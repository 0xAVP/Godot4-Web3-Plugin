# demo/tests/live/account/test_01_wallet_integrity.gd
extends W3Test

func run(runner: Node):
	log_section("TESTING ETH_WALLET: SECURITY & SIGNING")
	
	var wallet = EthWallet.new()
	wallet.type = EthWallet.WalletType.BRAIN_WALLET
	wallet.app_id = "test_salt_123"
	wallet.iterations = 2
	runner.add_child(wallet)
	
	# --- 1. Проверка разблокировки ---
	log_info("Unlocking Brain Wallet...")
	var passw = "correct_password"
	assert_true(wallet.unlock(passw), "Wallet unlocked with password")
	assert_true(wallet.is_unlocked(), "State is_unlocked = true")
	
	var addr1 = wallet.get_address()
	log_info("Derived Address: " + addr1)
	assert_true(W3Utils.is_valid_address(addr1), "Address is valid")

	# --- 2. Проверка детерминизма ---
	wallet.lock()
	assert_true(!wallet.is_unlocked(), "Wallet locked")
	assert_eq(wallet.get_address(), "", "Address cleared after lock")
	
	wallet.unlock(passw)
	assert_eq(wallet.get_address(), addr1, "Brain wallet is deterministic (same pass = same addr)")

	# --- 3. Проверка подписи сообщения (EIP-191) ---
	log_section("Testing Message Signing")
	var msg = "Hello Godot Web3!"
	var sig = wallet.sign_message(msg)
	assert_true(sig.begins_with("0x"), "Signature has hex prefix")
	assert_eq(sig.length(), 132, "Signature length is 65 bytes + prefix")

	# Верификация через C++ (Sign -> Recover)
	var msg_bytes = msg.to_utf8_buffer()
	var prefix = PackedByteArray([0x19])
	prefix.append_array("Ethereum Signed Message:\n".to_utf8_buffer())
	prefix.append_array(str(msg_bytes.size()).to_utf8_buffer())
	var hash = W3Keccak.hash(prefix + msg_bytes)
	
	var recovered = W3Crypto.recover_address(hash, W3Utils.hex_to_bytes(sig))
	assert_eq(recovered.to_lower(), addr1.to_lower(), "Signature recovery matches wallet address")

	# --- 4. Проверка Simple Wallet ---
	log_section("Testing Simple (Random) Wallet")
	var swallet = EthWallet.new()
	swallet.type = EthWallet.WalletType.SIMPLE_RANDOM
	runner.add_child(swallet)
	
	await runner.get_tree().process_frame # Ждем вызова unlocked сигнала
	assert_true(swallet.is_unlocked(), "Simple wallet unlocked by default")
	var saddr = swallet.get_address()
	assert_true(!saddr.is_empty(), "Random address generated: " + saddr)

	wallet.queue_free()
	swallet.queue_free()
	pass_test("EthWallet integrity verified.")
