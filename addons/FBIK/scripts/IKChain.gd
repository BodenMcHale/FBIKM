@tool
extends Marker3D

"""
	FBIKM - Chain
   		by Nemo Czanderlitch/Nino Čandrlić
			@R3X-G1L       (godot assets store)
			R3X-G1L6AME5H  (github)

	This node HAS to be a child of a FBIKM node to work. This node itself is the target.

	Name "Chain" comes from the fact that it solves for a set of connected bones; they solve a part of a skeleton;
	you can imagine your arm as a chain of two bones: elbow, and forearm. It begins its solving process from the tip
	bone, and continues up the tree structure until it reaches the user specified root bone, or a bone without a parent.

	Because FBIKM allows for multi chain solving, each chain has its individual target, and the pull force. When two
	chains pull at one another, priority is decided by by this value.
"""


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
