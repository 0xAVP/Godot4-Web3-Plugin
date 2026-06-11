# addons/godot_web3/nodes/internal/contract/eth_abi_indexer.gd
class_name EthAbiIndexer extends RefCounted

func index_manifest(abi_array: Array) -> Dictionary:
	var res = { "methods": {}, "events_by_topic": {}, "events_by_name": {} }
	for item in abi_array:
		var type = item.get("type", "")
		var name = item.get("name", "")
		if name == "": continue
		var signature = item.get("godot_signature", "")
		
		if type == "function":
			res.methods[name] = {
				"selector": W3ABI.encode_function_selector(signature) if not signature.is_empty() else PackedByteArray(),
				"input_types": item.get("inputs", []).map(func(x): return _extract_canonical_type(x)),
				"output_types": item.get("godot_output_types", []),
				"output_names": item.get("godot_output_names", []),
				"is_constant": item.get("stateMutability", "") in ["view", "pure"]
			}
		elif type == "event":
			var topic_0 = W3Utils.bytes_to_hex(W3Keccak.hash(signature.to_utf8_buffer()))
			var indexed_params = []
			var data_params = []
			for input in item.get("inputs", []):
				var p_info = {"name": input.name, "type": _extract_canonical_type(input)}
				if input.get("indexed", false): indexed_params.append(p_info)
				else: data_params.append(p_info)
			res.events_by_topic[topic_0] = {
				"name": name, "indexed_params": indexed_params, 
				"data_params": data_params, "data_types": data_params.map(func(x): return x.type)
			}
			res.events_by_name[name] = topic_0
	return res

func _extract_canonical_type(param: Dictionary) -> String:
	if param.type.begins_with("tuple"):
		var components = []
		for c in param.components: components.append(_extract_canonical_type(c))
		return "(%s)%s" % [",".join(components), param.type.substr(5)]
	return param.type
