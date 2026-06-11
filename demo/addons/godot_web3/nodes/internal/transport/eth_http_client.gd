extends EthRpcProvider

signal subscription_event(sub_id: String, result: Variant)

var http_url: String = ""
var custom_headers: PackedStringArray = []
# Настройки из инспектора через менеджер
var subs_enabled: bool = true
var poll_interval: float = 5.0
var auto_stop_enabled: bool = true

var _virtual_subs: Dictionary = {}
var _sub_counter: int = 0
var _last_polled_block: int = -1
var _is_polling: bool = false

func get_class_name(): return "EthHttpClient"

func abort_all():
	super.abort_all()
	_virtual_subs.clear()
	_is_polling = false

func request(method: String, params: Array, r_id: int) -> Dictionary:
	if _is_aborted: return _wrap_response(null, -1)
	
	var http = HTTPRequest.new()
	http.timeout = request_timeout
	add_child(http)
	
	var payload = _prepare_payload(method, params, r_id)
	
	# Формируем финальные заголовки
	var final_headers = custom_headers.duplicate()
	
	# Проверяем, не забыл ли пользователь Content-Type
	var has_ctype = false
	for h in final_headers:
		if h.to_lower().begins_with("content-type:"):
			has_ctype = true
			break
	if not has_ctype:
		final_headers.append("Content-Type: application/json")
	
	var err = http.request(http_url, final_headers, HTTPClient.METHOD_POST, payload)
	
	if err != OK:
		http.queue_free()
		return _wrap_response(null, 0)
		
	var res = await http.request_completed
	if is_instance_valid(http): http.queue_free()
	if _is_aborted: return _wrap_response(null, -1)
		
	var rpc_raw = null
	if res[0] == HTTPRequest.RESULT_SUCCESS and res[1] == 200:
		rpc_raw = JSON.parse_string(res[3].get_string_from_utf8())
		
	return _wrap_response(rpc_raw, res[1])

# --- Оптимизированные подписки (Low CU Cost) ---

func start_subscription(params: Array, _r_id: int) -> String:
	if not subs_enabled:
		if verbose_logs: print("[EthHttpClient] Subscription ignored: HTTP polling is disabled.")
		return ""
		
	_sub_counter += 1
	var sub_id = "vsub_" + str(_sub_counter)
	
	_virtual_subs[sub_id] = {
		"type": params[0],
		"params": params[1] if params.size() > 1 else {}
	}
	
	if not _is_polling:
		_start_master_poll_loop()
		
	return sub_id

func stop_subscription(sub_id: String, _r_id: int) -> bool:
	var erased = _virtual_subs.erase(sub_id)
	
	# Авто-стоп срабатывает только если настройка включена
	if auto_stop_enabled and _virtual_subs.is_empty():
		if verbose_logs: print("[EthHttpClient] Auto-stopping poll loop (no active subs).")
		_is_polling = false
		
	return erased

func _start_master_poll_loop():
	_is_polling = true
	if verbose_logs: print("[EthHttpClient] Master Poll Loop started (Interval: %.1fs)" % poll_interval)
	
	while _is_polling and not _is_aborted:
		await _perform_shared_poll()
		
		# Если во время выполнения poll мы решили остановиться
		if not _is_polling: break
		
		await get_tree().create_timer(poll_interval).timeout


## Главная функция экономии Compute Units
func _perform_shared_poll():
	# 1. Сначала узнаем текущую высоту (самый дешевый запрос - eth_blockNumber)
	var bn_res = await request("eth_blockNumber", [], randi())
	if not bn_res.rpc_raw or not bn_res.rpc_raw.has("result"): return
	
	var current_bn = W3Utils.hex_to_int(bn_res.rpc_raw.result)
	
	# Инициализация при первом запуске
	if _last_polled_block == -1:
		_last_polled_block = current_bn
		return

	# Если блок не изменился — выходим. МЫ СЭКОНОМИЛИ CU на всех остальных запросах!
	if current_bn <= _last_polled_block:
		return
		
	var from_blk = _last_polled_block + 1
	var to_blk = current_bn
	
	# 2. Если блок изменился, собираем данные для активных подписок
	var cached_block_data = null
	
	# Итерируемся по копии ключей (безопасно при удалении)
	for sub_id in _virtual_subs.keys():
		var sub = _virtual_subs.get(sub_id)
		if not sub: continue
		
		match sub.type:
			"newHeads":
				# Скачиваем блок только один раз за тик, даже если подписок много
				if cached_block_data == null:
					var b_res = await request("eth_getBlockByNumber", [W3Utils.int_to_hex(to_blk), false], randi())
					if b_res.rpc_raw: cached_block_data = b_res.rpc_raw.result
				
				if cached_block_data:
					subscription_event.emit(sub_id, cached_block_data)
					
			"logs":
				# Для логов используем eth_getLogs на диапазон пропущенных блоков
				var filter = sub.params.duplicate()
				filter["fromBlock"] = W3Utils.int_to_hex(from_blk)
				filter["toBlock"] = W3Utils.int_to_hex(to_blk)
				
				var l_res = await request("eth_getLogs", [filter], randi())
				if l_res.rpc_raw and l_res.rpc_raw.has("result"):
					for log_item in l_res.rpc_raw.result:
						subscription_event.emit(sub_id, log_item)

	_last_polled_block = current_bn
