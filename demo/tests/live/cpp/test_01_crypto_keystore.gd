extends W3Test

func run(_runner: Node):
	log_section("HARDCORE C++ CRYPTO TEST: KEYSTORE PRIMITIVES")

	# --- ТЕСТ 1: PBKDF2 (RFC 6070 / Тестовые векторы) ---
	log_section("1. PBKDF2 HMAC-SHA256 Determinism")
	
	var password = "password"
	var salt = "salt".to_utf8_buffer()
	var iterations = 1
	var key_length = 32
	
	# Официальный тестовый вектор PBKDF2-HMAC-SHA256:
	# Password: "password", Salt: "salt", Iterations: 1, Length: 32
	var expected_pbkdf2 = "120fb6cffcf8b32c43e7225256c4f837a86548c92ccc35480805987cb70be17b"
	
	var derived = W3Crypto.pbkdf2(password, salt, iterations, key_length)
	assert_eq(W3Utils.bytes_to_hex(derived, false), expected_pbkdf2, "PBKDF2 standard vector match")
	
	# Стресс-тест
	log_info("Testing PBKDF2 with 10,000 iterations...")
	var t_start = Time.get_ticks_msec()
	var derived_heavy = W3Crypto.pbkdf2(password, salt, 10000, key_length)
	var t_end = Time.get_ticks_msec()
	log_info("10k iterations took: %d ms" % (t_end - t_start))
	assert_true(derived_heavy.size() == 32, "High iteration PBKDF2 produced correct size")


	# --- ТЕСТ 2: AES-256-CTR (Roundtrip) ---
	log_section("2. AES-256-CTR Roundtrip")
	
	var aes_key = W3Crypto.generate_private_key() # 32 байта
	var aes_iv = W3Crypto.generate_private_key().slice(0, 16) # 16 байт
	var original_text = "Godot Web3 Plugin - Top Secret Data"
	var data_to_encrypt = original_text.to_utf8_buffer()
	
	# Шифрование
	var ciphertext = W3Crypto.aes_ctr_encrypt(data_to_encrypt, aes_key, aes_iv)
	assert_true(!ciphertext.is_empty(), "Encryption produced data")
	assert_true(ciphertext != data_to_encrypt, "Ciphertext is different from plaintext")
	
	# Расшифровка
	var decrypted = W3Crypto.aes_ctr_decrypt(ciphertext, aes_key, aes_iv)
	assert_eq(decrypted.get_string_from_utf8(), original_text, "Decryption roundtrip successful")
	
	# Проверка integrity
	var wrong_iv = aes_iv.duplicate()
	wrong_iv[0] = (wrong_iv[0] + 1) % 256
	var decrypted_bad = W3Crypto.aes_ctr_decrypt(ciphertext, aes_key, wrong_iv)
	assert_true(decrypted_bad != data_to_encrypt, "Decryption with wrong IV produces garbage")


	# --- ТЕСТ 3: Argon2id (Детерминизм) ---
	log_section("3. Argon2id KDF Determinism")
	
	var argon_pass = "password"
	var argon_salt = "any_salt_min_8b".to_utf8_buffer()
	# Параметры: iterations=2, memory=65536(64MB), parallelism=1, length=32
	
	var t_start_argon = Time.get_ticks_msec()
	var argon_key1 = W3Crypto.argon2id(argon_pass, argon_salt, 2, 65536, 1, 32)
	var t_end_argon = Time.get_ticks_msec()
	
	assert_true(argon_key1.size() == 32, "Argon2id produced 32-byte key")
	log_info("Argon2id (64MB) took: %d ms" % (t_end_argon - t_start_argon))
	
	var argon_key2 = W3Crypto.argon2id(argon_pass, argon_salt, 2, 65536, 1, 32)
	# Используем secure_compare из C++
	assert_true(W3Crypto.secure_compare(argon_key1, argon_key2), "Argon2id result is deterministic")
	
	# Изменяем соль на 1 бит
	var argon_salt_mod = argon_salt.duplicate()
	argon_salt_mod[0] += 1
	var argon_key_diff = W3Crypto.argon2id(argon_pass, argon_salt_mod, 2, 65536, 1, 32)
	assert_true(!W3Crypto.secure_compare(argon_key1, argon_key_diff), "Changing salt changes key")

	pass_test("All C++ Keystore primitives are solid!")
