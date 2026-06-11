# tests/live/test_09_http_stress.gd
extends W3Test

const HTTP_Script = preload("res://addons/godot_web3/nodes/internal/transport/eth_http_client.gd")
const WS_Script = preload("res://addons/godot_web3/nodes/internal/transport/eth_ws_client.gd")

func run(runner: Node):
	log_section("ULTIMATE FAULT TOLERANCE: HTTP <-> WS Cross-Switching")
	
	var client: EthClient = runner.get_node("EthClient")
	var network = client._network
	
	var limit = client.max_concurrency
	log_info("SYSTEM: Concurrency Limit = %d | Nodes = %d" % [limit, client.rpc_nodes.size()])

	# --- ШАГ 0: Убеждаемся, что в списке есть и HTTP и WS ---
	var has_http = false
	var has_ws = false
	for url in client.rpc_nodes:
		if url.begins_with("http"): has_http = true
		if url.begins_with("ws"): has_ws = true
	
	if not (has_http and has_ws):
		fail_test("Test requires at least one HTTP and one WS node in rpc_nodes!")
		return

	# --- ЭТАП 1: HTTP -> WebSocket под нагрузкой ---
	log_section("Phase 1: HTTP -> WS Migration")
	
	# 1.1. Выходим на HTTP ноду
	while network._active_provider.get_script() != HTTP_Script:
		network._rotate_node()
		await runner.get_tree().process_frame
	log_info("Starting on HTTP: %s" % client.rpc_nodes[network._current_node_index])

	# 1.2. Запускаем пачку запросов
	var batch1_count = 20
	var results1 = []
	results1.resize(batch1_count)
	var state1 = {"finished": 0}
	
	for i in range(batch1_count):
		var task = func(idx):
			results1[idx] = await client.request("eth_blockNumber", [])
			state1.finished += 1
		task.call_deferred(i)
	
	await runner.get_tree().create_timer(0.05).timeout
	
	# 1.3. Агрессивно ротируем до WebSocket
	log_info("!!! CHAOS: Forcing rotation to WebSocket...")
	while network._active_provider.get_script() != WS_Script:
		network._rotate_node()
		
	log_info("Migration triggered. Active provider is now WS. Waiting for recovery...")
	
	await _wait_for_tasks(state1, batch1_count, 15.0, runner)
	assert_eq(_count_success(results1), batch1_count, "HTTP -> WS: All 20 requests recovered and finished")


	# --- ЭТАП 2: WebSocket -> HTTP под нагрузкой ---
	log_section("Phase 2: WS -> HTTP Migration")
	
	# 2.1. Ждем рукопожатия WS (если нужно)
	if network._active_provider.socket.get_ready_state() != WebSocketPeer.STATE_OPEN:
		await client.connected
	
	log_info("Starting on WS: %s" % client.rpc_nodes[network._current_node_index])

	# 2.2. Запускаем пачку запросов
	var batch2_count = 20
	var results2 = []
	results2.resize(batch2_count)
	var state2 = {"finished": 0}
	
	for i in range(batch2_count):
		var task = func(idx):
			results2[idx] = await client.request("eth_gasPrice", [])
			state2.finished += 1
		task.call_deferred(i)
		
	await runner.get_tree().create_timer(0.05).timeout
	
	# 2.3. Агрессивно ротируем до HTTP
	log_info("!!! CHAOS: Forcing rotation back to HTTP...")
	while network._active_provider.get_script() != HTTP_Script:
		network._rotate_node()
		
	log_info("Migration triggered. Active provider is now HTTP. Waiting for recovery...")
	
	await _wait_for_tasks(state2, batch2_count, 15.0, runner)
	assert_eq(_count_success(results2), batch2_count, "WS -> HTTP: All 20 requests recovered and finished")


	# --- ЭТАП 3: Финальная проверка ресурсов ---
	log_section("Phase 3: Final Cleanup & Integrity")
	
	# Даем время на queue_free() последних воркеров
	await runner.get_tree().process_frame
	await runner.get_tree().process_frame
	
	var total_http_req_nodes = 0
	var active_providers_count = 0
	
	for child in network.get_children():
		active_providers_count += 1
		var s = child.get_script()
		if s == HTTP_Script or s == WS_Script:
			total_http_req_nodes += child.get_child_count()
	
	log_info("Active provider instances in Manager: %d" % active_providers_count)
	log_info("Dangling HTTPRequest worker nodes: %d" % total_http_req_nodes)
	
	assert_true(active_providers_count >= 1, "At least one provider is alive")
	assert_eq(total_http_req_nodes, 0, "No memory leaks: 0 worker nodes left")
	
	log_section("=== ULTIMATE STRESS TEST PASSED ===")

# --- Хелперы ---

func _wait_for_tasks(state: Dictionary, target: int, timeout: float, runner: Node):
	var time_left = timeout
	while state.finished < target and time_left > 0:
		await runner.get_tree().process_frame
		time_left -= 1.0/60.0

func _count_success(results: Array) -> int:
	var c = 0
	for r in results: if r != null: c += 1
	return c
