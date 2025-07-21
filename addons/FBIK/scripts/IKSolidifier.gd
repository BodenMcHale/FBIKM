@tool
extends Node
class_name IKSolidifier

## FBIKM - Solidifier for Godot 4.4.1
## by Nemo Czanderlitch/Nino Čandrlić
## @R3X-G1L       (godot assets store)
## R3X-G1L6AME5H  (github)
##
## Stiffens all bones that come after the specified bone in the hierarchy.
## This constraint maintains the original relative orientations and distances of bones,
## making them behave as a rigid body while still allowing the parent bone to rotate freely.
##
## Use cases:
## - Rigid weapon handles that don't bend when wielded
## - Solid armor pieces that maintain their shape
## - Mechanical parts that should move as a unit
## - Facial features that need to maintain proportions
## - Any bone chain that should act as a single rigid object
##
## The solidifier preserves the initial bone relationships established at setup time,
## preventing IK or physics from deforming the structure inappropriately.

## Node identifier for type checking
const FBIKM_NODE_ID: int = 7

## Configuration
var bone_id: String = "-1"  ## The root bone - it and all its children will be solidified

## Editor dropdown boilerplate
var _bone_names: String = "VOID:-1"

#region Property System for Editor Integration
## Custom property getter for editor dropdowns
func _get(property: StringName):
	match property:
		&"bone_id":
			return bone_id
		_:
			return null

## Custom property setter for editor dropdowns
func _set(property: StringName, value) -> bool:
	match property:
		&"bone_id":
			bone_id = str(value)
			return true
		_:
			return false

## Define custom properties for the editor inspector
func _get_property_list() -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	
	result.push_back({
		"name": "bone_id",
		"type": TYPE_INT,
		"usage": PROPERTY_USAGE_DEFAULT,
		"hint": PROPERTY_HINT_ENUM,
		"hint_string": _bone_names
	})
	
	return result
#endregion

#region Initialization and Editor Integration
func _ready() -> void:
	if Engine.is_editor_hint():  # Updated method name
		var parent_node: Node = get_parent()
		if parent_node != null and parent_node.get("FBIKM_NODE_ID") == 0:  # KinematicsManager's ID
			# Connect to parent's bone name updates for dropdown menus
			if parent_node.has_signal("bone_names_obtained"):
				if not parent_node.bone_names_obtained.is_connected(_update_parameters):
					parent_node.bone_names_obtained.connect(_update_parameters)

## Update the dropdown menu when bone structure changes
func _update_parameters(bone_names: String) -> void:
	_bone_names = bone_names
	notify_property_list_changed()  # Updated method name
#endregion

#region Validation and Helper Methods
## Validate that the solidifier configuration is correct
func is_valid() -> bool:
	if bone_id == "-1":
		return false
	
	var parent_node: Node = get_parent()
	if parent_node == null or parent_node.get("FBIKM_NODE_ID") != 0:
		return false
	
	# Check if bone exists in the skeleton
	if parent_node.virt_skel == null:
		return false
	
	if not parent_node.virt_skel.has_bone(bone_id):
		return false
	
	# Check if bone has children (solidifier needs children to be meaningful)
	var children: Array = parent_node.virt_skel.get_bone_children(bone_id)
	return not children.is_empty()

## Get all bones that will be affected by this solidifier
func get_affected_bones() -> PackedStringArray:
	var bones: PackedStringArray = []
	
	if not is_valid():
		return bones
	
	var parent_node: Node = get_parent()
	
	# Start with the root bone's children and recurse down
	var bone_queue: PackedStringArray = PackedStringArray(parent_node.virt_skel.get_bone_children(bone_id))
	var processed: Dictionary = {}
	
	while not bone_queue.is_empty():
		var current_bone: String = bone_queue[0]
		bone_queue.remove_at(0)
		
		if processed.has(current_bone):
			continue
		
		processed[current_bone] = true
		bones.append(current_bone)
		
		# Add children to queue for recursive processing
		var children: Array = parent_node.virt_skel.get_bone_children(current_bone)
		for child in children:
			if not processed.has(child):
				bone_queue.append(child)
	
	return bones

## Get the number of bones being solidified
func get_affected_bone_count() -> int:
	return get_affected_bones().size()

## Check if a specific bone is affected by this solidifier
func is_bone_affected(target_bone_id: String) -> bool:
	return target_bone_id in get_affected_bones()

## Set bone by name instead of ID
func set_bone_by_name(bone_name: String) -> bool:
	var parent_node: Node = get_parent()
	if parent_node == null or parent_node.skel == null:
		return false
	
	# Find bone ID by name
	for i in range(parent_node.skel.get_bone_count()):
		if parent_node.skel.get_bone_name(i) == bone_name:
			bone_id = str(i)
			notify_property_list_changed()
			return true
	
	return false

## Get the bone name if bone_id is valid
func get_bone_name() -> String:
	var parent_node: Node = get_parent()
	if parent_node == null or parent_node.skel == null:
		return ""
	
	if bone_id == "-1":
		return ""
	
	var bone_index: int = int(bone_id)
	if bone_index >= 0 and bone_index < parent_node.skel.get_bone_count():
		return parent_node.skel.get_bone_name(bone_index)
	
	return ""

