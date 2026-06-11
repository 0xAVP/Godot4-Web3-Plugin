# demo/tests/live/transport/test_contract_hardcore.gd
extends W3Test

const Indexer = preload("res://addons/godot_web3/nodes/internal/contract/eth_abi_indexer.gd")
const Mapper = preload("res://addons/godot_web3/nodes/internal/contract/eth_data_mapper.gd")

func run(runner: Node):
	log_section("HARDCORE UNIT TEST: ETH_CONTRACT COMPLEX TYPES")
	
	var idx = Indexer.new()
	var map = Mapper.new()

	# --- 1. ПРОВЕРКА ГЛУБОКОЙ ВЛОЖЕННОСТИ (Nested Tuples) ---
	# Представим функцию: getHero(uint256) -> (string name, (uint256 hp, uint256 mp) stats)
	log_section("1. Nested Structures (Tuple in Tuple)")
	
	var hero_abi = [{
		"name": "getHero",
		"type": "function",
		"godot_signature": "getHero(uint256)",
		"godot_output_types": ["string", "(uint256,uint256)"],
		"godot_output_names": ["name", ["hp", "mp"]],
		"stateMutability": "view",
		"inputs": [{"type": "uint256", "name": "id"}]
	}]
	
	# Имитируем ответ от C++: ["Arthas", [2500, 500]]
	var raw_hero = ["Arthas", [W3BigInt.from_int(2500), W3BigInt.from_int(500)]]
	var registry = idx.index_manifest(hero_abi)
	var mapped_hero = map.map_to_named(raw_hero, registry.methods.getHero.output_names)
	
	assert_eq(mapped_hero.name, "Arthas", "Root string decoded")
	assert_true(mapped_hero.get("1") is Dictionary, "Nested tuple mapped to Dictionary")
	assert_eq(mapped_hero.get("1").hp, "2500", "Nested BigInt accessed via name")

	# --- 2. ПРОВЕРКА МАССИВА СТРУКТУР (Array of Tuples) ---
	# Часто встречается в Diamond-манифестах для получения списков
	log_section("2. Testing EthDataMapper")
	var mapa = Mapper.new()
	
	# Сценарий A: Кортеж (Структура CellData)
	# Допустим, функция возвращает ОДИН кортеж (как твои getChunkData)
	var raw_tuple_data = [ [10, 1, true] ] 
	var names_tuple = [ ["biome", "resource", "isWalkable"] ]
	
	var cell = map.map_to_named(raw_tuple_data, names_tuple)
	
	assert_true(cell is Dictionary, "Single tuple unwrapped to Dictionary")
	assert_eq(cell.biome, 10, "Field 'biome' is 10")
	assert_eq(cell.isWalkable, true, "Field 'isWalkable' is true")

	# Сценарий B: Массив структур (tuple[])
	var raw_list_data = [ [ [1, 10], [2, 20] ] ]
	var names_list = [ ["biome", "res"] ]
	
	var list = mapa.map_to_named(raw_list_data, names_list)
	
	assert_true(list is Array, "Unwrapped single output to Array")
	assert_eq(list[0].biome, 1, "First element biome is 1")
	assert_eq(list[1].res, 20, "Second element res is 20")

	# --- 3. ПРОВЕРКА ПРЕДЕЛЬНЫХ ЗНАЧЕНИЙ (Uint256 Max) ---
	log_section("3. Boundary Values (uint256 Max)")
	
	var big_abi = [{
		"name": "getBalance",
		"godot_output_types": ["uint256"],
		"godot_output_names": ["balance"],
		"type": "function"
	}]
	
	var max_uint256_hex = "ffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff"
	var raw_big = [W3BigInt.from_hex(max_uint256_hex)]
	var reg_big = idx.index_manifest(big_abi)
	var mapped_big = map.map_to_named(raw_big, reg_big.methods.getBalance.output_names)
	
	assert_true(mapped_big is W3BigInt, "Max uint256 returned as W3BigInt object")
	assert_eq(mapped_big.to_hex(false), max_uint256_hex, "Max uint256 hex matches")

	# --- 4. ПРОВЕРКА ФИКСИРОВАННЫХ ТИПОВ (Bytes32, Address, Bool) ---
	log_section("4. Fixed Types (Address, Bool, Bytes32)")
	
	var addr = "0x7e5f4552091a69125d5dfcb7b8c2659029395bdf"
	var mixed_abi = [{
		"name": "getStatus",
		"godot_output_types": ["address", "bool", "bytes32"],
		"godot_output_names": ["owner", "isActive", "rootHash"],
		"type": "function"
	}]
	
	var raw_mixed = [addr, true, W3Utils.hex_to_bytes("aa".repeat(32))]
	var reg_mixed = idx.index_manifest(mixed_abi)
	var mapped_mixed = map.map_to_named(raw_mixed, reg_mixed.methods.getStatus.output_names)
	
	assert_eq(mapped_mixed.owner, addr, "Address preserved")
	assert_eq(mapped_mixed.isActive, true, "Boolean preserved")
	assert_true(mapped_mixed.rootHash.size() == 32, "Bytes32 size is 32")

	# --- 5. ТЕСТ НА ПУСТЫЕ ИМЕНА (Fallback to Index) ---
	log_section("5. Edge Case: Empty Names in ABI")
	
	var anonymous_abi = [{
		"name": "anon",
		"godot_output_types": ["uint256", "uint256"],
		"godot_output_names": ["", ""], # Имена не заданы
		"type": "function"
	}]
	
	var raw_anon = [1, 2]
	var reg_anon = idx.index_manifest(anonymous_abi)
	var mapped_anon = map.map_to_named(raw_anon, reg_anon.methods.anon.output_names) if false else map.map_to_named(raw_anon, reg_anon.methods.anon.output_names)
	
	assert_eq(mapped_anon.get("0"), 1, "Fallback to index '0' for unnamed param")
	assert_eq(mapped_anon.get("1"), 2, "Fallback to index '1' for unnamed param")

	# --- 6. ТЕСТ РЕКУРСИВНОГО ГЕНЕРАТОРА ТИПОВ (White Box) ---
	log_section("6. Internal: Canonical Type Generation")
	
	# Проверяем, как индексер собирает сложные строки для C++
	var complex_input = {
		"type": "tuple[][]",
		"components": [
			{"type": "uint256", "name": "id"},
			{"type": "tuple", "name": "data", "components": [
				{"type": "string", "name": "s"}
			]}
		]
	}
	var sig = idx._extract_canonical_type(complex_input)
	assert_eq(sig, "(uint256,(string))[][]", "Deeply nested signature generation")

	pass_test("MAXIMUM Hardcore logic test passed!")
