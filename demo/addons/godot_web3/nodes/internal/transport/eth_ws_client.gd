# addons/godot_web3/nodes/internal/eth_ws_client.gd
extends EthRpcProvider

signal connected
signal disconnected
signal subscription_event(sub_id: String, result: Variant)
signal _rpc_response_received

var ws_url: String = ""
var handshake_headers: PackedStringArray = []
var auto_reconnect: bool = true
var inbound_buffer_size_mb: int = 4
var ping_interval: float = 30.0
var _time_since_last_msg: float = 0.0
var socket := WebSocketPeer.new()
var _last_state := WebSocketPeer.STATE_CLOSED
var _pending_requests: Dictionary = {}

func get_class_name(): return "EthWsClient"

func _ready():
	socket.inbound_buffer_size = inbound_buffer_size_mb * 1024 * 1024 
	socket.max_queued_packets = 2048

func abort_all():
	super.abort_all() # Вызывает _is_aborted = true из базы
	_fail_all_pending("Provider Aborted")
	socket.close()

func connect_to_host() -> Error:
	if ws_url.is_empty(): return ERR_INVALID_PARAMETER
	socket.close()
	_last_state = WebSocketPeer.STATE_CLOSED
	socket.handshake_headers = handshake_headers
	
	# Если это WSS, создаем дефолтные опции клиента
	var tls = null
	if ws_url.begins_with("wss"):
		tls = TLSOptions.client()
		
	return socket.connect_to_url(ws_url, tls)

func _process(delta):
	socket.poll()
	var state = socket.get_ready_state()
	
	if state != _last_state:
		var old_state = _last_state
		_last_state = state
		if state == WebSocketPeer.STATE_OPEN: 
			connected.emit()
			_time_since_last_msg = 0.0 # Сбрасываем при открытии
		elif state == WebSocketPeer.STATE_CLOSED:
			disconnected.emit()
			_fail_all_pending("Socket closed")
			if auto_reconnect and not _is_aborted and old_state != WebSocketPeer.STATE_CONNECTING:
				get_tree().create_timer(2.0).timeout.connect(func(): if not _is_aborted: connect_to_host())

	# Вызываем логику пинга только если соединение открыто
	if state == WebSocketPeer.STATE_OPEN:
		_process_ping(delta)

	while socket.get_available_packet_count() > 0:
		# ВАЖНО: Сбрасываем таймер здесь. 
		# Если нода прислала любое сообщение (ответ или блок), пинг не нужен.
		_time_since_last_msg = 0.0 
		
		_handle_message(socket.get_packet())

func _process_ping(delta):
	if ping_interval <= 0: return
	
	_time_since_last_msg += delta
	if _time_since_last_msg >= ping_interval:
		_time_since_last_msg = 0.0
		_send_rpc_ping()

func _send_rpc_ping():
	if verbose_logs: print("[EthWsClient] Sending keep-alive ping...")
	# Используем net_version, так как это константный ответ, не требующий вычислений на ноде
	# Мы не используем await, чтобы не блокировать поток, просто "выстрелил и забыл"
	# Используем специальный ID (например, 999999999), чтобы не путать с обычными запросами
	var payload = _prepare_payload("net_version", [], 999999999)
	socket.send_text(payload)

func request(method: String, params: Array = [], r_id: int = 0) -> Dictionary:
	if _is_aborted: return _wrap_response(null, -1)
	if socket.get_ready_state() == WebSocketPeer.STATE_CONNECTING: await connected
	if _is_aborted: return _wrap_response(null, -1)
	if socket.get_ready_state() != WebSocketPeer.STATE_OPEN: return _wrap_response(null, 0)

	var payload = _prepare_payload(method, params, r_id)
	var err = socket.send_text(payload)
	if err != OK: return _wrap_response(null, 0)

	_pending_requests[r_id] = {"result": null, "done": false}
	
	var start_time = Time.get_ticks_msec()
	while _pending_requests.has(r_id) and not _pending_requests[r_id].done:
		await _rpc_response_received
		if _is_aborted: break
		if (Time.get_ticks_msec() - start_time) > (request_timeout * 1000.0):
			_pending_requests.erase(r_id)
			return _wrap_response(null, 408)
	
	if _is_aborted:
		_pending_requests.erase(r_id)
		return _wrap_response(null, -1)
		
	var data = _pending_requests[r_id].result
	_pending_requests.erase(r_id)
	
	# Формируем стандартный JSON-RPC объект для анализатора
	var rpc_raw = data if (data is Dictionary and (data.has("error") or data.has("result"))) else {"result": data}
	return _wrap_response(rpc_raw, 200)

# Методы подписок тоже используют _wrap_response для красоты
func start_subscription(params: Array, r_id: int = 0) -> String:
	var res = await request("eth_subscribe", params, r_id)
	return str(res.rpc_raw.result) if res.rpc_raw and res.rpc_raw.has("result") else ""

func stop_subscription(remote_id: String, r_id: int = 0) -> bool:
	var res = await request("eth_unsubscribe", [remote_id], r_id)
	return bool(res.rpc_raw.result) if res.rpc_raw and res.rpc_raw.has("result") else false

func _handle_message(packet: PackedByteArray):
	var json = JSON.parse_string(packet.get_string_from_utf8())
	if not json is Dictionary: return
	
	if json.has("id"):
		var id = int(json["id"])
		if id == 999999999: 
			if verbose_logs: print("[EthWsClient] Pong received (net_version)")
			return # Это был наш пинг, ничего делать не нужно
			
		if _pending_requests.has(id):
			_pending_requests[id].result = json.get("error", json.get("result"))
			_pending_requests[id].done = true
			_rpc_response_received.emit()
	elif json.has("method") and json["method"] == "eth_subscription":
		var p = json.get("params", {})
		subscription_event.emit(p.get("subscription"), p.get("result"))

func _fail_all_pending(reason: String):
	for id in _pending_requests.keys():
		_pending_requests[id].result = {"error": {"code": -1, "message": reason}}
		_pending_requests[id].done = true
	_rpc_response_received.emit()
