# addons/godot_web3/utils/w3_utils.gd
class_name W3Utils extends RefCounted

const WEI_IN_ETHER = 1000000000000000000

# --- HEX OPERATIONS ---

static func bytes_to_hex(data: PackedByteArray, with_prefix: bool = true) -> String:
	var hex = data.hex_encode()
	if with_prefix:
		return "0x" + hex
	return hex

static func hex_to_bytes(hex: String) -> PackedByteArray:
	if hex.begins_with("0x") or hex.begins_with("0X"):
		hex = hex.substr(2)
	# Если длина нечетная, добавляем ведущий ноль (иначе hex_decode сломается)
	if hex.length() % 2 != 0:
		hex = "0" + hex
	return hex.hex_decode()

static func int_to_hex(value: int) -> String:
	return "0x%x" % value

static func hex_to_int(hex: String) -> int:
	if hex.begins_with("0x") or hex.begins_with("0X"):
		hex = hex.substr(2)
	if hex.is_empty(): return 0
	# Для длинных строк (как ответ eth_call) лучше брать только последние 16 символов,
	# так как nonce никогда не превысит размер 64-битного int.
	if hex.length() > 16:
		hex = hex.substr(hex.length() - 16)
	return hex.hex_to_int()

# --- VALIDATION ---

static func is_valid_address(addr: String) -> bool:
	var clean = addr.strip_edges()
	if clean.begins_with("0x"):
		clean = clean.substr(2)
	if clean.length() != 40:
		return false
	return clean.is_valid_hex_number(false)

static func is_zero_address(addr: String) -> bool:
	# Проверка на пустой адрес или 0x000...
	if addr.is_empty(): return true
	var clean = addr.replace("0x", "")
	for char in clean:
		if char != "0": return false
	return true

# --- CONVERSION (WEI <-> ETHER) ---

# Используем W3BigInt из C++ для точности
static func ether_to_wei(ether_amount: float) -> W3BigInt:
	# Конвертируем float в строку с запасом точности, затем парсим
	var ether_str = "%.18f" % ether_amount
	# Убираем лишние нули и точку, считаем позицию
	var parts = ether_str.split(".")
	var whole = parts[0]
	var fraction = parts[1] if parts.size() > 1 else ""
	
	# Обрезаем дробную часть до 18 знаков
	if fraction.length() > 18:
		fraction = fraction.substr(0, 18)
	# Дополняем нулями до 18
	fraction = fraction.rpad(18, "0")
		
	# Собираем число как целое (умножили на 10^18)
	var total_str = whole + fraction
	# Удаляем ведущие нули
	while total_str.length() > 1 and total_str[0] == "0":
		total_str = total_str.substr(1)
		
	return W3BigInt.from_string(total_str)

static func wei_to_ether(wei: W3BigInt) -> float:
	# Это потеря точности, но для UI допустимо
	var str_val = wei.to_string_val()
	if str_val.length() <= 18:
		# Меньше 1 эфира
		var padded = str_val.lpad(18, "0")
		return ("0." + padded).to_float()
	else:
		var whole_len = str_val.length() - 18
		var whole = str_val.substr(0, whole_len)
		var frac = str_val.substr(whole_len)
		return (whole + "." + frac).to_float()

static func format_wei(wei: W3BigInt, decimals: int = 4) -> String:
	var eth = wei_to_ether(wei)
	return str(snapped(eth, pow(10, -decimals))) + " ETH"

static func try_parse_error(rpc_error: Dictionary) -> String:
	var msg = rpc_error.get("message", "execution reverted")
	var data = rpc_error.get("data")
	
	# Если data — это словарь (бывает у некоторых провайдеров), ищем hex внутри
	if typeof(data) == TYPE_DICTIONARY:
		# Пытаемся найти любую строку, начинающуюся на 0x
		for key in data:
			if typeof(data[key]) == TYPE_STRING and data[key].begins_with("0x"):
				data = data[key]
				break
			elif key == "data" and typeof(data[key]) == TYPE_STRING: # Infura style
				data = data[key]
				break

	# Если теперь у нас есть HEX-строка
	if typeof(data) == TYPE_STRING and data.begins_with("0x") and data.length() > 2:
		var bytes = hex_to_bytes(data)
		# Наш C++ декодер вернет "execution reverted: Reason" или "Panic: Reason"
		return W3ABI.decode_revert_reason(bytes)
	
	# Если данных нет, возвращаем просто сообщение от узла
	return msg
