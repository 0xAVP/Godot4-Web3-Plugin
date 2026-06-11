# tests/live/test_14_http_subs.gd
extends W3Test

const HTTP_Script = preload("res://addons/godot_web3/nodes/internal/transport/eth_http_client.gd")

func run(runner: Node):
	log_section("UNIT TEST: HTTP Virtual Subscriptions (Polling)")
	
	var client: EthClient = runner.get_node("EthClient")
	var network = client._network
	
	# 1. Переключаемся на HTTP, если мы на WS
	if not network._active_provider.get_script() == HTTP_Script:
		log_info("Switching to HTTP node for test...")
		network._rotate_node()
		await runner.get_tree().process_frame
	
	var provider = network._active_provider
	log_info("Testing on node: %s" % provider.http_url)

	# --- ТЕСТ 1: Проверка выключенного состояния ---
	log_section("Test 1: Disabled Subscriptions")
	provider.subs_enabled = false
	var sub_fail = await client.subscribe(["newHeads"])
	assert_eq(sub_fail, "", "Subscribe returns empty string when disabled")

	# --- ТЕСТ 2: Успешный опрос (Polling) ---
	log_section("Test 2: Basic Polling (newHeads)")
	provider.subs_enabled = true
	provider.poll_interval = 2.0 # Ускоряем для теста
	provider.verbose_logs = true
	
	var sub_id = await client.subscribe(["newHeads"])
	assert_true(!sub_id.is_empty(), "Virtual subscription started. ID: %s" % sub_id)
	
	if !sub_id.is_empty():
		log_info("Waiting for at least one block event (timeout 30s)...")
		var event_data = {"received": false}
		var on_event = func(id, data):
			if id == sub_id: event_data.received = true
		
		client.subscription_event.connect(on_event)
		
		# Ждем события или таймаута
		var wait_timer = 30.0
		while !event_data.received and wait_timer > 0:
			await runner.get_tree().create_timer(1.0).timeout
			wait_timer -= 1.0
		
		client.subscription_event.disconnect(on_event)
		assert_true(event_data.received, "Received block data via HTTP Polling")

	# --- ТЕСТ 3: Авто-стоп (CU Saving) ---
	log_section("Test 3: Auto-Stop Integrity")
	provider.auto_stop_enabled = true
	
	assert_true(provider._is_polling, "Poll loop is currently ACTIVE")
	
	log_info("Unsubscribing from %s..." % sub_id)
	await client.unsubscribe(sub_id)
	
	# Даем время циклу осознать пустую очередь
	await runner.get_tree().create_timer(1.0).timeout
	
	assert_true(!provider._is_polling, "Poll loop AUTO-STOPPED correctly (CU saved)")

	# Возвращаем стандартные настройки
	provider.poll_interval = client.http_subs_poll_interval
	log_section("=== HTTP SUBSCRIPTIONS TEST COMPLETE ===")
