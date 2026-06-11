extends EthBaseWallet

# Настройки
var _salt: String
var _iterations: int
var _memory: int
var _parallelism: int

func _init(config: Dictionary):
	_salt = config.get("salt", "default_salt")
	_iterations = config.get("iterations", 2)
	_memory = config.get("memory", 65536)
	_parallelism = config.get("parallelism", 1)

## Внутренний метод генерации ключа, чтобы не дублировать код
func _derive_raw_key(password: String, extra_entropy: Array) -> PackedByteArray:
	var current_salt = W3Keccak.hash(_salt.to_utf8_buffer())
	for item in extra_entropy:
		var item_hash = W3Keccak.hash(str(item).to_utf8_buffer())
		var next_salt = W3Keccak.hash(current_salt + item_hash)
		W3Crypto.secure_wipe(current_salt)
		W3Crypto.secure_wipe(item_hash)
		current_salt = next_salt

	var derived_key = W3Crypto.argon2id(password, current_salt, _iterations, _memory, _parallelism, 32)
	W3Crypto.secure_wipe(current_salt)
	return derived_key

## Переписываем существующий unlock через новый метод
func unlock(password: String, extra_entropy: Array = []) -> bool:
	if password.is_empty(): return false
	var key = _derive_raw_key(password, extra_entropy)
	if key.is_empty(): return false
	var success = _set_key(key) # Внутри _set_key ключ будет затерт
	return success

## НОВАЯ ФУНКЦИЯ: Проверка без смены ключа
func verify_credentials(password: String, extra_entropy: Array = []) -> bool:
	if not is_unlocked(): 
		return false
	
	# 1. Генерируем временный ключ из введенных данных
	var temp_key = _derive_raw_key(password, extra_entropy)
	if temp_key.is_empty(): return false
	
	# 2. Получаем адрес из этого ключа
	var pub = W3Crypto.get_public_key(temp_key, false)
	var temp_address = W3Crypto.get_address_from_pubkey(pub)
	
	# 3. Сравниваем с текущим адресом кошелька (регистронезависимо)
	var is_match = (temp_address.to_lower() == get_address().to_lower())
	
	# 4. МГНОВЕННО затираем временные секреты
	W3Crypto.secure_wipe(temp_key)
	
	return is_match
