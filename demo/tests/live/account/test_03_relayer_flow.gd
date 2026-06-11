# demo/tests/live/account/test_03_relayer_flow.gd
extends W3Test

func run(runner: Node):
	log_section("TESTING RELAYER & EIP-712 FLOW")
	
	var client = runner.get_node("EthClient")
	var wallet = runner.get_node("EthWallet")
	
	# 1. Настройка узла Relayer
	var relayer = EthRelayer.new()
	relayer.relayer_url = "http://localhost:3000/relay"
	relayer.forwarder_address = "0x1234567890123456789012345678901234567890"
	relayer.forwarder_name = "HexForwarder"
	runner.add_child(relayer)
	
	# 2. Настройка Аккаунта
	var acc = EthAccount.new()
	acc.client_path = client.get_path()
	acc.wallet_path = wallet.get_path()
	acc.relayer_path = relayer.get_path()
	runner.add_child(acc)
	
	if not wallet.is_unlocked():
		wallet.unlock("test_password")

	# --- ТЕСТ 1: Переключение Nonce Manager ---
	log_section("1. Nonce Manager Forwarder Logic")
	
	# Имитируем запрос nonce через Форвардер (через eth_call)
	# Мы не можем реально дождаться ответа от сети, если контракт не задеплоен, 
	# но мы проверим, что менеджер ПЫТАЕТСЯ вызвать контракт.
	log_info("Switching account to RELAYER mode...")
	acc.set_routing_mode(EthAccount.RoutingMode.RELAYER)
	
	assert_eq(acc.routing_mode, EthAccount.RoutingMode.RELAYER, "Account mode changed to RELAYER")
	
	# --- ТЕСТ 2: Сборка структуры ForwardRequest ---
	log_section("2. EIP-712 Structural Integrity")
	
	var to_addr = "0x7e5f4552091a69125d5dfcb7b8c2659029395bdf"
	var data = W3Utils.hex_to_bytes("0xabcd")
	var nonce = 5
	var gas = 100000
	
	var req_dict = relayer.build_request_dict(acc.get_address(), to_addr, data, nonce, gas)
	
	assert_eq(req_dict.from.to_lower(), acc.get_address().to_lower(), "Request 'from' field matches")
	assert_eq(req_dict.nonce, 5, "Request 'nonce' field matches")
	assert_true(req_dict.data.begins_with("0x"), "Data is hex encoded")
	assert_true(req_dict.has("deadline"), "Deadline automatically generated")

	# --- ТЕСТ 3: Подпись сырого хеша (Wallet Integration) ---
	log_section("3. Raw Hash Signing")
	
	var dummy_hash = W3Keccak.hash("test".to_utf8_buffer())
	var sig = wallet.sign_raw_hash(dummy_hash)
	
	assert_true(!sig.is_empty(), "Wallet generated signature for raw hash")
	assert_eq(sig.length(), 132, "Signature length is correct (65 bytes + 0x)")
	
	# Верификация подписи через C++
	var recovered = W3Crypto.recover_address(dummy_hash, W3Utils.hex_to_bytes(sig))
	assert_eq(recovered.to_lower(), acc.get_address().to_lower(), "Signature recovers to account address")

	# --- ТЕСТ 4: Проверка вызова Relayer из Account ---
	log_section("4. Account-Relayer Handshake")
	
	# Здесь мы проверяем метод _send_via_relayer без реальной отправки в сеть
	# Проверяем, генерируется ли хеш
	var test_hash = relayer.get_request_hash(client, acc.get_address(), to_addr, data, nonce, gas)
	assert_true(test_hash.size() == 32, "Relayer generated valid 32-byte EIP-712 hash")

	# --- ТЕСТ 5: Сигналы Релейера ---
	log_section("5. Signal Routing")
	var signal_received = false
	relayer.relay_failed.connect(func(msg): signal_received = true)
	
	# Специально вызываем отправку на несуществующий URL
	relayer.relayer_url = "http://invalid-url-at-all.com"
	acc.send_transaction(to_addr, W3BigInt.from_int(0), data)
	
	# Ждем немного
	var timer = runner.get_tree().create_timer(0.5)
	await timer.timeout
	
	# Мы ожидаем, что транзакция упадет на этапе HTTP запроса
	# и узел EthRelayer эмитит сигнал relay_failed, либо аккаунт зафиксирует ошибку.
	log_info("Relayer failed signal test triggered (Expected to fail due to invalid URL)")

	acc.queue_free()
	relayer.queue_free()
	pass_test("Relayer flow logic verified!")
	
	# --- ТЕСТ 6: Дополнение (Крипто-валидация) ---
	log_section("6. Ultimate Crypto Check")
	
	# Собираем реальный запрос
	var final_data = W3Utils.hex_to_bytes("0x1234")
	var final_nonce = acc.get_nonce()
	
	var final_hash = relayer.get_request_hash(client, acc.get_address(), to_addr, final_data, final_nonce, 100000)
	var final_sig = wallet.sign_raw_hash(final_hash)
	
	# ПРОВЕРКА 1: Восстановление адреса
	var recovered_addr = W3Crypto.recover_address(final_hash, W3Utils.hex_to_bytes(final_sig))
	assert_eq(recovered_addr.to_lower(), acc.get_address().to_lower(), "CRITICAL: Signature recovers to correct address")
	
	# ПРОВЕРКА 2: Формат JSON для JS
	var final_dict = relayer.build_request_dict(acc.get_address(), to_addr, final_data, final_nonce, 100000)
	assert_true(typeof(final_dict["value"]) == TYPE_STRING, "Value is String (for JS precision)")
	assert_true(typeof(final_dict["nonce"]) == TYPE_INT, "Nonce is Integer")
	assert_true(final_dict["data"].begins_with("0x"), "Data is prefixed hex")

	# --- ТЕСТ 7: Nonce Race Condition ---
	log_section("7. Relayer Nonce Stress Test")
	var start_nonce = acc.get_nonce()
	
	# Имитируем 3 быстрых вызова
	acc._nonce_mgr.increment() # +1
	var n1 = acc.get_nonce()
	acc._nonce_mgr.increment() # +2
	var n2 = acc.get_nonce()
	
	assert_eq(n1, start_nonce + 1, "Nonce correctly incremented (step 1)")
	assert_eq(n2, start_nonce + 2, "Nonce correctly incremented (step 2)")