## Calculate the maximum depth of the solidified hierarchy
func get_hierarchy_depth() -> int:
	if not is_valid():
		return 0
	
	var parent_node: Node = get_parent()
	var max_depth: int = 0
	
	for affected_bone in get_affected_bones():
		var depth: int = _calculate_bone_depth(affected_bone, bone_id)
		max_depth = max(max_depth, depth)
	
	return max_depth

## Calculate depth of a bone relative to the root bone
func _calculate_bone_depth(target_bone: String, root_bone: String) -> int:
	var parent_node: Node = get_parent()
	var depth: int = 0
	var current_bone: String = target_bone
	var max_iterations: int = 100
	
	while current_bone != root_bone and current_bone != "-1" and max_iterations > 0:
		current_bone = parent_node.virt_skel.get_bone_parent(current_bone)
		depth += 1
		max_iterations -= 1
	
	return depth if current_bone == root_bone else -1
#endregion

#region Debug and Visualization
## Get debug information about the solidifier
func get_debug_info() -> Dictionary:
	var info: Dictionary = {}
	info["bone_id"] = bone_id
	info["is_valid"] = is_valid()
	info["affected_bone_count"] = get_affected_bone_count()
	info["hierarchy_depth"] = get_hierarchy_depth()
	
	# Affected bones
	info["affected_bones"] = get_affected_bones()
	
	# Bone name for reference
	info["bone_name"] = get_bone_name()
	
	return info

## Print debug information to console
func print_debug_info() -> void:
	var info: Dictionary = get_debug_info()
	print("=== IK Solidifier Debug Info ===")
	for key in info.keys():
		if key == "affected_bones":
			print("  affected_bones: [", info[key].size(), " bones]")
			for bone in info[key]:
				print("    ", bone)
		else:
			print("  ", key, ": ", info[key])
	print("================================")

## Get visualization data for editor gizmos
func get_visualization_data() -> Dictionary:
	var data: Dictionary = {}
	
	if not is_valid():
		return data
	
	var parent_node: Node = get_parent()
	
	# Root bone information
	data["root_bone_position"] = parent_node.virt_skel.get_bone_position(bone_id)
	data["root_bone_rotation"] = parent_node.virt_skel.get_bone_rotation(bone_id)
	
	# Affected bone positions and connections
	data["affected_positions"] = []
	data["bone_connections"] = []
	
	var affected_bones: PackedStringArray = get_affected_bones()
	for affected_bone in affected_bones:
		var pos: Vector3 = parent_node.virt_skel.get_bone_position(affected_bone)
		data["affected_positions"].append(pos)
		
		# Add connection to parent
		var parent_bone: String = parent_node.virt_skel.get_bone_parent(affected_bone)
		if parent_bone == bone_id or parent_bone in affected_bones:
			var parent_index: int = affected_bones.find(parent_bone)
			var current_index: int = affected_bones.find(affected_bone)
			if parent_index != -1 and current_index != -1:
				data["bone_connections"].append([parent_index, current_index])
			elif parent_bone == bone_id:
				# Connection from root to child
				data["bone_connections"].append([-1, current_index])  # -1 represents root
	
	# Hierarchy depth visualization
	data["bone_depths"] = []
	for affected_bone in affected_bones:
		data["bone_depths"].append(_calculate_bone_depth(affected_bone, bone_id))
	
	return data

## Validate solidifier effectiveness
func validate_solidifier_setup() -> Dictionary:
	var validation: Dictionary = {}
	validation["is_effective"] = true
	validation["warnings"] = []
	validation["suggestions"] = []
	
	if not is_valid():
		validation["is_effective"] = false
		validation["warnings"].append("Invalid solidifier configuration")
		return validation
	
	# Check if there are bones to solidify
	var affected_count: int = get_affected_bone_count()
	if affected_count == 0:
		validation["warnings"].append("No child bones to solidify")
		validation["suggestions"].append("Solidifier needs child bones to be effective")
	elif affected_count > 50:
		validation["warnings"].append("Very high bone count may impact performance")
		validation["suggestions"].append("Consider breaking into multiple smaller solidifiers")
	
	# Check hierarchy depth
	var hierarchy_depth: int = get_hierarchy_depth()
	if hierarchy_depth > 10:
		validation["warnings"].append("Very deep hierarchy detected")
		validation["suggestions"].append("Deep hierarchies may impact performance")
	
	if validation["warnings"].is_empty():
		validation["suggestions"].append("Solidifier setup looks good!")
	
	return validation

## Get performance metrics
func get_performance_metrics() -> Dictionary:
	var metrics: Dictionary = {}
	metrics["affected_bone_count"] = get_affected_bone_count()
	metrics["hierarchy_depth"] = get_hierarchy_depth()
	
	# Estimate performance impact
	var bone_count: int = get_affected_bone_count()
	var impact: String = "Low"
	
	if bone_count > 50:
		impact = "High"
	elif bone_count > 20:
		impact = "Medium"
	
	metrics["estimated_performance_impact"] = impact
	
	return metrics
#endregion
