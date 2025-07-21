@tool
extends Marker3D  # Updated from Position3D
class_name IKChain

## FBIKM - Chain for Godot 4.4.1
## by Nemo Czanderlitch/Nino Čandrlić
## @R3X-G1L       (godot assets store)
## R3X-G1L6AME5H  (github)
##
## This node HAS to be a child of a FBIKM node to work. This node itself is the target.
##
## Name "Chain" comes from the fact that it solves for a set of connected bones; they solve a part of a skeleton;
## you can imagine your arm as a chain of two bones: elbow, and forearm. It begins its solving process from the tip
## bone, and continues up the tree structure until it reaches the user specified root bone, or a bone without a parent.
##
## Because FBIKM allows for multi chain solving, each chain has its individual target, and the pull force. When two
## chains pull at one another, priority is decided by this value.

## Node identifier for type checking
const FBIKM_NODE_ID: int = 1

## Chain configuration properties
var tip_bone_id: String = "-1"  ## The end bone of the chain (furthest from root)
var root_bone_id: String = "-1"  ## The starting bone of the chain (closest to skeleton root)
@export_range(0.005, 1.0) var pull_strength: float = 1.0  ## Strength of the IK pull force

## Editor dropdown boilerplate
var _bone_names: String = "VOID:-1"

#region Property System for Editor Integration
## Custom property getter for editor dropdowns
func _get(property: StringName):
	match property:
		&"tip_bone_id":
			return tip_bone_id
		&"root_bone_id":
			return root_bone_id
		_:
			return null

## Custom property setter for editor dropdowns
func _set(property: StringName, value) -> bool:
	match property:
		&"tip_bone_id":
			tip_bone_id = str(value)
			return true
		&"root_bone_id":
			root_bone_id = str(value)
			return true
		_:
			return false

## Define custom properties for the editor inspector
func _get_property_list() -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	
	# Tip bone selection dropdown
	result.push_back({
		"name": "tip_bone_id",
		"type": TYPE_INT,
		"usage": PROPERTY_USAGE_DEFAULT,
		"hint": PROPERTY_HINT_ENUM,
		"hint_string": _bone_names
	})
	
	# Root bone selection dropdown
	result.push_back({
		"name": "root_bone_id",
		"type": TYPE_INT,
		"usage": PROPERTY_USAGE_DEFAULT,
		"hint": PROPERTY_HINT_ENUM,
		"hint_string": _bone_names
	})
	
	return result
#endregion

#region Initialization
func _ready() -> void:
	if Engine.is_editor_hint():  # Updated method name
		var parent_node: Node = get_parent()
		if parent_node != null and parent_node.get("FBIKM_NODE_ID") == 0:  # KinematicsManager's ID
			# Connect to parent's bone name updates for dropdown menus
			if parent_node.has_signal("bone_names_obtained"):
				if not parent_node.bone_names_obtained.is_connected(_update_parameters):
					parent_node.bone_names_obtained.connect(_update_parameters)
#endregion

#region Editor Integration
## Update the dropdown menu when bone structure changes
func _update_parameters(bone_names: String) -> void:
	_bone_names = bone_names
	notify_property_list_changed()  # Updated method name

## Return current transform for the IK solver
func get_target() -> Transform3D:  # Updated return type
	return transform
#endregion

#region Validation and Helper Methods
## Validate that the chain configuration is correct
func is_valid() -> bool:
	if tip_bone_id == "-1" or root_bone_id == "-1":
		return false
	
	var parent_node: Node = get_parent()
	if parent_node == null or parent_node.get("FBIKM_NODE_ID") != 0:
		return false
	
	# Check if bones exist in the skeleton
	if parent_node.virt_skel == null:
		return false
	
	if not parent_node.virt_skel.has_bone(tip_bone_id):
		return false
	
	if not parent_node.virt_skel.has_bone(root_bone_id):
		return false
	
	# Validate that root is actually an ancestor of tip
	var current_bone: String = tip_bone_id
	var max_iterations: int = 100  # Prevent infinite loops
	
	while current_bone != "-1" and max_iterations > 0:
		if current_bone == root_bone_id:
			return true
		current_bone = parent_node.virt_skel.get_bone_parent(current_bone)
		max_iterations -= 1
	
	return false

## Get the length of the chain (number of bones)
func get_chain_length() -> int:
	var parent_node: Node = get_parent()
	if parent_node == null or parent_node.virt_skel == null:
		return 0
	
	if not is_valid():
		return 0
	
	var length: int = 0
	var current_bone: String = tip_bone_id
	var max_iterations: int = 100
	
	while current_bone != "-1" and current_bone != root_bone_id and max_iterations > 0:
		length += 1
		current_bone = parent_node.virt_skel.get_bone_parent(current_bone)
		max_iterations -= 1
	
	if current_bone == root_bone_id:
		length += 1
	
	return length

## Get all bones in the chain from tip to root
func get_chain_bones() -> PackedStringArray:
	var bones: PackedStringArray = []
	var parent_node: Node = get_parent()
	
	if parent_node == null or parent_node.virt_skel == null:
		return bones
	
	if not is_valid():
		return bones
	
	var current_bone: String = tip_bone_id
	var max_iterations: int = 100
	
	while current_bone != "-1" and max_iterations > 0:
		bones.append(current_bone)
		if current_bone == root_bone_id:
			break
		current_bone = parent_node.virt_skel.get_bone_parent(current_bone)
		max_iterations -= 1
	
	return bones
#endregion

#region Debug and Visualization
## Get debug information about the chain
func get_debug_info() -> Dictionary:
	var info: Dictionary = {}
	info["tip_bone_id"] = tip_bone_id
	info["root_bone_id"] = root_bone_id
	info["pull_strength"] = pull_strength
	info["is_valid"] = is_valid()
	info["chain_length"] = get_chain_length()
	info["target_position"] = global_position
	info["target_rotation"] = global_rotation
	
	var parent_node: Node = get_parent()
	if parent_node != null and parent_node.virt_skel != null:
		if parent_node.virt_skel.has_bone(tip_bone_id):
			info["tip_bone_name"] = parent_node.skel.get_bone_name(int(tip_bone_id)) if parent_node.skel != null else "Unknown"
		if parent_node.virt_skel.has_bone(root_bone_id):
			info["root_bone_name"] = parent_node.skel.get_bone_name(int(root_bone_id)) if parent_node.skel != null else "Unknown"
	
	return info

## Print debug information to console
func print_debug_info() -> void:
	var info: Dictionary = get_debug_info()
	print("=== IK Chain Debug Info ===")
	for key in info.keys():
		print("  ", key, ": ", info[key])
	print("===========================")
#endregion
