class_name EthInterfaceWallets extends RefCounted

# Интерфейс, который должны реализовать все модули (Brain, Keystore, Ledger и т.д.)

func verify_credentials(password: String, extra_entropy: Array = []) -> bool:
	return false

func unlock(password: String, extra_entropy: Array = []) -> bool:
	return false

func lock() -> void:
	pass

func is_unlocked() -> bool:
	return false

func get_address() -> String:
	return ""

func sign_transaction(tx: W3Transaction) -> String:
	return ""

func sign_message(message: String) -> String:
	return ""

func sign_raw_hash(hash: PackedByteArray) -> String:
	return ""
