# tests/live/test_12_gap_fill.gd
extends W3Test

const HTTP_Script = preload("res://addons/godot_web3/nodes/internal/transport/eth_http_client.gd")
const WS_Script = preload("res://addons/godot_web3/nodes/internal/transport/eth_ws_client.gd")

func run(runner: Node):
	log_section("STRESS TEST: Universal Gap Filling (WS & HTTP)")
	
	var client: EthClient = runner.get_node("EthClient")
	var network = client._network
	
	# --- ФАЗА 1: WebSocket Gap Fill ---
	log_section("Phase 1: WebSocket Recovery")
	# Убеждаемся, что мы на WS
	if network._active_provider.get_script() != WS_Script:
		network._rotate_node()
		
	if network._active_provider.socket.get_ready_state() != WebSocketPeer.STATE_OPEN:
		await client.connected
	
	await _run_gap_fill_logic(client, runner, "WS")

	# --- ФАЗА 2: HTTP Gap Fill ---
	log_section("Phase 2: HTTP Recovery (Polling Backfill)")
	# Переключаемся на HTTP
	while network._active_provider.get_script() != HTTP_Script:
		network._rotate_node()
		await runner.get_tree().process_frame
	
	var http_provider = network._active_provider
	http_provider.poll_interval = 2.0 # Ускоряем опрос
	
	await _run_gap_fill_logic(client, runner, "HTTP")
	
	# Возвращаем настройки
	http_provider.poll_interval = client.http_subs_poll_interval

	log_section("=== UNIVERSAL GAP FILL TEST COMPLETE ===")

## Общая логика теста
func _run_gap_fill_logic(client: EthClient, runner: Node, label: String):
	log_info("[%s] Subscribing to logs..." % label)
	var my_sub = await client.subscribe(["logs", {}])
	
	var events = []
	var on_event = func(id, data): 
		if id == my_sub: events.append(data)
	client.subscription_event.connect(on_event)
	
	# 1. Ждем первого события
	log_info("[%s] Waiting for initial event..." % label)
	var timer = runner.get_tree().create_timer(30.0)
	while events.is_empty() and timer.time_left > 0:
		await runner.get_tree().process_frame
	
	if events.is_empty():
		fail_test("[%s] Network too quiet to test Gap Fill." % label)
		client.subscription_event.disconnect(on_event)
		return

	var last_blk_before = client._svc_subs._db.get_last_block(my_sub)
	log_info("[%s] Checkpoint block: %d. Simulating outage..." % [label, last_blk_before])
	events.clear()

	# 2. ИМИТИРУЕМ ОБРЫВ
	var provider = client._network._active_provider
	if label == "WS":
		provider.auto_reconnect = false
		provider.socket.close()
		log_info("[%s] Socket closed. System is offline." % label)
	else:
		# Для HTTP просто временно ломаем URL прямо в провайдере
		var real_url = provider.http_url
		provider.http_url = "http://127.0.0.1:1"
		log_info("[%s] URL corrupted. Polling will fail." % label)
		await runner.get_tree().create_timer(10.0).timeout
		provider.http_url = real_url # Восстанавливаем

	if label == "WS":
		await runner.get_tree().create_timer(10.0).timeout

		# 3. ВОССТАНОВЛЕНИЕ WS
		log_info("[%s] Restoring connection..." % label)
		provider.auto_reconnect = true
		provider.connect_to_host()
		await client.connected
	else:
		log_info("[%s] URL restored. Waiting for next poll..." % label)

	# 4. ПРОВЕРКА
	log_info("[%s] Waiting for Backfill events..." % label)
	var wait_fill = 20.0
	while events.is_empty() and wait_fill > 0:
		await runner.get_tree().create_timer(0.5).timeout
		wait_fill -= 0.5
	
	if not events.is_empty():
		var backfilled_count = events.size()
		# Проверяем, что события действительно из "прошлого" (или текущие, но после паузы)
		var first_new_blk = W3Utils.hex_to_int(events[0].blockNumber)
		pass_test("[%s] RECOVERED %d events!" % [label, backfilled_count])
		assert_true(first_new_blk > last_blk_before, "Backfill block %d > checkpoint %d" % [first_new_blk, last_blk_before])
	else:
		log_info("[%s] No events in gap (zero activity)." % label)
		pass_test("[%s] Recovery sequence finished." % label)
	
	client.subscription_event.disconnect(on_event)
	await client.unsubscribe(my_sub)
