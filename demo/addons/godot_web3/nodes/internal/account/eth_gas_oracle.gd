class_name EthGasOracle extends RefCounted

# Настройки
var strategy: String = "eip1559"
var buffer_pct: int = 15
var manual_limit: int = 0
var priority: int = 1 # EthAccount.PriorityLevel

func _init(p_strategy: String, p_buffer: int, p_limit: int, p_priority: int):
	strategy = p_strategy
	buffer_pct = p_buffer
	manual_limit = p_limit
	priority = p_priority

## Оценка лимита газа с учетом процентного буфера
func estimate_limit(client: EthClient, tx_params: Dictionary) -> int:
	if manual_limit > 0:
		return manual_limit
		
	var res = await client.request("eth_estimateGas", [tx_params])
	if res:
		var est = W3Utils.hex_to_int(res)
		# Формула: est * (1 + buffer/100)
		var buffer_multiplier = 1.0 + (float(buffer_pct) / 100.0)
		return int(est * buffer_multiplier)
	return 0

## Оценка комиссий (EIP-1559 / Legacy)
func fetch_fees(client: EthClient) -> Dictionary:
	var result = {}
	
	if strategy == "eip1559":
		# 1. Получаем базовую комиссию последнего блока
		var block_data = await client.request("eth_getBlockByNumber", ["latest", false])
		var base_fee = W3BigInt.from_int(0)
		if block_data and block_data.has("baseFeePerGas"):
			base_fee = W3BigInt.from_hex(block_data["baseFeePerGas"])
		
		# 2. Получаем рекомендованный Priority Fee (чаевые) от узла
		var prio_hex = await client.request("eth_maxPriorityFeePerGas")
		var network_prio = W3BigInt.from_hex(prio_hex if prio_hex else "0x59682F00") # 1.5 Gwei fallback
		
		# 3. Применяем модификаторы приоритета
		var prio_multiplier: float = 1.0
		var base_bump_multiplier: float = 1.1 # Запас по базовой цене
		
		match priority:
			0: # SLOW
				prio_multiplier = 0.8
				base_bump_multiplier = 1.05
			1: # MARKET
				prio_multiplier = 1.1 # Небольшой запас выше рынка
				base_bump_multiplier = 1.15
			2: # AGGRESSIVE
				prio_multiplier = 2.0 # Двойные чаевые для быстрого включения
				base_bump_multiplier = 1.5  # Огромный запас для резких скачков
		
		# Вычисляем финальный Priority Fee
		var m_prio_big = W3BigInt.from_string(str(int(prio_multiplier * 100)))
		var final_prio = network_prio.mul(m_prio_big).div(W3BigInt.from_int(100))
		
		# Вычисляем финальный Max Fee = (BaseFee * base_bump) + final_prio
		var m_base_big = W3BigInt.from_string(str(int(base_bump_multiplier * 100)))
		var bumped_base = base_fee.mul(m_base_big).div(W3BigInt.from_int(100))
		
		# Согласно EIP-1559: MaxFee = MaxPriorityFee + (2 * BaseFee) для гарантии включения в следующие 6 блоков
		# Но мы используем наш bumped_base для более гибкого контроля в играх
		var max_fee = bumped_base.add(final_prio)
		
		result["type"] = W3Transaction.TYPE_EIP1559
		result["max_priority_fee_per_gas"] = final_prio
		result["max_fee_per_gas"] = max_fee
		
	else:
		# Legacy Logic (Gas Price)
		var price = await client.get_gas_price()
		var legacy_multiplier = 1.0
		
		match priority:
			0: legacy_multiplier = 0.9
			1: legacy_multiplier = 1.1
			2: legacy_multiplier = 1.5
			
		var m_big = W3BigInt.from_string(str(int(legacy_multiplier * 100)))
		var final_price = price.mul(m_big).div(W3BigInt.from_int(100))
		
		result["type"] = W3Transaction.TYPE_LEGACY
		result["gas_price"] = final_price
		
	return result
