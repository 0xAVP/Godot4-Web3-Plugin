# demo/tests/live/transport/test_03_contract_events.gd
extends W3Test

func run(runner: Node):
	log_section("LIVE TEST: EthContract Events & Subscriptions")
	
	var client = runner.get_node("EthClient")
	var event_abi = [{
		"name": "ChunkExplored",
		"type": "event",
		"godot_signature": "ChunkExplored(int32,int32,uint256,address)",
		"inputs": [
			{"name": "q", "type": "int32", "indexed": true},
			{"name": "r", "type": "int32", "indexed": true},
			{"name": "seed", "type": "uint256", "indexed": false},
			{"name": "discoverer", "type": "address", "indexed": false}
		]
	}]

	# 1. Инициализация
	var contract = EthContract.new()
	contract.client_path = client.get_path()
	contract.contract_address = "0x7e5f4552091a69125d5dfcb7b8c2659029395bdf"
	runner.add_child(contract)
	
	# ВАЖНО: Используем setup_abi, чтобы контракт подключился к клиенту
	contract.setup_abi(event_abi)
	
	# --- ТЕСТ 1: ПОДПИСКА ---
	log_section("1. Testing Subscription")
	var sub_id = await contract.subscribe_event("ChunkExplored")
	
	assert_true(!sub_id.is_empty(), "Subscription ID received: " + sub_id)
	assert_true(contract._event_subs.has("ChunkExplored"), "Internal dict has ChunkExplored")
	assert_eq(contract._event_subs["ChunkExplored"], sub_id, "Internal sub_id matches")

	# --- ТЕСТ 2: ДЕКОДИРОВАНИЕ И СИГНАЛ ---
	log_section("2. Testing Signal Routing")
	var event_data = {"received": false, "name": ""}
	contract.event_received.connect(func(n, d): 
		event_data.received = true
		event_data.name = n
	)
	
	# Имитируем приход данных от EthClient
	var t0 = contract._registry.events_by_name["ChunkExplored"]
	var mock_log = {
		"topics": [t0, "0x" + "0".repeat(64), "0x" + "0".repeat(64)],
		"data": "0x" + "0".repeat(128)
	}
	
	# Эмулируем сигнал от клиента (так контракт узнает о событии)
	client.subscription_event.emit(sub_id, mock_log)
	
	# Даем Godot кадр на обработку сигнала
	await runner.get_tree().process_frame
	
	assert_true(event_data.received, "Contract emitted event_received signal")
	assert_eq(event_data.name, "ChunkExplored", "Signal has correct event name")

	# --- ТЕСТ 3: ОТПИСКА ---
	log_section("3. Testing Unsubscribe")
	var unsub_ok = await contract.unsubscribe_event("ChunkExplored")
	
	assert_true(unsub_ok, "Unsubscribe call returned success")
	assert_true(!contract._event_subs.has("ChunkExplored"), "Event name removed from internal dict")
	
	# Проверяем, что после отписки контракт больше не реагирует на этот ID
	event_data.received = false
	client.subscription_event.emit(sub_id, mock_log)
	assert_true(!event_data.received, "Contract ignores logs after unsubscription")

	# --- ТЕСТ 4: ОТПИСКА ОТ ВСЕГО ---
	log_section("4. Testing Unsubscribe All")
	# Подписываемся снова
	await contract.subscribe_event("ChunkExplored")
	assert_true(!contract._event_subs.is_empty(), "Subscribed back")
	
	await contract.unsubscribe_all()
	
	assert_true(contract._event_subs.is_empty(), "All subscriptions cleared")

	contract.queue_free()
	pass_test("All event lifecycle checks passed!")
