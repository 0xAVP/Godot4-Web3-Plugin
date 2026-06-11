# addons/godot_web3/nodes/internal/eth_rpc_provider.gd
extends Node
class_name EthRpcProvider

var request_timeout: float = 10.0
var verbose_logs: bool = false
var _is_aborted: bool = false

func abort_all():
	_is_aborted = true

# Общий метод для создания JSON-RPC строки
func _prepare_payload(method: String, params: Array, r_id: int) -> String:
	var dict = {"jsonrpc": "2.0", "method": method, "params": params, "id": r_id}
	if verbose_logs: print("[%s] >> %s (id: %d)" % [get_class_name(), method, r_id])
	return JSON.stringify(dict)

# Общий метод для обработки "сырого" словаря из JSON
func _wrap_response(rpc_dict: Variant, http_code: int) -> Dictionary:
	return { "rpc_raw": rpc_dict, "http_code": http_code }

# Виртуальный метод, чтобы потомки могли называть себя в логах
func get_class_name() -> String:
	return "EthRpcProvider"
