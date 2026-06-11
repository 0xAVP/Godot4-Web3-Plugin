# tests/test_base.gd
class_name W3Test extends RefCounted

var _failed: bool = false

# Виртуальный метод
func run(_runner: Node) -> void:
	pass

# --- Логирование ---

func log_section(msg: String):
	print_rich("[b][color=yellow]--- %s ---[/color][/b]" % msg)

func pass_test(msg: String):
	print_rich("  [color=green]✔ %s[/color]" % msg)

func fail_test(msg: String):
	_failed = true
	print_rich("  [color=red]✘ %s[/color]" % msg)

func log_info(msg: String):
	print_rich("  [color=gray]info: %s[/color]" % msg)

# --- Ассерты (Проверки) ---

func assert_true(condition: bool, msg: String):
	if condition:
		pass_test(msg)
	else:
		fail_test("%s (Expected true, got false)" % msg)

func assert_not_null(obj: Variant, msg: String):
	if obj != null:
		pass_test(msg)
	else:
		fail_test("%s (Got null)" % msg)

func assert_eq(actual: Variant, expected: Variant, msg: String):
	# Универсальное получение строкового представления
	var a_str = _to_str(actual)
	var e_str = _to_str(expected)
	
	if a_str == e_str:
		pass_test("%s [%s]" % [msg, a_str])
	else:
		fail_test("%s (Expected '%s', got '%s')" % [msg, e_str, a_str])

# Вспомогательная функция для безопасного перевода в строку
func _to_str(v: Variant) -> String:
	if typeof(v) == TYPE_OBJECT and v != null:
		if v.has_method("to_string_val"):
			return v.to_string_val()
		if v.has_method("to_int256_string"):
			return v.to_int256_string()
	if typeof(v) == TYPE_ARRAY:
		var items = []
		for item in v:
			items.append(_to_str(item))
		return "[" + ", ".join(items) + "]"
	return str(v)
