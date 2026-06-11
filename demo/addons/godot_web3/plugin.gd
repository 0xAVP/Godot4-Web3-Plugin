# demo/addons/godot_web3/plugin.gd
@tool
extends EditorPlugin

func _enter_tree():
	# В Godot 4 не нужно использовать add_custom_type, 
	# если в скриптах есть class_name.
	pass

func _exit_tree():
	pass
