class_name EthBaseWallet extends EthInterfaceWallets

# Вместо одного ключа храним две части, которые при XOR дают ключ
var _masked_key: PackedByteArray = PackedByteArray()
var _session_mask: PackedByteArray = PackedByteArray()
var _address: String = ""

# --- Внутренние хелперы (Protected) ---

func _init_mask():
	# Генерируем случайную маску для текущей сессии
	_session_mask = W3Crypto.generate_private_key()

## Генерирует QR-код приватного ключа. 
## Возвращает ImageTexture, которую можно сразу вставить в TextureRect.
func get_private_key_qr(scale: int = 10) -> ImageTexture:
	if not is_unlocked(): return null
	
	var tmp_key = _unmask_key()
	var img = W3Crypto.generate_qr_code(tmp_key, scale)
	
	# Затираем ключ немедленно
	W3Crypto.secure_wipe(tmp_key)
	
	if img:
		return ImageTexture.create_from_image(img)
	return null

## Устанавливает ключ, маскирует его и вычисляет адрес.
func _set_key(raw_key: PackedByteArray) -> bool:
	if raw_key.size() != 32:
		return false
	
	if _session_mask.is_empty():
		_init_mask()
		
	# Маскируем: masked = raw ^ mask
	_masked_key.resize(32)
	for i in range(32):
		_masked_key[i] = raw_key[i] ^ _session_mask[i]
	
	# Вычисляем адрес из ЧИСТОГО ключа, пока он у нас есть
	var pub = W3Crypto.get_public_key(raw_key, false)
	_address = W3Crypto.get_address_from_pubkey(pub)
	
	# СРАЗУ затираем входящий чистый ключ
	W3Crypto.secure_wipe(raw_key)
	
	return true

# --- Реализация интерфейса ---

func verify_credentials(_password: String, _extra_entropy: Array = []) -> bool:
	return false

func lock() -> void:
	# Метод для ручного вызова (например, из интерфейса или родительского Node)
	if _masked_key.size() > 0:
		W3Crypto.secure_wipe(_masked_key)
	if _session_mask.size() > 0:
		W3Crypto.secure_wipe(_session_mask)
	_masked_key = PackedByteArray()
	_session_mask = PackedByteArray()
	_address = ""

func is_unlocked() -> bool:
	return not _address.is_empty() and _masked_key.size() == 32

func get_address() -> String:
	return _address

func sign_transaction(tx: W3Transaction) -> String:
	if not is_unlocked(): return ""
	
	# 1. Восстанавливаем чистый ключ во временный массив
	var tmp_key = _unmask_key()
	
	# 2. Подписываем
	var rlp = tx.sign(tmp_key)
	
	# 3. МГНОВЕННО затираем временный ключ
	W3Crypto.secure_wipe(tmp_key)
	
	return W3Utils.bytes_to_hex(rlp)

func sign_message(message: String) -> String:
	if not is_unlocked(): return ""
	
	var tmp_key = _unmask_key()
	
	var msg_bytes = message.to_utf8_buffer()
	var prefix = PackedByteArray([0x19])
	prefix.append_array("Ethereum Signed Message:\n".to_utf8_buffer())
	prefix.append_array(str(msg_bytes.size()).to_utf8_buffer())
	
	var hash = W3Keccak.hash(prefix + msg_bytes)
	var sig = W3Crypto.sign(hash, tmp_key)
	
	W3Crypto.secure_wipe(tmp_key)
	
	return W3Utils.bytes_to_hex(sig)

# Приватный метод для временного снятия маски
func _unmask_key() -> PackedByteArray:
	var res = PackedByteArray()
	res.resize(32)
	for i in range(32):
		res[i] = _masked_key[i] ^ _session_mask[i]
	return res

func _notification(what):
	if what == NOTIFICATION_PREDELETE:
		# ВАЖНО: В Godot 4 здесь нельзя вызывать методы (даже свои).
		# Обращаемся к переменным напрямую и используем статические методы классов.
		if _masked_key != null and _masked_key.size() > 0:
			W3Crypto.secure_wipe(_masked_key)
		if _session_mask != null and _session_mask.size() > 0:
			W3Crypto.secure_wipe(_session_mask)

func sign_raw_hash(hash: PackedByteArray) -> String:
	if not is_unlocked(): return ""
	var tmp_key = _unmask_key()
	var sig = W3Crypto.sign(hash, tmp_key) # Чистая подпись без префиксов
	W3Crypto.secure_wipe(tmp_key)
	return W3Utils.bytes_to_hex(sig)
