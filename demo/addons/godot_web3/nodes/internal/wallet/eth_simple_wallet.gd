extends EthBaseWallet

func _init(config: Dictionary = {}):
	# Simple Wallet можно инициализировать сразу с ключом (если передан в конфиге)
	# Или сгенерировать случайный
	if config.has("private_key_hex"):
		var pk_bytes = W3Utils.hex_to_bytes(config.private_key_hex)
		_set_key(pk_bytes)
	else:
		# Генерируем новый случайный кошелек
		var random_key = W3Crypto.generate_private_key()
		_set_key(random_key)

## Simple Wallet всегда считается "разблокированным", если у него есть ключ.
## Аргумент password игнорируется.
func unlock(password: String, extra_entropy: Array = []) -> bool:
	# Если ключ уже есть - мы разблокированы
	return is_unlocked()

func verify_credentials(_password: String, _extra_entropy: Array = []) -> bool:
	# Для Simple Wallet проверка пароля всегда возвращает true, 
	# если он создан, так как "пароля нет - проверять нечего".
	# Это позволит UI-цепочкам "введите пароль для подтверждения" 
	# просто проходить дальше для гостевых аккаунтов.
	return is_unlocked()
