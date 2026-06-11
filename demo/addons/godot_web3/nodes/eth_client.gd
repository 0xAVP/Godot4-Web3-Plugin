@icon("res://addons/godot_web3/icons/icon.svg")
class_name EthClient extends Node

# --- Signals ---
signal connected
signal disconnected
signal node_rotated(new_url: String)
signal subscription_event(sub_id: String, result: Variant)
signal subscription_recovered(local_id: String, new_remote_id: String)

# --- Exports ---
@export_group("Network")
## ID блокчейн-сети (например: 1 - Mainnet, 11155111 - Sepolia). Используется для подписи транзакций.
@export var chain_id: int = 1
## Список URL адресов RPC узлов (поддерживаются http/https и ws/wss).
@export var rpc_nodes: Array[String] = []
## Заголовки для каждой ноды (соответствуют индексу в rpc_nodes).
## Пишите в формате: 
## Key1: Value1
## Key2: Value2
@export_multiline var rpc_node_headers: Array[String] = []

@export_group("Performance")
## Максимальное количество одновременных запросов (Concurrency Limit). 
## Ограничивает нагрузку на сеть и RPC-узел. Лишние запросы встают в очередь.
@export var max_concurrency: int = 6

@export_group("Settings")
## Количество ПОЛНЫХ циклов прохода по всем узлам списка перед тем, как признать запрос неудавшимся.
@export var max_retries: int = 3
## Максимальное время ожидания ответа на один запрос (в секундах).
@export var request_timeout: float = 10.0
## Пауза (в секундах) перед переключением на следующий узел после ошибки транспорта.
@export var rotation_delay: float = 0.5   
## Если включено, в консоль Godot будут выводиться детальные логи всех запросов и ответов.
@export var verbose_logs: bool = false

@export_group("WS:")
## Размер входящего буфера WebSocket (в Мегабайтах). Увеличьте, если получаете очень тяжелые блоки или много логов.
@export var ws_buffer_size_mb: int = 4
## Интервал пинга для WebSocket (в секундах). 0 - отключить.
## Помогает избежать разрыва соединения провайдером при простое.
@export var ws_ping_interval: float = 30.0

@export_group("HTTP:")
## Разрешить эмуляцию подписок (polling) при использовании HTTP узлов.
@export var http_subs_enabled: bool = true
## Интервал опроса узла (в секундах). Чем меньше значение, тем выше расход Compute Units (CU).
@export var http_subs_poll_interval: float = 5.0
## Если включено, опрос прекращается автоматически, когда нет активных подписчиков.
@export var http_subs_auto_stop: bool = true

# --- Internal Modules (Private by convention) ---
var _network: EthNetworkManager
var _svc_subs: EthSubscriptionService

func _ready():
	var net_config = {
		"nodes": rpc_nodes,
		"node_headers": rpc_node_headers,
		"chain_id": chain_id,
		"verbose": verbose_logs,
		"retries": max_retries,
		"timeout": request_timeout,
		"delay": rotation_delay,
		"max_concurrency": max_concurrency,
		"ws_buffer_size": ws_buffer_size_mb,
		"http_subs_enabled": http_subs_enabled,
		"http_poll_interval": http_subs_poll_interval,
		"http_auto_stop": http_subs_auto_stop,
		"ws_ping_interval": ws_ping_interval
	}
	
	# 2. Initialize Transport Layer
	_network = EthNetworkManager.new(self, net_config)
	
	# Wire Network Signals
	_network.connected.connect(func(): emit_signal("connected"))
	_network.disconnected.connect(func(): emit_signal("disconnected"))
	_network.node_rotated.connect(func(url): emit_signal("node_rotated", url))
	
	# 3. Initialize Service Layer
	_svc_subs = EthSubscriptionService.new(_network, verbose_logs)
	
	# Wire Service Signals
	_svc_subs.event.connect(func(id, res): emit_signal("subscription_event", id, res))
	_svc_subs.recovered.connect(func(l, r): emit_signal("subscription_recovered", l, r))


## Полностью заменяет список RPC узлов и их заголовков.
func set_nodes(new_urls: Array[String], new_headers: Array[String] = []) -> void:
	if new_urls.is_empty():
		push_error("EthClient: Node list cannot be empty.")
		return
	# Обновляем локальные переменные для инспектора
	rpc_nodes = new_urls
	rpc_node_headers = new_headers
	# Передаем в менеджер
	if _network:
		_network.update_node_list(rpc_nodes, rpc_node_headers)

# --- Public API (Facade) ---

func request(method: String, params: Array = []) -> Variant:
	if not _network: return null
	return await _network.request(method, params)

func subscribe(params: Array) -> String:
	if not _svc_subs: return ""
	return await _svc_subs.subscribe(params)

func unsubscribe(local_id: String) -> bool:
	if not _svc_subs: return false
	return await _svc_subs.unsubscribe(local_id)

# --- High Level Helpers ---

func get_block_number() -> int:
	var res = await request("eth_blockNumber", [])
	if res: return W3Utils.hex_to_int(res)
	return -1

func get_balance(address: String, block_tag: String = "latest") -> W3BigInt:
	var res = await request("eth_getBalance", [address, block_tag])
	if res: return W3BigInt.from_hex(res)
	return W3BigInt.from_int(0)

func get_transaction_count(address: String, block_tag: String = "latest") -> int:
	var res = await request("eth_getTransactionCount", [address, block_tag])
	if res: return W3Utils.hex_to_int(res)
	return 0

func get_gas_price() -> W3BigInt:
	var res = await request("eth_gasPrice", [])
	if res: return W3BigInt.from_hex(res)
	return W3BigInt.from_int(0)

func send_raw_transaction(raw_hex: String) -> String:
	if not raw_hex.begins_with("0x"): raw_hex = "0x" + raw_hex
	var tx_hash = await request("eth_sendRawTransaction", [raw_hex])
	return str(tx_hash if tx_hash else "")

func wait_for_transaction(tx_hash: String, polling_interval: float = 2.0, timeout: float = 60.0) -> Dictionary:
	var start_time = Time.get_ticks_msec()
	while (Time.get_ticks_msec() - start_time) < (timeout * 1000.0):
		var receipt = await request("eth_getTransactionReceipt", [tx_hash])
		if receipt != null and typeof(receipt) == TYPE_DICTIONARY:
			return receipt
		await get_tree().create_timer(polling_interval).timeout
	return {}
