@tool
extends Node
class_name IKBind

## FBIKM - Bind for Godot 4.4.1
## by Nemo Czanderlitch/Nino Čandrlić
## @R3X-G1L       (godot assets store)
## R3X-G1L6AME5H  (github)
##
## This node ties 3 bones in a triangle, where the distance between the tips of the bones always remains the same.
## Visualize a rig of the torso. You have two chains that both have the same parent node. If you were to simply apply
## a chain driver to them, the chest would be shredded because the bones of the chest are moving independently when they
## should be moving in unison; the chest is a solid entity after all.
##
##  0       0
##   \     /
##    0   0
##     \ /
##      0
##      |
##      0
##
## So you need to limit the branching bones to keep distance between themselves. You have to bind them. 
## With requirement of this distance being kept constant, there is now an imaginary third bone. 
## This then creates a bone triangle; a loop. Hence the three bone_N parameters below.
##
##    0       0
##     \ B1  /
##      0---0
##   B3 \ / B2
##        0
##        |
##        0
## B  - bones
##
## Alas, this triangle is independent from the rest of the skeleton. This means it gets detached from the rest of the
## body during runtime. Hence the bone_N_correction_bone parameters. These specify the bones neighboring the bones that
## are in the loop.
##
##    0       0
## CB3 \ B1  / CB2
##      0---0
##   B3  \ / B2
##        0
##        |  CB1
##        0
##
## CB - correction bones
## B  - bones

## Node identifier for type checking
const FBIKM_NODE_ID: int = 4

## Bind configuration
var bind_id: int = -1

## Triangle bones - form the constraint triangle
var bone_1: String = "-1"  ## First corner of the triangle
var bone_2: String = "-1"  ## Second corner of the triangle
var bone_3: String = "-1"  ## Third corner of the triangle

## Correction bones - maintain connection to rest of skeleton
var bone_1_correction_bone: String = "-1"  ## Bone that keeps bone_1 anchored
var bone_2_correction_bone: String = "-1"  ## Bone that keeps bone_2 anchored
var bone_3_correction_bone: String = "-1"  ## Bone that keeps bone_3 anchored

## Optional parameter that changes the distance of the "collar" bone
@export_range(0.05, 2.0) var length_23_multiplier: float = 1.0

## Editor control variables
@export var lock_correction_bone_2: bool = false : set = _lock_correction_2
@export var lock_correction_bone_3: bool = false : set = _lock_correction_3

## Automatically calculated lengths (set during evaluation)
var length_12: float = 0.0  ## Distance between bone_1 and bone_2
var length_23: float = 0.0  ## Distance between bone_2 and bone_3
var length_31: float = 0.0  ## Distance between bone_3 and bone_1

## Correction bone lengths
var correction_length_1: float = 0.0
var correction_length_2: float = 0.0
var correction_length_3: float = 0.0

## Editor dropdown boilerplate
var _bone_names: String = "VOID:-1"

#region Editor Lock Controls
func _lock_correction_2(value: bool) -> void:
	lock_correction_bone_2 = value
	notify_property_list_changed()  # Updated method name

func _lock_correction_3(value: bool) -> void:
	lock_correction_bone_3 = value
	notify_property_list_changed()  # Updated method name
#endregion

#region Property System for Editor Integration
## Custom property getter for editor dropdowns
func _get(property: StringName):
	match property:
		&"bone_1":
			return bone_1
		&"bone_1_correction_bone":
			return bone_1_correction_bone
		&"bone_2":
			return bone_2
		&"bone_2_correction_bone":
			return bone_2_correction_bone
		&"bone_3":
			return bone_3
		&"bone_3_correction_bone":
			return bone_3_correction_bone
		_:
			return null

## Custom property setter for editor dropdowns
func _set(property: StringName, value) -> bool:
	match property:
		&"bone_1":
			bone_1 = str(value)
			return true
		&"bone_1_correction_bone":
			bone_1_correction_bone = str(value)
			return true
		&"bone_2":
			bone_2 = str(value)
			return true
		&"bone_2_correction_bone":
			bone_2_correction_bone = str(value)
			return true
		&"bone_3":
			bone_3 = str(value)
			return true
		&"bone_3_correction_bone":
			bone_3_correction_bone = str(value)
			return true
		_:
			return false

## Define custom properties for the editor inspector
func _get_property_list() -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	
	# Main triangle bones
	result.push_back({
		"name": "bone_1",
		"type": TYPE_INT,
		"usage": PROPERTY_USAGE_DEFAULT,
		"hint": PROPERTY_HINT_ENUM,
		"hint_string": _bone_names
	})
	
	result.push_back({
		"name": "bone_1_correction_bone",
		"type": TYPE_INT,
		"usage": PROPERTY_USAGE_DEFAULT,
		"hint": PROPERTY_HINT_ENUM,
		"hint_string": _bone_names
	})
	
	result.push_back({
		"name": "bone_2",
		"type": TYPE_INT,
		"usage": PROPERTY_USAGE_DEFAULT,
		"hint": PROPERTY_HINT_ENUM,
		"hint_string": _bone_names
	})
	
	# Bone 2 correction (may be locked)
	var bone_2_correction_hint: String = _bone_names
	if lock_correction_bone_2:
		bone_2_correction_hint = "LOCKED:-1"
	
	result.push_back({
		"name": "bone_2_correction_bone",
		"type": TYPE_INT,
		"usage": PROPERTY_USAGE_DEFAULT,
		"hint": PROPERTY_HINT_ENUM,
		"hint_string": bone_2_correction_hint
	})
	
	result.push_back({
		"name": "bone_3",
		"type": TYPE_INT,
		"usage": PROPERTY_USAGE_DEFAULT,
		"hint": PROPERTY_HINT_ENUM,
		"hint_string": _bone_names
	})
	
	# Bone 3 correction (may be locked)
	var bone_3_correction_hint: String = _bone_names
	if lock_correction_bone_3:
		bone_3_correction_hint = "LOCKED:-1"
	
	result.push_back({
		"name": "bone_3_correction_bone",
		"type": TYPE_INT,
		"usage": PROPERTY_USAGE_DEFAULT,
		"hint": PROPERTY_HINT_ENUM,
		"hint_string": bone_3_correction_hint
	})
	
	return result
