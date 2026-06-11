# tests/live/test_01_basic.gd
extends W3Test

# Добавляем аргумент runner, чтобы соответствовать родителю
func run(runner: Node):
	log_section("Checking Utils & Math")
	
	# Ссылка на клиент, если он понадобится (берем из сцены через раннер)
	var client = runner.get_node("EthClient")
	
	# 1. Math
	var a = W3BigInt.from_int(100)
	var b = W3BigInt.from_int(200)
	assert_eq(a.add(b), "300", "BigInt Addition")
	
	# 2. Wei Conversion
	var one_eth = W3Utils.ether_to_wei(1.0)
	assert_eq(one_eth, "1000000000000000000", "1.0 ETH to Wei")
	
	# 3. Crypto (Keccak)
	log_section("Checking Core Crypto")
	var data = "godot".to_utf8_buffer()
	var hash = W3Keccak.hash(data)
	assert_eq(hash.size(), 32, "Keccak256 output size")
	
	# 4. RPC (Node Check)
	log_section("Checking Client Node")
	assert_eq(client.chain_id > 0, true, "Client has Chain ID: " + str(client.chain_id))
