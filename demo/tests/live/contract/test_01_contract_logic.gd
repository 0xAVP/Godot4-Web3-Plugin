# demo/tests/live/transport/test_01_contract_logic.gd
extends W3Test

const Indexer = preload("res://addons/godot_web3/nodes/internal/contract/eth_abi_indexer.gd")
const Mapper = preload("res://addons/godot_web3/nodes/internal/contract/eth_data_mapper.gd")

func run(runner: Node):
	log_section("UNIT TEST: EthContract Logic (Indexer & Mapper)")
	
	var test_abi = [
		{
			"name": "getChunkData",
			"type": "function",
			"godot_signature": "getChunkData(int32,int32)",
			"godot_output_types": ["(int16,uint8,bool)"],
			"godot_output_names": [["biome", "resource", "isWalkable"]],
			"stateMutability": "view",
			"inputs": [
				{"type": "int32", "name": "q"},
				{"type": "int32", "name": "r"}
			]
		},
		{
			"name": "simpleValue",
			"type": "function",
			"godot_signature": "simpleValue()",
			"godot_output_types": ["uint256"],
			"godot_output_names": ["val"],
			"stateMutability": "view",
			"inputs": []
		}
	]

	# --- 1. ТЕСТ ИНДЕКСАТОРА ---
	log_section("1. Testing EthAbiIndexer")
	var idx = Indexer.new()
	var registry = idx.index_manifest(test_abi)
	
	# ПРАВКА: Добавлен .methods
	assert_true(registry.methods.has("getChunkData"), "Registry.methods contains 'getChunkData'")
	assert_true(registry.methods.getChunkData.selector.size() == 4, "Selector is 4 bytes")
	
	var complex_type = {
		"type": "tuple[]",
		"components": [
			{"type": "int16", "name": "a"},
			{"type": "uint8", "name": "b"}
		]
	}
	var canonical = idx._extract_canonical_type(complex_type)
	assert_eq(canonical, "(int16,uint8)[]", "Recursive type extraction: (int16,uint8)[]")

	# --- 2. ТЕСТ МАППЕРА ---
	log_section("2. Testing EthDataMapper")
	var map = Mapper.new()
	
	var raw_tuple_data = [ [10, 1, true] ] 
	var names_tuple = [ ["biome", "resource", "isWalkable"] ]
	
	var cell = map.map_to_named(raw_tuple_data, names_tuple)
	
	assert_true(cell is Dictionary, "Single tuple unwrapped to Dictionary")
	assert_eq(cell.biome, 10, "Field 'biome' is 10")
	assert_eq(cell.isWalkable, true, "Field 'isWalkable' is true")

	var raw_list_data = [ [ [1, 10], [2, 20] ] ]
	var names_list = [ ["biome", "res"] ]
	
	var list = map.map_to_named(raw_list_data, names_list)
	
	assert_true(list is Array, "Unwrapped single output to Array")
	assert_eq(list[0].biome, 1, "First element biome is 1")
	assert_eq(list[1].res, 20, "Second element res is 20")

	# --- 3. ИНТЕГРАЦИЯ В УЗЕЛ (Mock-вызов) ---
	log_section("3. Testing EthContract Encoding")
	var contract = EthContract.new()
	contract.manifest_path = "" 
	contract._registry = registry 
	
	var args = [10, -5]
	# ПРАВКА: Добавлен .methods
	var calldata = contract._encode_method_call(registry.methods.getChunkData, args)
	
	var selector_hex = W3Utils.bytes_to_hex(calldata.slice(0, 4), false)
	var expected_selector = W3Utils.bytes_to_hex(W3ABI.encode_function_selector("getChunkData(int32,int32)"), false)
	
	assert_eq(selector_hex, expected_selector, "Calldata starts with correct selector")
	assert_true(calldata.size() > 4, "Calldata contains encoded arguments")

	contract.queue_free()
	pass_test("EthContract logic is solid!")
