# addons/godot_web3/nodes/eth_contract.gd
@icon("res://addons/godot_web3/icons/icon.svg")
class_name EthContract extends Node

signal event_received(event_name: String, data: Dictionary)

@export_group("Artifact")
@export_file("*.json") var manifest_path: String

@export_group("Network")
@export var contract_address: String
@export var client_path: NodePath
@export var account_path: NodePath

@export_group("Settings")
enum OutputFormat { NAMED_DICTIONARY, RAW_ARRAY }
@export var output_format: OutputFormat = OutputFormat.NAMED_DICTIONARY
@export var verbose: bool = false

var _registry: Dictionary = { "methods": {}, "events_by_topic": {}, "events_by_name": {} }
var _event_subs: Dictionary = {} 

var _indexer = preload("res://addons/godot_web3/nodes/internal/contract/eth_abi_indexer.gd").new()
var _mapper = preload("res://addons/godot_web3/nodes/internal/contract/eth_data_mapper.gd").new()

@onready var client: EthClient = get_node_or_null(client_path)
@onready var account: EthAccount = get_node_or_null(account_path)

func _ready():
	if not manifest_path.is_empty():
		_load_manifest_from_path()

func _load_manifest_from_path():
	if not FileAccess.file_exists(manifest_path):
		push_error("EthContract: File not found: %s" % manifest_path)
		return
	var file_content = FileAccess.get_file_as_string(manifest_path)
	var data = JSON.parse_string(file_content)
	if data and data.has("abi"):
		setup_abi(data["abi"])

## Публичный метод для настройки ABI (используется автоматически или вручную в тестах)
func setup_abi(abi_array: Array):
	_registry = _indexer.index_manifest(abi_array)
	# Подключаем сигнал клиента только когда мы готовы декодировать данные
	if client and not client.subscription_event.is_connected(_on_eth_event):
		client.subscription_event.connect(_on_eth_event)

func _exit_tree():
	unsubscribe_all()

# --- PUBLIC API: METHODS ---

func call_func(method_name: String, args: Array = []) -> Variant:
	if not _registry.methods.has(method_name): return null
	var m = _registry.methods[method_name]
	var calldata = _encode_method_call(m, args)
	var res = await client.request("eth_call", [{"to": contract_address, "data": W3Utils.bytes_to_hex(calldata)}, "latest"])
	if res == null: return null
	var decoded = W3ABI.decode(m.output_types, W3Utils.hex_to_bytes(str(res)))
	return _mapper.map_to_named(decoded, m.output_names) if output_format == OutputFormat.NAMED_DICTIONARY else decoded

func send_func(method_name: String, args: Array = [], value: W3BigInt = null) -> String:
	if not _registry.methods.has(method_name) or not account: return ""
	var m = _registry.methods[method_name]
	return await account.send_transaction(contract_address, value if value else W3BigInt.from_int(0), _encode_method_call(m, args))

# --- PUBLIC API: EVENTS ---

func subscribe_event(event_name: String) -> String:
	if not client or _event_subs.has(event_name): return ""
	if not _registry.events_by_name.has(event_name): return ""
	var topic_0 = _registry.events_by_name[event_name]
	var filter = {"address": contract_address, "topics": [[topic_0]]}
	var sub_id = await client.subscribe(["logs", filter])
	if not sub_id.is_empty():
		_event_subs[event_name] = sub_id
	return sub_id

func unsubscribe_event(event_name: String) -> bool:
	if not client or not _event_subs.has(event_name): return false
	var sub_id = _event_subs[event_name]
	var success = await client.unsubscribe(sub_id)
	if success: _event_subs.erase(event_name)
	return success

func unsubscribe_all():
	if not client: return
	var names = _event_subs.keys().duplicate()
	for n in names: await unsubscribe_event(n)

# --- INTERNAL ---

func _on_eth_event(sub_id: String, result: Variant):
	if not sub_id in _event_subs.values(): return
	if typeof(result) != TYPE_DICTIONARY or not result.has("topics"): return
	var topic_0 = result.topics[0]
	if _registry.events_by_topic.has(topic_0):
		_process_event_log(topic_0, result)

func _process_event_log(topic_0: String, log_data: Dictionary):
	var meta = _registry.events_by_topic[topic_0]
	var out = {}
	if not meta.data_types.is_empty():
		var raw = W3ABI.decode(meta.data_types, W3Utils.hex_to_bytes(log_data.data))
		for i in range(raw.size()):
			out[meta.data_params[i].name] = raw[i]
	for i in range(meta.indexed_params.size()):
		var p = meta.indexed_params[i]
		var raw_t = log_data.topics[i + 1]
		if p.type == "address": out[p.name] = "0x" + raw_t.substr(26)
		elif p.type.begins_with("uint") or p.type.begins_with("int"): out[p.name] = W3BigInt.from_hex(raw_t)
		else: out[p.name] = raw_t
	event_received.emit(meta.name, out)

func _encode_method_call(m: Dictionary, args: Array) -> PackedByteArray:
	var payload = W3ABI.encode_params(m.input_types, args)
	var res = PackedByteArray()
	res.append_array(m.selector)
	res.append_array(payload)
	return res
