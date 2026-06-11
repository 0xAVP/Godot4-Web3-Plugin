# tests/live/test_13_analyzer_unit.gd
extends W3Test

const Analyzer = preload("res://addons/godot_web3/nodes/internal/transport/eth_response_analyzer.gd")
const Verdict = Analyzer.Verdict

func run(_runner: Node):
	log_section("UNIT TEST: EthResponseAnalyzer")

	# --- ГРУППА 1: УСПЕХ ---
	log_section("Category: Success Scenarios")
	
	_check_analysis({"result": "0x1"}, 200, Verdict.OK, "Standard success")
	_check_analysis({"result": {"status": "0x1"}}, 200, Verdict.OK, "Complex result success")
	_check_analysis({"result": []}, 200, Verdict.OK, "Empty array success")

	# --- ГРУППА 2: ТРАНСПОРТНЫЕ ОШИБКИ (RETRY) ---
	log_section("Category: Transport Retry (Node/Network issues)")
	
	_check_analysis(null, 0, Verdict.RETRY, "Physical network failure (HTTP 0)")
	_check_analysis(null, 408, Verdict.RETRY, "Request timeout (HTTP 408)")
	_check_analysis(null, 429, Verdict.RETRY, "Rate Limit (HTTP 429)")
	_check_analysis(null, 500, Verdict.RETRY, "Internal Server Error (HTTP 500)")
	_check_analysis(null, 503, Verdict.RETRY, "Service Unavailable (HTTP 503)")
	_check_analysis("not json", 200, Verdict.RETRY, "Malformed non-JSON response")

	# --- ГРУППА 3: КРИТИЧЕСКИЕ ОШИБКИ ТРАНСПОРТА (FATAL) ---
	log_section("Category: Transport Fatal (Config issues)")
	
	_check_analysis(null, 404, Verdict.FATAL, "Wrong RPC URL (HTTP 404)")
	_check_analysis(null, 401, Verdict.FATAL, "Unauthorized/API Key issues (HTTP 401)")
	_check_analysis(null, 400, Verdict.FATAL, "Bad Request (HTTP 400)")

	# --- ГРУППА 4: RPC ИНФРАСТРУКТУРНЫЕ ОШИБКИ (RETRY) ---
	log_section("Category: RPC Infrastructure Retry")
	
	_check_analysis(
		{"error": {"code": -32000, "message": "node is syncing"}}, 
		200, Verdict.RETRY, "Node is syncing"
	)
	_check_analysis(
		{"error": {"code": -32005, "message": "limit exceeded"}}, 
		200, Verdict.RETRY, "Alchemy/Infura limit code -32005"
	)
	_check_analysis(
		{"error": {"code": -32000, "message": "execution aborted (timeout)"}}, 
		200, Verdict.RETRY, "Execution timeout on node"
	)
	_check_analysis(
		{"error": {"message": "too many requests"}}, 
		200, Verdict.RETRY, "Rate limit in message text"
	)
	_check_analysis(
		{"error": {"message": "behind chain head"}}, 
		200, Verdict.RETRY, "Node is lagging"
	)

	# --- ГРУППА 5: RPC ЛОГИЧЕСКИЕ ОШИБКИ (FATAL) ---
	log_section("Category: RPC Logic Fatal (User/Protocol issues)")
	
	_check_analysis(
		{"error": {"code": -32602, "message": "invalid params"}}, 
		200, Verdict.FATAL, "Invalid method parameters"
	)
	_check_analysis(
		{"error": {"message": "execution reverted: not an owner"}}, 
		200, Verdict.FATAL, "Smart-contract Reverted"
	)
	_check_analysis(
		{"error": {"message": "insufficient funds for gas * price + value"}}, 
		200, Verdict.FATAL, "Insufficient funds"
	)
	_check_analysis(
		{"error": {"message": "nonce too low"}}, 
		200, Verdict.FATAL, "Transaction Nonce too low"
	)
	_check_analysis(
		{"error": {"message": "invalid signature"}}, 
		200, Verdict.FATAL, "Crypto signature failed"
	)

	log_section("=== ANALYZER UNIT TEST COMPLETE ===")

# --- Helper ---

func _check_analysis(raw_rpc: Variant, http_code: int, expected_v: int, test_name: String):
	var res = Analyzer.analyze(raw_rpc, http_code)
	
	var v_names = {
		Verdict.OK: "OK",
		Verdict.RETRY: "RETRY",
		Verdict.FATAL: "FATAL"
	}
	
	var actual_v = res.verdict
	if actual_v == expected_v:
		pass_test("%s -> %s" % [test_name, v_names[actual_v]])
	else:
		fail_test("%s (Expected %s, got %s) | Msg: %s" % [
			test_name, 
			v_names[expected_v], 
			v_names[actual_v],
			res.message
		])
