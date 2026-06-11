extends RefCounted

# { "local_id": { "params": [], "remote_id": "", "last_block": 0 } }
var _subs: Dictionary = {}
var _remote_to_local: Dictionary = {}
var _counter: int = 0

func register(remote_id: String, params: Array) -> String:
	_counter += 1
	var local_id = "sub_" + str(_counter)
	# Добавляем поле last_block
	_subs[local_id] = {"params": params, "remote_id": remote_id, "last_block": 0}
	_remote_to_local[remote_id] = local_id
	return local_id

func update_last_block(local_id: String, block: int):
	if _subs.has(local_id):
		# Обновляем только если новый блок выше старого
		if block > _subs[local_id].last_block:
			_subs[local_id].last_block = block

func get_last_block(local_id: String) -> int:
	return _subs.get(local_id, {}).get("last_block", 0)

func update_remote_id(local_id: String, new_remote_id: String):
	if _subs.has(local_id):
		var old_remote = _subs[local_id].remote_id
		_remote_to_local.erase(old_remote)
		_subs[local_id].remote_id = new_remote_id
		_remote_to_local[new_remote_id] = local_id

func get_local_id(remote_id: String) -> String:
	return _remote_to_local.get(remote_id, "")

func get_all_subs() -> Dictionary:
	return _subs

func remove_local(local_id: String):
	if _subs.has(local_id):
		var remote_id = _subs[local_id].remote_id
		_remote_to_local.erase(remote_id)
		_subs.erase(local_id)
