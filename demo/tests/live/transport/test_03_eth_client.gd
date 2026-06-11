# tests/live/test_08_eth_client.gd
extends W3Test

const HTTP_Script = preload("res://addons/godot_web3/nodes/internal/transport/eth_http_client.gd")
const WS_Script = preload("res://addons/godot_web3/nodes/internal/transport/eth_ws_client.gd")

func run(runner: Node):
	log_section("STRESS & EDGE CASE TEST: EthClient (Facade Architecture)")
	
	var client: EthClient = runner.get_node_or_null("EthClient")
	if not client:
		client = EthClient.new()
		client.name = "EthClient"
		client.rpc_nodes = [
			"https://dead-link.com/rpc", 
			"https://base-sepolia.infura.io/v3/4aa4d838e9ce41beab99f63089155f48",
			"wss://base-sepolia.infura.io/ws/v3/4aa4d838e9ce41beab99f63089155f48",
			"http://127.0.0.1:1"
		]
		client.chain_id = 84532
		client.verbose_logs = true
		runner.add_child(client)

	var net_manager = client._network 

	# --- КРАЕВЫЕ СЛУЧАИ: HTTP ---
	
	log_section("Edge Case 1: Failover from start")
	log_info("Current node is 0 (dead). Requesting block via Facade...")
	var b1 = await client.get_block_number()
	assert_true(b1 > 0, "Failover: Automatically skipped node 0 and got block from node 1")
	assert_true(net_manager._active_provider.get_script() == HTTP_Script, "Current internal provider is HTTP")

	# ИСПРАВЛЕНО: Теперь HTTP поддерживает подписки через Polling
	log_section("Edge Case 2: HTTP Virtual Subscription")
	log_info("Calling 'subscribe' while on HTTP node (Polling expected)...")
	
	var sub_id = await client.subscribe(["newHeads"])
	assert_true(!sub_id.is_empty(), "Unified API: HTTP now supports virtual subscriptions")
	
	if !sub_id.is_empty():
		await client.unsubscribe(sub_id)
		pass_test("HTTP Subscription lifecycle verified")

	log_section("Edge Case 3: High-level Helpers (HTTP)")
	var gas = await client.get_gas_price()
	assert_true(gas != null and gas.gt(W3BigInt.from_int(0)), "Gas price fetched")
	
	var nonce = await client.get_transaction_count("0x7e5f4552091a69125d5dfcb7b8c2659029395bdf")
	pass_test("Nonce fetched: " + str(nonce))

	# --- КРАЕВЫЕ СЛУЧАИ: ПЕРЕКЛЮЧЕНИЕ ---

	log_section("Edge Case 4: Rotation Stress")
	log_info("Rapidly rotating to WebSocket node...")
	
	while net_manager._active_provider.get_script() != WS_Script:
		net_manager._rotate_node()
	
	assert_true(net_manager._active_provider.get_script() == WS_Script, "Provider is now WebSocket")
	
	if net_manager._active_provider.socket.get_ready_state() != WebSocketPeer.STATE_OPEN:
		log_info("Waiting for WS handshake...")
		await client.connected
	pass_test("WebSocket Link Established via Facade signal")

	# --- КРАЕВЫЕ СЛУЧАИ: WEBSOCKET ---

	log_section("Edge Case 5: WebSocket Subscriptions")
	var ws_sub_id = await client.subscribe(["newHeads"])
	
	if not ws_sub_id.is_empty():
		var test_state = {"got_event": false}
		var timer = runner.get_tree().create_timer(15.0)
		
		var on_event = func(id, data):
			if id == ws_sub_id:
				test_state["got_event"] = true
				log_info("Real-time block via WS: " + str(data.get("number")))

		client.subscription_event.connect(on_event)
		while not test_state["got_event"] and timer.time_left > 0:
			await runner.get_tree().process_frame
		
		client.subscription_event.disconnect(on_event)
		assert_true(test_state["got_event"], "Event received via WS Facade signal")
		await client.unsubscribe(ws_sub_id)
	else:
		fail_test("WS Subscription failed")

	log_section("Edge Case 6: WS Request with large data")
	var full_block = await client.request("eth_getBlockByNumber", ["latest", false])
	assert_not_null(full_block, "Large JSON response over WS handled correctly")

	# --- КРАЕВЫЕ СЛУЧАИ: ОШИБКИ СЕТИ ---

	log_section("Edge Case 7: Middle-of-list failure")
	log_info("Forcing failure on node 3 (dead HTTP)...")
	
	# Крутим до конца списка
	net_manager._rotate_node() 
	
	log_info("Making request to dead node (expecting full circle recovery)...")
	var recovery_block = await client.get_block_number()
	assert_true(recovery_block > 0, "Full recovery: Cycled through list back to node 1")
	
	var active_url = client.rpc_nodes[net_manager._current_node_index]
	log_info("Back to working node: " + active_url)

	log_section("Edge Case 8: Transaction Waiting (Timeout)")
	var fake_hash = "0x" + "1".repeat(64)
	var start_t = Time.get_ticks_msec()
	
	var receipt = await client.wait_for_transaction(fake_hash, 0.5, 3.0)
	var end_t = Time.get_ticks_msec()
	
	assert_eq(receipt, {}, "Timeout handled: returned empty dictionary")
	assert_true((end_t - start_t) >= 3000, "Timeout duration respected (~3s)")

	log_section("=== ALL ETHCLIENT FACADE TESTS PASSED ===")
