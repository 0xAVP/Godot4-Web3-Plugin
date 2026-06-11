# demo/tests/live/account/test_02_account_flow.gd
extends W3Test

func run(runner: Node):
	log_section("TESTING ETH_ACCOUNT: FLOW & NONCE RACE PROTECTION")
	
	var client = runner.get_node("EthClient")
	var wallet = runner.get_node("EthWallet")
	
	var acc = EthAccount.new()
	acc.client_path = client.get_path()
	acc.wallet_path = wallet.get_path()
	runner.add_child(acc)
	
	if not wallet.is_unlocked():
		wallet.unlock("test_password")

	log_info("Syncing nonce from network...")
	await acc.sync_nonce()
	var n_start = acc.get_nonce()
	log_info("Initial Nonce: %d" % n_start)

	log_section("Stress Test: Rapid Transaction Sending")
	log_info("Firing 3 transactions simultaneously...")
	
	var target_addr = "0x0000000000000000000000000000000000000000"
	var amount = W3BigInt.from_int(0)
	
	# Счётчик завершенных транзакций для финального ожидания
	var completed = 0
	var tracker = func(): 
		await acc.send_transaction(target_addr, amount)
		completed += 1

	# Запускаем 3 корутины без await. 
	# Они выполнятся до первой приостановки (await) внутри send_transaction.
	tracker.call()
	tracker.call()
	tracker.call()

	# --- МОМЕНТ ИСТИНЫ ---
	# Внутри send_transaction инкремент происходит ДО сетевых вызовов.
	# Так как tracker.call() "споткнулся" о первый сетевой await внутри EthAccount,
	# управление вернулось сюда мгновенно, но Nonce уже должен быть увеличен.
	
	var n_now = acc.get_nonce()
	log_info("Nonce after rapid firing: %d" % n_now)
	
	assert_eq(n_now, n_start + 3, "Nonce incremented 3 times before network finished")
	
	log_info("Now waiting for network requests to finish...")
	# Ждем, пока все три лямбды завершатся (таймаут 15 секунд для безопасности)
	var timeout = 15.0
	while completed < 3 and timeout > 0:
		await runner.get_tree().process_frame
		timeout -= 1.0/60.0
	
	# --- 3. Проверка сборки (Gas Strategy) ---
	log_section("Checking Transaction Assembly")
	var fees = {
		"type": W3Transaction.TYPE_EIP1559,
		"max_fee_per_gas": W3BigInt.from_int(50000000000),
		"max_priority_fee_per_gas": W3BigInt.from_int(1500000000)
	}
	var tx = acc._assemble_tx(target_addr, amount, PackedByteArray(), 10, 21000, fees)
	assert_eq(tx.get_nonce().to_int256_string(), "10", "Nonce in TX object")
	
	acc.queue_free()
	pass_test("EthAccount flow and race protection verified!")
