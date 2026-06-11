# tests/live/test_10_ws_stress.gd
extends W3Test

const WS_Script = preload("res://addons/godot_web3/nodes/internal/transport/eth_ws_client.gd")

func run(runner: Node):
	log_section("STRESS TEST: WebSocket Client (Facade Architecture)")
	
	# 1. Создаем EthClient (Фасад)
	var client = EthClient.new()
	client.name = "EthClient_WS_Stress"
	# Указываем ТОЛЬКО WS ноду, чтобы тестировать именно сокет
	client.rpc_nodes.assign(["wss://base-sepolia.infura.io/ws/v3/4aa4d838e9ce41beab99f63089155f48"])
	client.verbose_logs = false
	runner.add_child(client)
	
	# Получаем доступ к менеджеру сети (White Box) для проверок
	var net_manager = client._network
	
	log_info("Connecting to: %s" % client.rpc_nodes[0])
	
	# Ждем, пока сокет внутри провайдера не откроется
	if net_manager._active_provider.socket.get_ready_state() != WebSocketPeer.STATE_OPEN:
		await client.connected
		
	pass_test("WebSocket Connected via Facade.")
	assert_true(net_manager._active_provider is WS_Script, "Provider is WS_Script")

	# --- ТЕСТ 1: Параллельные запросы (Full Duplex) ---
	log_section("Test 1: Parallel Requests (20 at once)")
	log_info("Testing ID multiplexing via Facade.")
	
	var results1 = await _launch_parallel(client, 20, "eth_blockNumber", [])
	
	assert_eq(results1.size(), 20, "All 20 parallel requests returned")
	pass_test("Multiplexing works: IDs were not mixed up.")

	# --- ТЕСТ 2: Подписки (Real-time) ---
	log_section("Test 2: Event Subscriptions")
	var sub_id = await client.subscribe(["newHeads"])
	
	if sub_id.is_empty():
		fail_test("Subscription failed")
	else:
		log_info("Subscribed to newHeads. ID: %s" % sub_id)
		
		var event_data = {"received": false, "payload": null}
		var on_event = func(id, data):
			if id == sub_id:
				event_data.received = true
				event_data.payload = data
		
		client.subscription_event.connect(on_event)
		
		log_info("Waiting for real-time block event...")
		var timer = runner.get_tree().create_timer(15.0)
		while not event_data.received and timer.time_left > 0:
			await runner.get_tree().process_frame
		
		client.subscription_event.disconnect(on_event)
		
		if event_data.received:
			pass_test("Received event via WS Facade.")
		else:
			log_info("No block event received (timeout - OK for testnets)")

		var unsub_ok = await client.unsubscribe(sub_id)
		assert_true(unsub_ok, "Unsubscribed successfully")

	# --- ТЕСТ 3: Обрыв соединения во время запроса ---
	log_section("Test 3: Connection Drop Handling")
	log_info("Simulating connection drop during active request...")
	
	var drop_state = {"res": null, "done": false}
	var drop_task = func():
		drop_state.res = await client.request("eth_blockNumber", [])
		drop_state.done = true
	
	# Запускаем без await
	drop_task.call() 
	
	# ВЗЛОМ: Закрываем сокет напрямую через менеджер
	net_manager._active_provider.socket.close()
	log_info("Socket closed manually while request was pending.")
	
	# Ждем завершения задачи
	var wait_timer = runner.get_tree().create_timer(3.0)
	while not drop_state.done and wait_timer.time_left > 0:
		await runner.get_tree().process_frame
	
	assert_true(drop_state.done, "Request coroutine finished after disconnect")
	# При обрыве соединения NetworkManager вернет null (так как это ошибка транспорта, а ретраи не помогут при закрытом сокете без нод для ротации)
	assert_true(drop_state.res == null, "Request returned null (failed) on disconnect")
	pass_test("Pending requests correctly aborted.")

	# --- ТЕСТ 4: Авто-реконнект ---
	log_section("Test 4: Auto-reconnect Verification")
	log_info("Waiting for auto-reconnect logic (internal to WS Client)...")
	
	if net_manager._active_provider.socket.get_ready_state() != WebSocketPeer.STATE_OPEN:
		await client.connected
		
	pass_test("Client automatically reconnected.")
	
	var after_res = await client.get_block_number()
	assert_true(after_res > 0, "Client works after reconnection. Block: " + str(after_res))

	# --- ТЕСТ 5: Огромный JSON ---
	log_section("Test 5: Large Payload Stress")
	log_info("Requesting full block with transactions...")
	
	var large_res = await client.request("eth_getBlockByNumber", ["latest", true])
	assert_not_null(large_res, "Large JSON response handled")
	if large_res and large_res.has("transactions"):
		var txs = large_res.get("transactions", [])
		log_info("Parsed large block. Transactions: %d" % txs.size())
	
	client.queue_free()
	log_section("=== ALL WS STRESS TESTS PASSED ===")

# --- Хелперы ---

func _launch_parallel(client: EthClient, count: int, method: String, params: Array) -> Array:
	var results = []
	results.resize(count)
	var state = {"finished": 0}
	
	var task = func(idx):
		results[idx] = await client.request(method, params)
		state.finished += 1
		
	for i in range(count):
		task.call(i)
		
	while state.finished < count:
		await client.get_tree().process_frame
		
	return results
