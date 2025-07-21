@tool
extends Marker3D

## Simplified IK Chain for Godot 4.x

const FBIKM_NODE_ID = 1

@export var tip_bone_id: String = "-1" : set = _set_tip_bone
@export var root_bone_id: String = "-1" : set = _set_root_bone
@export var pull_strength: float = 1.0

var _bone_names: String = "NONE:-1"

func _ready():
	if Engine.is_editor_hint():
		_connect_to_parent()

func _connect_to_parent():
	var parent_node = get_parent()
	if parent_node and parent_node.has_signal("bone_names_updated"):
		if not parent_node.bone_names_updated.is_connected(_on_bone_names_updated):
			parent_node.bone_names_updated.connect(_on_bone_names_updated)

func _on_bone_names_updated(bone_names: String):
	_bone_names = bone_names
	notify_property_list_changed()

func _set_tip_bone(value: String):
	tip_bone_id = value
	
func _set_root_bone(value: String):
	root_bone_id = value

func _get_property_list():
	var properties = []
	
	properties.append({
		"name": "tip_bone_id",
		"type": TYPE_STRING,
		"usage": PROPERTY_USAGE_DEFAULT,
		"hint": PROPERTY_HINT_ENUM,
		"hint_string": _bone_names
	})
	
	properties.append({
		"name": "root_bone_id", 
		"type": TYPE_STRING,
		"usage": PROPERTY_USAGE_DEFAULT,
		"hint": PROPERTY_HINT_ENUM,
		"hint_string": _bone_names
	})
	
	return properties

## Interface methods for the FBIK manager
func get_fbik_type() -> String:
	return "chain"

func get_target_position() -> Vector3:
	return global_position

func get_tip_bone() -> String:
	return tip_bone_id
	
func get_root_bone() -> String:
	return root_bone_id

func get_pull_strength() -> float:
	return pull_strength
