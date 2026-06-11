extends W3Test

func run(_runner: Node):
	log_section("HARDCORE C++ RECOVERY & CRYPTO INTEGRITY")

	# Тестовый вектор (Known Key)
	var pk_hex = "0000000000000000000000000000000000000000000000000000000000000001"
	var expected_addr = "0x7e5f4552091a69125d5dfcb7b8c2659029395bdf"
	
	var pk_bytes = W3Utils.hex_to_bytes(pk_hex)

	# --- ТЕСТ 1: Public Key & Address Derivation ---
	log_section("1. Address Derivation")
	var pub_key = W3Crypto.get_public_key(pk_bytes, false) # Uncompressed
	var derived_addr = W3Crypto.get_address_from_pubkey(pub_key)
	
	assert_eq(derived_addr.to_lower(), expected_addr, "Address derived from private key correctly")


	# --- ТЕСТ 2: Внутренняя целостность (Sign -> Recover) ---
	log_section("2. Internal Roundtrip (Sign -> Recover)")
	
	# Имитируем логику EIP-191 вручную, чтобы тестировать чистое ядро W3Crypto
	var msg_str = "Godot Engine Expert Check"
	var msg_bytes = msg_str.to_utf8_buffer()
	
	var prefix = PackedByteArray([0x19])
	prefix.append_array("Ethereum Signed Message:\n".to_utf8_buffer())
	prefix.append_array(str(msg_bytes.size()).to_utf8_buffer())
	
	# Хешируем (W3Crypto.sign принимает только 32 байта хеша!)
	var hash = W3Keccak.hash(prefix + msg_bytes)
	
	# Подписываем
	var sig_bytes = W3Crypto.sign(hash, pk_bytes)
	assert_eq(sig_bytes.size(), 65, "Signature size is 65 bytes (R+S+V)")
	
	# Восстанавливаем
	var recovered_addr = W3Crypto.recover_address(hash, sig_bytes)
	assert_eq(recovered_addr.to_lower(), expected_addr, "Recovered address matches original")


	# --- ТЕСТ 3: Манипуляция данными (Tamper Check) ---
	log_section("3. Data Tamper Check")
	
	var tampered_bytes = msg_bytes.duplicate()
	tampered_bytes.append(0x21) # Добавили '!'
	# Хешируем поддельное сообщение
	var hash_tampered = W3Keccak.hash(prefix + tampered_bytes)
	
	# Пытаемся восстановить адрес, используя СТАРУЮ подпись, но НОВЫЙ хеш
	var recovered_fake = W3Crypto.recover_address(hash_tampered, sig_bytes)
	
	# Адрес должен либо не восстановиться (""), либо быть другим
	var is_safe = (recovered_fake != expected_addr)
	assert_true(is_safe, "Tampered message does NOT recover to owner address")


	# --- ТЕСТ 4: V-Value Robustness (EIP-155 vs Legacy) ---
	log_section("4. V-Value Robustness")
	
	# W3Crypto.sign возвращает V как 0 или 1 (RecID).
	# Ethereum RPC ожидает 27/28 (Legacy) или ChainID-based.
	# C++ recover_address должна уметь работать и с 0/1, и с 27/28.
	
	var sig_raw = sig_bytes.duplicate()
	var v_original = sig_raw[64] # Скорее всего 0 или 1
	
	# Тест V=27 (если RecID=0) или V=28 (если RecID=1)
	var sig_legacy = sig_raw.duplicate()
	sig_legacy[64] = 27 + v_original
	
	var addr_legacy = W3Crypto.recover_address(hash, sig_legacy)
	assert_eq(addr_legacy.to_lower(), expected_addr, "Handles Legacy V (27/28)")
	
	# Тест V=0/1 (Native RecID)
	var sig_native = sig_raw.duplicate()
	sig_native[64] = v_original # Просто 0 или 1
	
	var addr_native = W3Crypto.recover_address(hash, sig_native)
	assert_eq(addr_native.to_lower(), expected_addr, "Handles Native V (0/1)")


	# --- ТЕСТ 5: Производительность (Benchmarking) ---
	log_section("5. Performance Bench (Address Recovery)")
	
	var t_start = Time.get_ticks_usec()
	var loops = 1000
	for i in range(loops):
		W3Crypto.recover_address(hash, sig_bytes)
	var t_end = Time.get_ticks_usec()
	
	var total_ms = (t_end - t_start) / 1000.0
	var ops_sec = loops / (total_ms / 1000.0)
	
	log_info("1000 recoveries: %.2f ms (%.0f ops/sec)" % [total_ms, ops_sec])
	
	# Лимит: хотя бы 500 операций в секунду (это очень медленно для C++, но приемлемо для GDIntegration)
	assert_true(total_ms < 2000, "Performance within limits (>500 ops/s)")

	pass_test("All hardcore C++ recovery checks passed!")
