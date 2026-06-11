# demo/tests/runner.gd
extends Node

enum TestSuite {
	ALL,
	CPP,
	ACCOUNT,
	TRANSPORT,
	CONTRACT
}

@export var suite_to_run: TestSuite = TestSuite.ALL
@export var stop_on_failure: bool = false

const BASE_DIR = "res://tests/live/"

func _ready():
	# Даем кадру завершиться, чтобы все узлы в сцене (EthClient и т.д.) инициализировались
	await get_tree().process_frame
	
	var folder_name = ""
	match suite_to_run:
		TestSuite.CPP: folder_name = "cpp/"
		TestSuite.ACCOUNT: folder_name = "account/"
		TestSuite.TRANSPORT: folder_name = "transport/"
		TestSuite.CONTRACT: folder_name = "contract/"
	
	print_rich("\n[b][color=cyan]=== STARTING WEB3 TEST RUNNER ===[/color][/b]")
	print_rich("[color=gray]Mode: %s[/color]\n" % TestSuite.keys()[suite_to_run])
	
	await _run_tests_in_folder(folder_name)
	
	print_rich("\n[b][color=cyan]=== ALL SELECTED TESTS FINISHED ===[/color][/b]")

func _run_tests_in_folder(subfolder: String):
	var target_dir = BASE_DIR + subfolder
	var scripts = _get_all_gd_files(target_dir)
	
	if scripts.is_empty():
		print_rich("[color=yellow]No tests found in: %s[/color]" % target_dir)
		return

	for script_path in scripts:
		var script_name = script_path.get_file()
		print_rich("[b]>>> RUNNING: %s[/b]" % script_name)
		
		var TestClass = load(script_path)
		if not TestClass:
			print_rich("[color=red]Failed to load script: %s[/color]" % script_path)
			continue
			
		var test_instance = TestClass.new()
		
		if test_instance.has_method("run"):
			await test_instance.run(self)
			
			if stop_on_failure and test_instance.get("_failed"):
				print_rich("[color=red]Stopping suite due to failure in %s[/color]" % script_name)
				return
		else:
			print_rich("[color=yellow]Script %s does not have a run() method[/color]" % script_name)

## Рекурсивно или выборочно собирает файлы .gd
func _get_all_gd_files(path: String) -> Array[String]:
	var files: Array[String] = []
	var dir = DirAccess.open(path)
	
	if not dir:
		printerr("Cannot open directory: ", path)
		return files

	dir.list_dir_begin()
	var item_name = dir.get_next()
	
	while item_name != "":
		var full_path = path.path_join(item_name)
		
		if dir.current_is_dir():
			# Если мы в режиме ALL, заходим в подпапки
			if suite_to_run == TestSuite.ALL:
				files.append_array(_get_all_gd_files(full_path + "/"))
		elif item_name.ends_with(".gd"):
			files.append(full_path)
			
		item_name = dir.get_next()
	
	files.sort()
	return files
