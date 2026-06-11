# demo/tests/live/transport/test_03_contract_events.gd
extends W3Test

func run(runner: Node):
	log_section("UNIT TEST: EthContract Events Decoding")
	
	var event_abi = [
		{
			"name": "ChunkExplored",
			"type": "event",
			"godot_signature": "ChunkExplored(int32,int32,uint256,address)",
			"inputs": [
				{"name": "q", "type": "int32", "indexed": true},
				{"name": "r", "type": "int32", "indexed": true},
				{"name": "seed", "type": "uint256", "indexed": false},
				{"name": "discoverer", "type": "address", "indexed": false}
			]
		}
	]

	# --- 1. ПРОВЕРКА ИНДЕКСАЦИИ ---
	log_section("1. Event Indexing")
	var contract = EthContract.new()
	var idx = preload("res://addons/godot_web3/nodes/internal/contract/eth_abi_indexer.gd").new()
	var registry = idx.index_manifest(event_abi)
	
	assert_true(registry.events_by_name.has("ChunkExplored"), "Registry has event by name")
	var t0 = registry.events_by_name["ChunkExplored"]
	assert_true(registry.events_by_topic.has(t0), "Registry has metadata by topic0")
	
	var meta = registry.events_by_topic[t0]
	assert_eq(meta.indexed_params.size(), 2, "Found 2 indexed params (q, r)")
	assert_eq(meta.data_params.size(), 2, "Found 2 data params (seed, discoverer)")

	# --- 2. ДЕКОДИРОВАНИЕ ЛОГА (Mock Log) ---
	log_section("2. Log Decoding (Indexed + Data)")
	
	# Подготавливаем "сырой" лог от ноды
	# Topics: [Topic0, q=10, r=-5]
	var topic_q = "0x" + "0".repeat(62) + "0a" # 10
	var topic_r = "0x" + "f".repeat(64) # -1 (для примера отрицательного)
	
	# Data: [seed (32b), discoverer (32b padded)]
	var seed_val = W3BigInt.from_int(123456789)
	var discoverer = "0x7e5f4552091a69125d5dfcb7b8c2659029395bdf"
	
	var raw_data = W3ABI.encode_params(["uint256", "address"], [seed_val, discoverer])
	
	var mock_log = {
		"topics": [t0, topic_q, topic_r],
		"data": W3Utils.bytes_to_hex(raw_data)
	}

	# Настраиваем контракт
	contract._registry = registry
	var event_data = {"name": "", "data": {}}
	
	# Ловим сигнал
	contract.event_received.connect(func(n, d): 
		event_data.name = n
		event_data.data = d
	)
	
	# Вызываем внутренний процессор
	contract._process_event_log(t0, mock_log)
	
	# Проверки
	assert_eq(event_data.name, "ChunkExplored", "Correct event name emitted")
	
	var d = event_data.data
	assert_eq(d.q.to_int256_string(), "10", "Indexed q decoded")
	assert_eq(d.r.to_int256_string(), "-1", "Indexed r decoded (negative)")
	assert_eq(d.seed.to_string_val(), "123456789", "Data seed decoded")
	assert_eq(d.discoverer.to_lower(), discoverer.to_lower(), "Data address decoded")

	contract.queue_free()
	pass_test("Event indexing and decoding verified!")
