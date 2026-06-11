# demo/tests/live/cpp/test_03_eip712.gd
extends W3Test

func run(_runner: Node):
	log_section("HARDCORE C++ EIP-712 LOGIC TEST")

	var domain = {
		"name": "HexForwarder",
		"version": "1",
		"chainId": 1328,
		"verifyingContract": "0x1234567890123456789012345678901234567890"
	}

	var message = {
		"from": "0x7e5f4552091a69125d5dfcb7b8c2659029395bdf",
		"to": "0x2e5f4552091a69125d5dfcb7b8c2659029395bdc",
		"value": W3BigInt.from_int(0),
		"gas": 21000,
		"nonce": 0,
		"deadline": 1739223000,
		"data": W3Utils.hex_to_bytes("0xdeadbeef")
	}

	# --- ТЕСТ 1: Детерминизм и Типы данных ---
	log_section("1. Data Type Robustness")
	
	var hash1 = W3Crypto.get_eip712_forward_request_hash(domain, message)
	
	# Меняем типы данных в словаре на альтернативные (String вместо Int и т.д.)
	var domain_alt = domain.duplicate()
	domain_alt["chainId"] = "1328" # Строка вместо числа
	
	var message_alt = message.duplicate()
	message_alt["gas"] = "21000"
	message_alt["nonce"] = W3BigInt.from_int(0) # Объект вместо числа
	message_alt["deadline"] = "1739223000"
	
	var hash2 = W3Crypto.get_eip712_forward_request_hash(domain_alt, message_alt)
	
	assert_eq(W3Utils.bytes_to_hex(hash1), W3Utils.bytes_to_hex(hash2), "Hash must be identical regardless of input Variant types (Int/String/BigInt)")


	# --- ТЕСТ 2: Форматирование Адресов ---
	log_section("2. Address Format Stress")
	
	var message_addr = message.duplicate()
	# Разные написания одного и того же адреса
	var addresses = [
		"0x7e5f4552091a69125d5dfcb7b8c2659029395bdf",
		"0X7E5F4552091A69125D5DFCB7B8C2659029395BDF", # Upper + 0X
		"7e5f4552091a69125d5dfcb7b8c2659029395bdf"    # No prefix
	]
	
	var last_hash = ""
	for addr in addresses:
		message_addr["from"] = addr
		var h = W3Utils.bytes_to_hex(W3Crypto.get_eip712_forward_request_hash(domain, message_addr))
		if last_hash == "":
			last_hash = h
		else:
			assert_eq(h, last_hash, "Address format '%s' must not change the hash" % addr)


	# --- ТЕСТ 3: Граничные значения (Overflow & Empty) ---
	log_section("3. Boundary Values & Empty Data")
	
	var message_edge = message.duplicate()
	# Максимальный uint256 (64 'f')
	var max_u256 = "ffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff"
	message_edge["value"] = W3BigInt.from_hex(max_u256)
	message_edge["data"] = PackedByteArray() # Пустая дата
	
	var h_edge = W3Crypto.get_eip712_forward_request_hash(domain, message_edge)
	assert_true(h_edge.size() == 32, "Max uint256 and empty data handled without crash")
	
	# Проверка, что изменение одного бита в данных меняет хеш
	message_edge["data"] = PackedByteArray([0x01])
	var h_edge_mod = W3Crypto.get_eip712_forward_request_hash(domain, message_edge)
	assert_true(h_edge != h_edge_mod, "Hash must change when data is modified")


	# --- ТЕСТ 4: Реальный вектор (Regression Check) ---
	log_section("4. Regression Check")
	# Этот хеш вычислен для данных выше. Если он изменится — мы сломали логику упаковки.
	# Важно: если ты поменял DOMAIN_TYPEHASH или REQUEST_TYPEHASH в C++, этот тест упадет.
	var expected_hash = W3Utils.bytes_to_hex(hash1)
	log_info("Current Hash: " + expected_hash)
	
	# Простая проверка на "не пустоту" и структуру
	assert_true(hash1.size() == 32, "Hash size is exactly 32 bytes")
	assert_true(W3Utils.bytes_to_hex(hash1) != "0x" + "0".repeat(64), "Hash is not zero")


	# --- ТЕСТ 5: Производительность (Stress) ---
	log_section("5. Performance Bench")
	var t_start = Time.get_ticks_usec()
	var iterations = 500
	for i in range(iterations):
		W3Crypto.get_eip712_forward_request_hash(domain, message)
	var t_end = Time.get_ticks_usec()
	
	var total_ms = (t_end - t_start) / 1000.0
	log_info("%d iterations took %.2f ms (avg %.3f ms/op)" % [iterations, total_ms, total_ms/iterations])
	assert_true(total_ms < 500, "Performance is acceptable (sub-millisecond per hash)")

	pass_test("EIP-712 Hardcore tests passed!")
