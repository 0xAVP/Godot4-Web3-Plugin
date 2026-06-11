class_name EthNonceManager extends RefCounted

signal updated(val: int)

var _current: int = -1
var _auto_fetch: bool = true
var _is_syncing: bool = false

func _init(auto_fetch: bool):
	_auto_fetch = auto_fetch

func get_current() -> int:
	return _current

func reset():
	_current = -1

func increment():
	if _current != -1:
		_current += 1
		updated.emit(_current)

func decrement():
	if _current > 0:
		_current -= 1
		updated.emit(_current)

## Принудительная синхронизация с сетью.
## Если forwarder_addr пустой — берем системный nonce аккаунта.
## Если указан адрес — вызываем метод nonces(address) у контракта.
func sync(client: EthClient, address: String, force: bool = false, forwarder_addr: String = "") -> int:
	if not client or address.is_empty():
		return -1
	
	var net_nonce: int = -1
	
	if forwarder_addr.is_empty():
		# Путь Wallet (обычный RPC запрос)
		net_nonce = await client.get_transaction_count(address, "latest")
	else:
		# Путь Relayer (через eth_call к контракту)
		var selector = W3ABI.encode_function_selector("nonces(address)")
		var encoded_addr = W3ABI.encode_params(["address"], [address])
		var calldata = W3Utils.bytes_to_hex(selector + encoded_addr)
		
		var res = await client.request("eth_call", [{
			"to": forwarder_addr, 
			"data": calldata
		}, "latest"])
		if res != null and str(res) != "0x":
			# Используем W3BigInt, потому что eth_call возвращает 32 байта данных.
			# Обычный hex_to_int может не переварить такую длинную строку.
			var bi = W3BigInt.from_hex(str(res))
			net_nonce = int(bi.to_string_val())
		# ------------------------------------
	
	if net_nonce != -1:
		if force or net_nonce > _current:
			_current = net_nonce
			updated.emit(_current)
		
	return _current
## Возвращает nonce для следующей транзакции. 
func ensure_synced(client: EthClient, address: String, forwarder_addr: String = "") -> int:
	if _current != -1:
		return _current
	
	if _is_syncing:
		while _is_syncing:
			await client.get_tree().process_frame
		return _current
		
	_is_syncing = true
	var res = await sync(client, address, false, forwarder_addr)
	_is_syncing = false
	return res
