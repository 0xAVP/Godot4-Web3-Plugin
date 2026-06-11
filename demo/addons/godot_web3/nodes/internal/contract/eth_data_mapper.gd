# addons/godot_web3/nodes/internal/contract/eth_data_mapper.gd
class_name EthDataMapper extends RefCounted

func map_to_named(raw_results: Array, output_names: Array) -> Variant:
	if output_names.is_empty() or raw_results.is_empty(): return raw_results
	if raw_results.size() == 1: return _dispatch_mapping(raw_results[0], output_names[0])
	var result_dict = {}
	for i in range(raw_results.size()):
		var metadata = output_names[i]
		var key = metadata if typeof(metadata) == TYPE_STRING and not metadata.is_empty() else str(i)
		result_dict[key] = _dispatch_mapping(raw_results[i], metadata)
	return result_dict

func _dispatch_mapping(data: Variant, metadata: Variant) -> Variant:
	if typeof(metadata) == TYPE_ARRAY and typeof(data) == TYPE_ARRAY:
		if data.size() > 0 and typeof(data[0]) == TYPE_ARRAY:
			var list = []
			for item in data: list.append(_map_struct(item, metadata))
			return list
		return _map_struct(data, metadata)
	return data

func _map_struct(struct_values: Array, field_names: Array) -> Dictionary:
	var out = {}
	for i in range(min(struct_values.size(), field_names.size())):
		var f_name = field_names[i]
		var key = f_name if typeof(f_name) == TYPE_STRING and not f_name.is_empty() else "field_" + str(i)
		out[key] = struct_values[i]
	return out
