@icon("res://addons/godot_web3/icons/icon.svg")
class_name EthAccount extends Node

# --- Сигналы ---
signal transaction_sent(hash: String)
signal nonce_updated(new_nonce: int)
enum RoutingMode { DIRECT, RELAYER }
# --- Настройки ---
@export_group("Routing")
## Режим отправки: напрямую в сеть или через Gasless Relayer
@export var routing_mode: RoutingMode = RoutingMode.DIRECT
## Путь к узлу EthRelayer (обязателен, если выбран режим RELAYER)
@export var relayer_path: NodePath
@export_group("Connections")
## Путь к узлу [EthClient] в дереве сцены.
## Необходим для отправки транзакций, оценки газа и получения nonce.
@export var client_path: NodePath
## Путь к узлу [EthWallet] в дереве сцены.
## Необходим для криптографической подписи транзакций. Без кошелька аккаунт работать не будет.
@export var wallet_path: NodePath
## Если [b]true[/b], при разблокировке кошелька аккаунт автоматически запросит актуальный Nonce (счетчик транзакций) из сети.
## Рекомендуется оставлять включенным для синхронизации с блокчейном.
@export var auto_fetch_nonce: bool = true

@export_group("Gas Management")
## Лимит газа. Если 0 — рассчитывается автоматически.
@export var gas_limit: int = 0 :
	set(v): gas_limit = v; if _gas_oracle: _gas_oracle.manual_limit = v
## Буфер газа в процентах (например, 15). 
## Добавляется к результату eth_estimateGas для защиты от "Out of Gas" при изменении состояния блокчейна.
@export_range(0, 100) var gas_buffer_percentage: int = 15 :
	set(v): gas_buffer_percentage = v; if _gas_oracle: _gas_oracle.buffer_pct = v
## Стратегия формирования цены (Fee Market).
@export_enum("legacy", "eip1559") var gas_strategy: String = "eip1559" :
	set(v): gas_strategy = v; if _gas_oracle: _gas_oracle.strategy = v

enum PriorityLevel { SLOW, MARKET, AGGRESSIVE }

## Уровень приоритета транзакции. Влияет на MaxPriorityFee (чаевые майнеру).
## SLOW: экономия, MARKET: стандарт, AGGRESSIVE: для быстрых транзакций.
@export var priority_level: PriorityLevel = PriorityLevel.MARKET :
	set(v): priority_level = v; if _gas_oracle: _gas_oracle.priority = v

# --- Internal ---
const NonceMgrScript = preload("res://addons/godot_web3/nodes/internal/account/eth_nonce_manager.gd")
const GasOracleScript = preload("res://addons/godot_web3/nodes/internal/account/eth_gas_oracle.gd")

var _nonce_mgr: RefCounted
var _gas_oracle: RefCounted

@onready var client: EthClient = get_node_or_null(client_path)
@onready var wallet: EthWallet = get_node_or_null(wallet_path)
@onready var relayer: EthRelayer = get_node_or_null(relayer_path)

func _ready():
	_nonce_mgr = NonceMgrScript.new(auto_fetch_nonce)
	_gas_oracle = GasOracleScript.new(gas_strategy, gas_buffer_percentage, gas_limit, priority_level)
	_nonce_mgr.updated.connect(func(val): nonce_updated.emit(val))
	
	if wallet:
		wallet.unlocked.connect(func(): _nonce_mgr.reset(); sync_nonce())
		if wallet.is_unlocked(): sync_nonce()

# --- Public API ---

func get_address() -> String:
	return wallet.get_address() if wallet else ""

func get_nonce() -> int:
	return _nonce_mgr.get_current()

func set_routing_mode(mode: RoutingMode) -> void:
	routing_mode = mode
	_nonce_mgr.reset()
	sync_nonce()

func sync_nonce() -> void:
	if not _validate_deps(): return
	var f_addr = relayer.forwarder_address if (routing_mode == RoutingMode.RELAYER and relayer) else ""
	await _nonce_mgr.sync(client, get_address(), true, f_addr)

