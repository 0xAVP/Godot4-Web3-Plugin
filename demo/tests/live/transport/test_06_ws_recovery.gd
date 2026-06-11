# tests/live/test_11_ws_recovery.gd
extends W3Test

func run(runner: Node):
	log_section("STRESS TEST: Full Stack Auto-Recovery via EthClient")
	
	var client = EthClient.new()
	client.rpc_nodes.assign(["wss://base-sepolia.infura.io/ws/v3/4aa4d838e9ce41beab99f63089155f48"])
	runner.add_child(client)
	
	# Мониторим публичные сигналы EthClient
	client.connected.connect(func(): log_info("NETWORK: Connected (Handshake OK)"))
	client.disconnected.connect(func(): log_info("NETWORK: Disconnected"))
	client.subscription_recovered.connect(func(l_id, r_id): 
		log_info("RECOVERY: Local Sub %s re-mapped to remote %s" % [l_id, r_id])
	)

	await client.connected
	
	# 1. Создаем подписку
	var my_sub = await client.subscribe(["newHeads"])
	log_info("SYSTEM: Stable Local ID: %s" % my_sub)

	var state = {"received": false, "block": 0}
	var on_event = func(id, data):
		if id == my_sub:
			state.received = true
			state.block = W3Utils.hex_to_int(data.number)
			log_info("DATA: Received Block #%d via %s" % [state.block, id])

	client.subscription_event.connect(on_event)
	
	# 2. Ждем первый блок
	log_info("Waiting for initial stream...")
	var timer = runner.get_tree().create_timer(30.0)
	while not state.received and timer.time_left > 0:
		await runner.get_tree().process_frame
	
	assert_true(state.received, "Data stream started.")
	var block_before = state.block

	# 3. ИМИТИРУЕМ ОБРЫВ
	log_section("ACTION: KILLING CONNECTION")
	state.received = false
	# Мы лезем в транспорт только для имитации аварии
	client._network._active_provider.socket.close() 
	
	log_info("System is now in 'Wait & Recover' mode...")
	
	# 4. Ждем автоматического восстановления
	var final_timer = runner.get_tree().create_timer(40.0)
	while not state.received and final_timer.time_left > 0:
		await runner.get_tree().process_frame
		
	assert_true(state.received, "Data stream resumed automatically after reconnect.")
	
	if state.received:
		var block_after = state.block
		var gap = block_after - block_before
		log_info("STATS: Stream resumed. Gap during downtime: %d blocks." % gap)
		pass_test("Auto-recovery successful. Local ID %s is persistent!" % my_sub)
	
	client.queue_free()
