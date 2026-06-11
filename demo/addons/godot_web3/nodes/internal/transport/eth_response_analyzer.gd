# addons/godot_web3/nodes/internal/eth_response_analyzer.gd
class_name EthResponseAnalyzer extends RefCounted

enum Verdict { OK, RETRY, FATAL }

## Анализирует ответ от RPC и возвращает вердикт: стоит ли пробовать другую ноду.
static func analyze(response: Variant, http_code: int = 200) -> Dictionary:
	# 1. Проверка транспортного уровня (HTTP / WS)
	# Код 0 — это "Connection Error" в Godot (нода лежит или DNS упал)
	# Код 408 — это таймаут
	var is_retry_code = (
		http_code == -1 or # Добавлено: Мягкая отмена для переезда
		http_code == 0 or 
		http_code == 408 or 
		http_code == 429 or 
		(http_code >= 500 and http_code <= 599)
	)
	
	if is_retry_code:
		return _result(Verdict.RETRY, null, "Node infrastructure error (HTTP %d)" % http_code)
	
	if http_code != 200:
		return _result(Verdict.FATAL, null, "Critical transport error (HTTP %d)" % http_code)

	# 2. Базовая проверка структуры
	if response == null:
		return _result(Verdict.RETRY, null, "Empty response body")
	
	if typeof(response) != TYPE_DICTIONARY:
		return _result(Verdict.RETRY, null, "Response is not a valid JSON object")

	# 3. Анализ RPC Ошибки
	if response.has("error"):
		var err = response["error"]
		var msg = str(err.get("message", "")).to_lower()
		var code = int(err.get("code", 0))
		
		# Список признаков того, что нода "плохая" (RETRY)
		var node_issues = [
			"syncing", "rate limit", "too many requests", 
			"exhausted", "timeout", "behind chain", "not found"
		]
		
		var is_node_issue = false
		for issue in node_issues:
			if issue in msg:
				is_node_issue = true
				break
		
		# Специфические коды некоторых провайдеров (Alchemy/Infura)
		if code == -32005 or code == -32000 and "timeout" in msg:
			is_node_issue = true
			
		if is_node_issue:
			return _result(Verdict.RETRY, err, "Node issue: " + msg)
		else:
			# Логические ошибки (Revert, No funds, Nonce too low) - FATAL
			return _result(Verdict.FATAL, err, "Logic/Protocol error: " + msg)

	# 4. Успех
	if not response.has("result"):
		# Некоторые ноды при успехе могут не прислать result (редко)
		return _result(Verdict.RETRY, null, "Missing 'result' field in success response")

	return _result(Verdict.OK, response["result"])

static func _result(v: Verdict, err: Variant, msg: String = "") -> Dictionary:
	return { "verdict": v, "error": err, "message": msg, "data": null if v != Verdict.OK else err }
