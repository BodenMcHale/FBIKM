@tool
extends EditorPlugin

func _enter_tree():
	# Add custom node types to the editor
	add_custom_type(
		"FBIKManager", 
		"Node3D", 
		preload("res://addons/FBIK/scripts/IKManager.gd"), 
		preload("res://addons/FBIK/icons/Manager.svg")
	)
	
	add_custom_type(
		"FBIKChain", 
		"Marker3D", 
		preload("res://addons/FBIK/scripts/IKChain.gd"), 
		preload("res://addons/FBIK/icons/Chain.svg")
	)
	
	add_custom_type(
		"FBIKLookAt", 
		"Marker3D", 
		preload("res://addons/FBIK/scripts/IKLookAt.gd"), 
		preload("res://addons/FBIK/icons/LookAt.svg")
	)
	
	add_custom_type(
		"FBIKPole", 
		"Marker3D", 
		preload("res://addons/FBIK/scripts/IKPole.gd"), 
		preload("res://addons/FBIK/icons/Pole.svg")
	)

func _exit_tree():
	# Remove custom types when plugin is disabled
	remove_custom_type("FBIKManager")
	remove_custom_type("FBIKChain")
	remove_custom_type("FBIKLookAt")
	remove_custom_type("FBIKPole")
