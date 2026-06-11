# addons/godot_web3/nodes/internal/eth_network_manager.gd
class_name EthNetworkManager extends Node

signal connected
signal disconnected
signal node_rotated(new_url: String)
signal raw_subscription_notification(remote_id: String, result: Variant)

const Analyzer = preload("res://addons/godot_web3/nodes/internal/transport/eth_response_analyzer.gd")
const HTTP_Provider = preload("res://addons/godot_web3/nodes/internal/transport/eth_http_client.gd")
const WS_Provider = preload("res://addons/godot_web3/nodes/internal/transport/eth_ws_client.gd")

var _config: Dictionary
var _active_provider: Node = null
var _current_node_index: int = 0
var last_rpc_error: Dictionary = {}

# Контроль очереди (Concurrency)
var _active_tasks: int = 0
signal _slot_available

func _init(context: Node, config: Dictionary):
	_config = config
	# Добавляем менеджера в дерево сцены, чтобы он мог управлять таймерами и детьми
	context.add_child(self)
	_mount_provider()

func _mount_provider():
	# Мягкая замена провайдера
	if _active_provider:
		var old = _active_provider
		if old.has_method("abort_all"): 
			old.abort_all()
		
		# Старый провайдер не удаляется мгновенно, чтобы дать завершиться активным await.
		# Он удалится через 30 секунд.
		get_tree().create_timer(30.0).timeout.connect(func(): 
			if is_instance_valid(old): old.queue_free()
		)

	var url = _config.nodes[_current_node_index].strip_edges()
	
	# Извлекаем сырой текст заголовков по индексу
	var raw_headers_text = ""
	var headers_config = _config.get("node_headers", [])
	if _current_node_index < headers_config.size():
		raw_headers_text = headers_config[_current_node_index]
	
	# Парсим текст в PackedStringArray ("Key: Value")
	var parsed_headers = _parse_headers(raw_headers_text)

	var is_ws = url.begins_with("ws")
	
	if is_ws:
		_active_provider = WS_Provider.new()
		_active_provider.ws_url = url
		_active_provider.handshake_headers = parsed_headers
		_active_provider.ping_interval = _config.get("ws_ping_interval", 30.0)
		_active_provider.inbound_buffer_size_mb = _config.get("ws_buffer_size", 4)
	else:
		_active_provider = HTTP_Provider.new()
		_active_provider.http_url = url
		_active_provider.custom_headers = parsed_headers # Передаем в HTTP
		_active_provider.subs_enabled = _config.get("http_subs_enabled", true)
		_active_provider.poll_interval = _config.get("http_poll_interval", 5.0)
		_active_provider.auto_stop_enabled = _config.get("http_auto_stop", true)
	
	_active_provider.verbose_logs = _config.verbose
	_active_provider.request_timeout = _config.timeout
	
	# Подключаем сигналы текущего провайдера
	if _active_provider.has_signal("connected"):
		_active_provider.connected.connect(func(): connected.emit())
	if _active_provider.has_signal("disconnected"):
		_active_provider.disconnected.connect(func(): disconnected.emit())
	if _active_provider.has_signal("subscription_event"):
		_active_provider.subscription_event.connect(func(id, res): 
			raw_subscription_notification.emit(id, res)
		)

	add_child(_active_provider)
	
	if _active_provider.has_method("connect_to_host"):
		_active_provider.connect_to_host()

# Вспомогательная функция парсинга заголовков
func _parse_headers(text: String) -> PackedStringArray:
	var result: PackedStringArray = []
	var lines = text.split("\n")
	for line in lines:
		var clean_line = line.strip_edges()
		if clean_line.is_empty() or not ":" in clean_line:
			continue
		result.append(clean_line)
	return result

# --- Public API (Шлюз запросов) ---

func request(method: String, params: Array) -> Variant:
	# 1. Ограничение конкурентности (Semaphore)
	if _active_tasks >= _config.max_concurrency:
		await _slot_available
	
	_active_tasks += 1
	var result = await _do_request_with_retries(method, params)
	_active_tasks -= 1
	
	_slot_available.emit()
	return result

func _do_request_with_retries(method: String, params: Array) -> Variant:
	var failures = 0
	var nodes_count = _config.nodes.size()
	var total_allowed = nodes_count * _config.retries
	if total_allowed == 0: total_allowed = 1
	
	while failures < total_allowed:
		var p = _active_provider
		if not is_instance_valid(p): return null
		
		# Выполняем запрос через текущего исполнителя
		var response = await p.request(method, params, randi())
		
		# Обработка плановой ротации (abort_all возвращает -1)
		if response is Dictionary and response.get("http_code") == -1:
			failures += 1
			# Небольшая пауза, чтобы новый провайдер успел подхватить работу
			await get_tree().create_timer(0.05).timeout
			continue 

		# Анализ ответа
		var analysis = Analyzer.analyze(response.rpc_raw, response.http_code)
		
		match analysis.verdict:
			Analyzer.Verdict.OK:
				last_rpc_error = {} # Сброс ошибки при успехе
				return analysis.data
			Analyzer.Verdict.FATAL:
				last_rpc_error = analysis.error if analysis.error else {"message": analysis.message}
				return null # Возвращаем null, чтобы не ломать типы данных
			Analyzer.Verdict.RETRY:
				if _active_provider == p:
					_rotate_node()
				failures += 1
				await get_tree().create_timer(_config.delay).timeout
				
	return null

func _rotate_node() -> bool:
	if _config.nodes.size() <= 1: return false
	_current_node_index = (_current_node_index + 1) % _config.nodes.size()
	_mount_provider()
	node_rotated.emit(_config.nodes[_current_node_index])
	return true

## Обновляет список нод и заголовков "на лету" и переподключается
func update_node_list(new_nodes: Array[String], new_headers: Array[String]):
	if new_nodes.is_empty():
		push_error("EthNetworkManager: Cannot update node list with empty array.")
		return

	# Обновляем конфигурацию
	_config["nodes"] = new_nodes
	_config["node_headers"] = new_headers
	
	# Сбрасываем индекс на начало (или можно оставить 0)
	_current_node_index = 0
	
	# Принудительно пересоздаем провайдер с новыми настройками
	_mount_provider()
	
	# Опционально: сообщаем, что произошла ротация (на первую ноду нового списка)
	node_rotated.emit(new_nodes[0])

# --- Подписки (Прямые вызовы провайдера) ---

func start_subscription_direct(params: Array) -> String:
	if _active_provider and _active_provider.has_method("start_subscription"):
		return await _active_provider.start_subscription(params, randi())
	return ""

func stop_subscription_direct(remote_id: String) -> bool:
	if _active_provider and _active_provider.has_method("stop_subscription"):
		return await _active_provider.stop_subscription(remote_id, randi())
	return false
