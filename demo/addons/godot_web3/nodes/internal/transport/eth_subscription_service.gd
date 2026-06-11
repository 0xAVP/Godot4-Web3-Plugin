# addons/godot_web3/nodes/internal/eth_subscription_service.gd
class_name EthSubscriptionService extends RefCounted

signal event(local_id: String, result: Variant)
signal recovered(local_id: String, new_remote_id: String)

var _net: EthNetworkManager
var _db: RefCounted # eth_subscription_manager.gd (просто хранилище данных)
var _verbose: bool = false

func _init(net: EthNetworkManager, verbose: bool):
	_net = net
	_verbose = verbose
	# Загружаем существующий менеджер (базу данных ID)
	_db = preload("res://addons/godot_web3/nodes/internal/transport/eth_subscription_manager.gd").new()
	
	# Слушаем сеть
	_net.connected.connect(_on_network_recovery)
	_net.raw_subscription_notification.connect(_on_incoming_data)

# --- Public API ---

func subscribe(params: Array) -> String:
	# 1. Запрос в сеть
	var remote_id = await _net.start_subscription_direct(params)
	if not remote_id.is_empty():
		# 2. Регистрация в локальной базе
		return _db.register(remote_id, params)
	return ""

func unsubscribe(local_id: String) -> bool:
	var subs = _db.get_all_subs()
	if not subs.has(local_id): return false
	
	var remote_id = subs[local_id].remote_id
	
	# 1. Отмена в сети
	var success = await _net.stop_subscription_direct(remote_id)
	
	# 2. Удаление из базы (в любом случае)
	_db.remove_local(local_id)
	return success

# --- Logic: Incoming Data ---

func _on_incoming_data(remote_id: String, result: Variant):
	var local_id = _db.get_local_id(remote_id)
	
	# Если ID не найден (возможно, устаревшая подписка), используем remote_id как фоллбэк
	var emit_id = local_id if not local_id.is_empty() else remote_id
	
	# Обработка массивов (batch logs)
	if result is Array:
		for item in result:
			_process_single_item(emit_id, local_id, item)
	else:
		_process_single_item(emit_id, local_id, result)

func _process_single_item(emit_id: String, local_id: String, item: Variant):
	# Трекинг последнего блока для Gap Filling
	if item is Dictionary and not local_id.is_empty():
		var bn_hex = ""
		if item.has("blockNumber"): bn_hex = item.blockNumber
		elif item.has("number"): bn_hex = item.number
		
		if not bn_hex.is_empty():
			_db.update_last_block(local_id, W3Utils.hex_to_int(bn_hex))
			
	emit_signal("event", emit_id, item)

# --- Logic: Recovery & Gap Filling ---

func _on_network_recovery():
	var active_subs = _db.get_all_subs()
	if active_subs.is_empty(): return
	
	if _verbose: print("[EthService] Network restored. Recovering %d subscriptions..." % active_subs.size())
	
	# Получаем текущий блок, чтобы знать, до куда докачивать
	var block_res = await _net.request("eth_blockNumber", [])
	var current_net_block = 0
	if block_res:
		current_net_block = W3Utils.hex_to_int(block_res)
	
	# Итерируемся по копии ключей
	var keys = active_subs.keys()
	for local_id in keys:
		var cfg = active_subs[local_id]
		
		# 1. Resubscribe
		var new_remote_id = await _net.start_subscription_direct(cfg.params)
		
		if not new_remote_id.is_empty():
			_db.update_remote_id(local_id, new_remote_id)
			emit_signal("recovered", local_id, new_remote_id)
			
			# 2. Gap Fill Check
			var last_seen_block = cfg.last_block
			# Логика запускается только для подписок на "logs" и если мы видели блоки ранее
			if cfg.params.size() >= 1 and cfg.params[0] == "logs" and last_seen_block > 0 and current_net_block > last_seen_block:
				var filter = cfg.params[1] if cfg.params.size() > 1 else {}
				# Запускаем в фоне
				_fill_gap(local_id, last_seen_block + 1, current_net_block, filter)

func _fill_gap(local_id: String, from_blk: int, to_blk: int, filter: Dictionary):
	if _verbose: print("[EthService] Backfilling %s: blocks %d -> %d" % [local_id, from_blk, to_blk])
	
	var query = filter.duplicate()
	query["fromBlock"] = W3Utils.int_to_hex(from_blk)
	query["toBlock"] = W3Utils.int_to_hex(to_blk)
	
	# Используем обычный request, чтобы получить пропущенные логи
	var logs = await _net.request("eth_getLogs", [query])
	
	if logs is Array and not logs.is_empty():
		# Эмулируем приход данных
		# Нам нужен актуальный remote_id, чтобы система подумала, что это пришло из сокета
		var current_remote = _db._subs[local_id].remote_id
		for log_item in logs:
			_on_incoming_data(current_remote, log_item)