#endregion

#region Initialization and Editor Integration
## Update the dropdown menu when bone structure changes
func _update_parameters(bone_names: String) -> void:
	_bone_names = bone_names
	notify_property_list_changed()  # Updated method name
#endregion

#region Validation and Helper Methods
## Validate that the bind configuration is correct
func is_valid() -> bool:
	if bone_1 == "-1" or bone_2 == "-1" or bone_3 == "-1":
		return false
	
	var parent_node: Node = get_parent()
	if parent_node == null or parent_node.get("FBIKM_NODE_ID") != 0:
		return false
	
	# Check if all bones exist in the skeleton
	if parent_node.virt_skel == null:
		return false
	
	return (parent_node.virt_skel.has_bone(bone_1) and 
			parent_node.virt_skel.has_bone(bone_2) and 
			parent_node.virt_skel.has_bone(bone_3))

## Check if the triangle is degenerate (all bones in a line)
func is_degenerate_triangle() -> bool:
	if not is_valid():
		return true
	
	var parent_node: Node = get_parent()
	var pos1: Vector3 = parent_node.virt_skel.get_bone_position(bone_1)
	var pos2: Vector3 = parent_node.virt_skel.get_bone_position(bone_2)
	var pos3: Vector3 = parent_node.virt_skel.get_bone_position(bone_3)
	
	# Calculate triangle area using cross product
	var v1: Vector3 = pos2 - pos1
	var v2: Vector3 = pos3 - pos1
	var area: float = v1.cross(v2).length() * 0.5
	
	# If area is very small, triangle is degenerate
	return area < 0.001

## Get the triangle's perimeter
func get_perimeter() -> float:
	return length_12 + length_23 + length_31

## Get the triangle's area using Heron's formula
func get_area() -> float:
	var s: float = get_perimeter() * 0.5  # Semi-perimeter
	var area_squared: float = s * (s - length_12) * (s - length_23) * (s - length_31)
	return sqrt(max(area_squared, 0.0))

## Check if the triangle satisfies the triangle inequality
func satisfies_triangle_inequality() -> bool:
	return (length_12 + length_23 > length_31 and
			length_23 + length_31 > length_12 and
			length_31 + length_12 > length_23)
#endregion

#region Debug and Visualization
## Get debug information about the bind constraint
func get_debug_info() -> Dictionary:
	var info: Dictionary = {}
	info["bone_1"] = bone_1
	info["bone_2"] = bone_2
	info["bone_3"] = bone_3
	info["bone_1_correction"] = bone_1_correction_bone
	info["bone_2_correction"] = bone_2_correction_bone
	info["bone_3_correction"] = bone_3_correction_bone
	info["bind_id"] = bind_id
	info["is_valid"] = is_valid()
	info["is_degenerate"] = is_degenerate_triangle()
	info["satisfies_triangle_inequality"] = satisfies_triangle_inequality()
	info["length_12"] = length_12
	info["length_23"] = length_23
	info["length_31"] = length_31
	info["perimeter"] = get_perimeter()
	info["area"] = get_area()
	info["length_23_multiplier"] = length_23_multiplier
	
	var parent_node: Node = get_parent()
	if parent_node != null and parent_node.skel != null:
		if bone_1 != "-1" and int(bone_1) < parent_node.skel.get_bone_count():
			info["bone_1_name"] = parent_node.skel.get_bone_name(int(bone_1))
		if bone_2 != "-1" and int(bone_2) < parent_node.skel.get_bone_count():
			info["bone_2_name"] = parent_node.skel.get_bone_name(int(bone_2))
		if bone_3 != "-1" and int(bone_3) < parent_node.skel.get_bone_count():
			info["bone_3_name"] = parent_node.skel.get_bone_name(int(bone_3))
	
	return info

## Print debug information to console
func print_debug_info() -> void:
	var info: Dictionary = get_debug_info()
	print("=== IK Bind Debug Info ===")
	for key in info.keys():
		print("  ", key, ": ", info[key])
	print("==========================")

## Get visual representation of the triangle for debugging
func get_triangle_points() -> PackedVector3Array:
	var points: PackedVector3Array = []
	
	if not is_valid():
		return points
	
	var parent_node: Node = get_parent()
	points.append(parent_node.virt_skel.get_bone_position(bone_1))
	points.append(parent_node.virt_skel.get_bone_position(bone_2))
	points.append(parent_node.virt_skel.get_bone_position(bone_3))
	
	return points
#endregion