func send_transaction(to: String, value: W3BigInt, data: PackedByteArray = PackedByteArray()) -> String:
	if not _validate_deps(): return ""
	
	if routing_mode == RoutingMode.RELAYER:
		return await _send_via_relayer(to, value, data)
	else:
		return await _send_via_direct(to, value, data)

# --- Private: Direct Path ---

func _send_via_direct(to: String, value: W3BigInt, data: PackedByteArray) -> String:
	var my_nonce = await _nonce_mgr.ensure_synced(client, get_address())
	if my_nonce == -1: return ""
	
	var nonce_to_use = my_nonce
	_nonce_mgr.increment()
	
	var fees = await _gas_oracle.fetch_fees(client)
	var est_params = { "from": get_address(), "value": value.to_hex() }
	if not to.is_empty(): est_params["to"] = to
	if not data.is_empty(): est_params["data"] = W3Utils.bytes_to_hex(data)
	
	var limit = await _gas_oracle.estimate_limit(client, est_params)
	if limit == 0: 
		_nonce_mgr.decrement()
		return ""

	var tx = _assemble_tx(to, value, data, nonce_to_use, limit, fees)
	var signed_hex = wallet.sign_transaction(tx)
	
	var tx_hash = await client.send_raw_transaction(signed_hex)
	if tx_hash.is_empty(): _nonce_mgr.decrement()
	else: transaction_sent.emit(tx_hash)
	return tx_hash

# --- Private: Relayer Path ---

func _send_via_relayer(to: String, value: W3BigInt, data: PackedByteArray) -> String:
	if not relayer:
		push_error("EthAccount: Relayer node not found for RELAYER mode")
		return ""

	# 1. Nonce из Форвардера
	var my_nonce = await _nonce_mgr.ensure_synced(client, get_address(), relayer.forwarder_address)
	if my_nonce == -1: return ""
	
	var nonce_to_use = my_nonce
	_nonce_mgr.increment()
	
	# 2. Gas Limit (в релейере это часто фиксированное значение или лимит)
	# Мы можем использовать оракул для оценки, чтобы релейер не упал по газу
	var est_params = { "from": get_address(), "value": value.to_hex(), "to": to, "data": W3Utils.bytes_to_hex(data) }
	var limit = await _gas_oracle.estimate_limit(client, est_params)
	if limit == 0: limit = 500000 # Fallback
	
	# 3. Подготовка EIP-712 Хеша
	var hash = relayer.get_request_hash(client, get_address(), to, data, nonce_to_use, limit, value)
	
	# 4. Подпись чистым кошельком (без префиксов)
	var signature = wallet.sign_raw_hash(hash)
	if signature.is_empty():
		_nonce_mgr.decrement()
		return ""
		
	# 5. Сборка JSON и отправка
	var req_dict = relayer.build_request_dict(get_address(), to, data, nonce_to_use, limit, value)
	var res = await relayer.send_relay_transaction(req_dict, signature)
	
	if res.is_empty():
		_nonce_mgr.decrement()
	else:
		# Если res начинается на queued_, это jobId, иначе это tx_hash
		transaction_sent.emit(res)
		
	return res

# --- Helpers ---

func _validate_deps() -> bool:
	return client and wallet and wallet.is_unlocked()

func _assemble_tx(to: String, value: W3BigInt, data: PackedByteArray, nonce: int, limit: int, fees: Dictionary) -> W3Transaction:
	var tx = W3Transaction.new()
	tx.set_chain_id(W3BigInt.from_int(client.chain_id))
	tx.set_nonce(W3BigInt.from_int(nonce))
	tx.set_value(value)
	tx.set_data(data)
	tx.set_gas_limit(W3BigInt.from_int(limit))
	if to.is_empty(): tx.set_creation()
	else: tx.set_to(to)
	tx.set_type(fees["type"])
	if fees.has("gas_price"): tx.set_gas_price(fees["gas_price"])
	if fees.has("max_fee_per_gas"):
		tx.set_max_fee_per_gas(fees["max_fee_per_gas"])
		tx.set_max_priority_fee_per_gas(fees["max_priority_fee_per_gas"])
	return tx
