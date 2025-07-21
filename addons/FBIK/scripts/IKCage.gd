@tool
extends Node
class_name IKCage

## FBIKM - Cage Bind for Godot 4.4.1
## by Nemo Czanderlitch/Nino Čandrlić
## @R3X-G1L       (godot assets store)
## R3X-G1L6AME5H  (github)
##
## Complex constraint system for cage-like structures such as rib cages, spinal columns, or any
## structure where multiple bones need to maintain specific distance relationships while allowing
## controlled deformation. This is more complex than a simple triangular bind as it handles
## a 4-bone system with backbone and target bone relationships.
##
## Structure:
##   Backbone_1 ---- Target_Bone_1
##       |                |
##       |                |
##   Backbone_2 ---- Target_Bone_2
##
## The cage maintains all distance relationships while allowing the structure to bend and twist
## naturally. Correction bones help maintain connection to the rest of the skeleton.

## Node identifier for type checking
const FBIKM_NODE_ID: int = 9

## Cage bone configuration
var backbone_1: String = "-1"  ## Primary backbone bone (usually upper)
var backbone_2: String = "-1"  ## Secondary backbone bone (usually lower)
var backbone_2_correction: String = "-1"  ## Keeps backbone_2 connected to skeleton
var target_bone_1: String = "-1"  ## First target bone (e.g., left rib)
var target_bone_1_correction: String = "-1"  ## Keeps target_bone_1 connected
var target_bone_2: String = "-1"  ## Second target bone (e.g., right rib)
var target_bone_2_correction: String = "-1"  ## Keeps target_bone_2 connected

## Bind identifier (assigned during evaluation)
var bind_id: int = -1

## Distance constraints - calculated during setup
var b1b2_length: float = 0.0  ## Distance backbone_1 to backbone_2
var b1t1_length: float = 0.0  ## Distance backbone_1 to target_bone_1
var b1t2_length: float = 0.0  ## Distance backbone_1 to target_bone_2
var b2t1_length: float = 0.0  ## Distance backbone_2 to target_bone_1
var b2t2_length: float = 0.0  ## Distance backbone_2 to target_bone_2
var t1t2_length: float = 0.0  ## Distance target_bone_1 to target_bone_2

## Correction bone distances
var b2_correction_length: float = 0.0  ## Backbone_2 to its correction bone
var t1_correction_length: float = 0.0  ## Target_bone_1 to its correction bone
var t2_correction_length: float = 0.0  ## Target_bone_2 to its correction bone

## Editor dropdown boilerplate
var _bone_names: String = "VOID:-1"

#region Property System for Editor Integration
## Custom property getter for editor dropdowns
func _get(property: StringName):
	match property:
		&"backbone_1":
			return backbone_1
		&"backbone_2":
			return backbone_2
		&"target_bone_1":
			return target_bone_1
		&"target_bone_2":
			return target_bone_2
		&"backbone_2_correction":
			return backbone_2_correction
		&"target_bone_1_correction":
			return target_bone_1_correction
		&"target_bone_2_correction":
			return target_bone_2_correction
		_:
			return null

## Custom property setter for editor dropdowns
func _set(property: StringName, value) -> bool:
	match property:
		&"backbone_1":
			backbone_1 = str(value)
			return true
		&"backbone_2":
			backbone_2 = str(value)
			return true
		&"target_bone_1":
			target_bone_1 = str(value)
			return true
		&"target_bone_2":
			target_bone_2 = str(value)
			return true
		&"backbone_2_correction":
			backbone_2_correction = str(value)
			return true
		&"target_bone_1_correction":
			target_bone_1_correction = str(value)
			return true
		&"target_bone_2_correction":
			target_bone_2_correction = str(value)
			return true
		_:
			return false

## Define custom properties for the editor inspector
func _get_property_list() -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	
	# Backbone bones
	result.push_back({
		"name": "backbone_1",
		"type": TYPE_INT,
		"usage": PROPERTY_USAGE_DEFAULT,
		"hint": PROPERTY_HINT_ENUM,
		"hint_string": _bone_names
	})
	
	result.push_back({
		"name": "backbone_2",
		"type": TYPE_INT,
		"usage": PROPERTY_USAGE_DEFAULT,
		"hint": PROPERTY_HINT_ENUM,
		"hint_string": _bone_names
	})
	
	result.push_back({
		"name": "backbone_2_correction",
		"type": TYPE_INT,
		"usage": PROPERTY_USAGE_DEFAULT,
		"hint": PROPERTY_HINT_ENUM,
		"hint_string": _bone_names
	})
	
	# Target bones
	result.push_back({
		"name": "target_bone_1",
		"type": TYPE_INT,
		"usage": PROPERTY_USAGE_DEFAULT,
		"hint": PROPERTY_HINT_ENUM,
		"hint_string": _bone_names
	})
	
	result.push_back({
		"name": "target_bone_1_correction",
		"type": TYPE_INT,
		"usage": PROPERTY_USAGE_DEFAULT,
		"hint": PROPERTY_HINT_ENUM,
		"hint_string": _bone_names
	})
	
	result.push_back({
		"name": "target_bone_2",
		"type": TYPE_INT,
		"usage": PROPERTY_USAGE_DEFAULT,
		"hint": PROPERTY_HINT_ENUM,
		"hint_string": _bone_names
	})
	
	result.push_back({
		"name": "target_bone_2_correction",
		"type": TYPE_INT,
		"usage": PROPERTY_USAGE_DEFAULT,
		"hint": PROPERTY_HINT_ENUM,
		"hint_string": _bone_names
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
## Validate that the cage configuration is correct
func is_valid() -> bool:
	# Check that all main bones are defined
	if (backbone_1 == "-1" or backbone_2 == "-1" or 
		target_bone_1 == "-1" or target_bone_2 == "-1"):
		return false
	
	var parent_node: Node = get_parent()
	if parent_node == null or parent_node.get("FBIKM_NODE_ID") != 0:
		return false
	
	# Check if all bones exist in the skeleton
	if parent_node.virt_skel == null:
		return false
	
	return (parent_node.virt_skel.has_bone(backbone_1) and 
			parent_node.virt_skel.has_bone(backbone_2) and 
			parent_node.virt_skel.has_bone(target_bone_1) and 
			parent_node.virt_skel.has_bone(target_bone_2))

## Check if correction bones are properly configured
func has_valid_corrections() -> bool:
	if not is_valid():
		return false
	
	var parent_node: Node = get_parent()
	var corrections_valid: bool = true
	
	# Check backbone_2 correction
	if backbone_2_correction != "-1":
		corrections_valid = corrections_valid and parent_node.virt_skel.has_bone(backbone_2_correction)
	
	# Check target_bone_1 correction
	if target_bone_1_correction != "-1":
		corrections_valid = corrections_valid and parent_node.virt_skel.has_bone(target_bone_1_correction)
	
	# Check target_bone_2 correction
	if target_bone_2_correction != "-1":
		corrections_valid = corrections_valid and parent_node.virt_skel.has_bone(target_bone_2_correction)
	
	return corrections_valid

## Calculate the volume of the cage (for debugging/validation)
func get_cage_volume() -> float:
	if not is_valid():
		return 0.0
	
	var parent_node: Node = get_parent()
	var pos_b1: Vector3 = parent_node.virt_skel.get_bone_position(backbone_1)
	var pos_b2: Vector3 = parent_node.virt_skel.get_bone_position(backbone_2)
	var pos_t1: Vector3 = parent_node.virt_skel.get_bone_position(target_bone_1)
	var pos_t2: Vector3 = parent_node.virt_skel.get_bone_position(target_bone_2)
	
	# Calculate volume of tetrahedron formed by the four points
	var v1: Vector3 = pos_b2 - pos_b1
	var v2: Vector3 = pos_t1 - pos_b1
	var v3: Vector3 = pos_t2 - pos_b1
	
	return abs(v1.dot(v2.cross(v3))) / 6.0

## Check if the cage is degenerate (all points coplanar)
func is_degenerate() -> bool:
	return get_cage_volume() < 0.001

## Get all cage bone IDs as an array
func get_cage_bones() -> PackedStringArray:
	var bones: PackedStringArray = []
	if backbone_1 != "-1":
		bones.append(backbone_1)
	if backbone_2 != "-1":
		bones.append(backbone_2)
	if target_bone_1 != "-1":
		bones.append(target_bone_1)
	if target_bone_2 != "-1":
		bones.append(target_bone_2)
	return bones

## Get all correction bone IDs as an array
func get_correction_bones() -> PackedStringArray:
	var bones: PackedStringArray = []
	if backbone_2_correction != "-1":
		bones.append(backbone_2_correction)
	if target_bone_1_correction != "-1":
		bones.append(target_bone_1_correction)
	if target_bone_2_correction != "-1":
		bones.append(target_bone_2_correction)
	return bones

## Calculate the center point of the cage
func get_cage_center() -> Vector3:
	if not is_valid():
		return Vector3.ZERO
	
	var parent_node: Node = get_parent()
	var center: Vector3 = Vector3.ZERO
	var count: int = 0
	
	for bone_id in get_cage_bones():
		center += parent_node.virt_skel.get_bone_position(bone_id)
		count += 1
	
	return center / float(count) if count > 0 else Vector3.ZERO

## Get the bounding box of the cage
func get_cage_bounds() -> AABB:
	if not is_valid():
		return AABB()
	
	var parent_node: Node = get_parent()
	var bones: PackedStringArray = get_cage_bones()
	
	if bones.is_empty():
		return AABB()
	
	var first_pos: Vector3 = parent_node.virt_skel.get_bone_position(bones[0])
	var bounds: AABB = AABB(first_pos, Vector3.ZERO)
	
	for i in range(1, bones.size()):
		var pos: Vector3 = parent_node.virt_skel.get_bone_position(bones[i])
		bounds = bounds.expand(pos)
	
	return bounds
#endregion

#region Debug and Visualization
## Get debug information about the cage constraint
func get_debug_info() -> Dictionary:
	var info: Dictionary = {}
	info["backbone_1"] = backbone_1
	info["backbone_2"] = backbone_2
	info["backbone_2_correction"] = backbone_2_correction
	info["target_bone_1"] = target_bone_1
	info["target_bone_1_correction"] = target_bone_1_correction
	info["target_bone_2"] = target_bone_2
	info["target_bone_2_correction"] = target_bone_2_correction
	info["bind_id"] = bind_id
	info["is_valid"] = is_valid()
	info["has_valid_corrections"] = has_valid_corrections()
	info["is_degenerate"] = is_degenerate()
	info["cage_volume"] = get_cage_volume()
	info["cage_center"] = get_cage_center()
	info["cage_bounds"] = get_cage_bounds()
	
	# Distance information
	info["b1b2_length"] = b1b2_length
	info["b1t1_length"] = b1t1_length
	info["b1t2_length"] = b1t2_length
	info["b2t1_length"] = b2t1_length
	info["b2t2_length"] = b2t2_length
	info["t1t2_length"] = t1t2_length
	info["b2_correction_length"] = b2_correction_length
	info["t1_correction_length"] = t1_correction_length
	info["t2_correction_length"] = t2_correction_length
	
	# Bone names for reference
	var parent_node: Node = get_parent()
	if parent_node != null and parent_node.skel != null:
		var skel: Skeleton3D = parent_node.skel
		if backbone_1 != "-1" and int(backbone_1) < skel.get_bone_count():
			info["backbone_1_name"] = skel.get_bone_name(int(backbone_1))
		if backbone_2 != "-1" and int(backbone_2) < skel.get_bone_count():
			info["backbone_2_name"] = skel.get_bone_name(int(backbone_2))
		if target_bone_1 != "-1" and int(target_bone_1) < skel.get_bone_count():
			info["target_bone_1_name"] = skel.get_bone_name(int(target_bone_1))
		if target_bone_2 != "-1" and int(target_bone_2) < skel.get_bone_count():
			info["target_bone_2_name"] = skel.get_bone_name(int(target_bone_2))
	
	return info

## Print debug information to console
func print_debug_info() -> void:
	var info: Dictionary = get_debug_info()
	print("=== IK Cage Debug Info ===")
	for key in info.keys():
		print("  ", key, ": ", info[key])
	print("==========================")

## Get cage geometry for visualization
func get_cage_geometry() -> Dictionary:
	var geometry: Dictionary = {}
	
	if not is_valid():
		return geometry
	
	var parent_node: Node = get_parent()
	
	# Get all bone positions
	geometry["backbone_1_pos"] = parent_node.virt_skel.get_bone_position(backbone_1)
	geometry["backbone_2_pos"] = parent_node.virt_skel.get_bone_position(backbone_2)
	geometry["target_bone_1_pos"] = parent_node.virt_skel.get_bone_position(target_bone_1)
	geometry["target_bone_2_pos"] = parent_node.virt_skel.get_bone_position(target_bone_2)
	
	# Define cage edges for wireframe display
	geometry["edges"] = [
		[backbone_1, backbone_2],  # Backbone connection
		[backbone_1, target_bone_1],  # B1 to T1
		[backbone_1, target_bone_2],  # B1 to T2
		[backbone_2, target_bone_1],  # B2 to T1
		[backbone_2, target_bone_2],  # B2 to T2
		[target_bone_1, target_bone_2]  # Target connection
	]
	
	# Define triangular faces for solid display
	geometry["faces"] = [
		[backbone_1, backbone_2, target_bone_1],
		[backbone_1, backbone_2, target_bone_2],
		[backbone_1, target_bone_1, target_bone_2],
		[backbone_2, target_bone_1, target_bone_2]
	]
	
	return geometry

## Validate cage distance constraints
func validate_constraints() -> Dictionary:
	var validation: Dictionary = {}
	
	if not is_valid():
		validation["error"] = "Cage configuration is invalid"
		return validation
	
	var parent_node: Node = get_parent()
	validation["distances_match"] = true
	validation["constraint_errors"] = []
	
	# Check if current distances match expected distances
	var current_b1b2: float = (parent_node.virt_skel.get_bone_position(backbone_1) - 
							   parent_node.virt_skel.get_bone_position(backbone_2)).length()
	if abs(current_b1b2 - b1b2_length) > 0.01:
		validation["distances_match"] = false
		validation["constraint_errors"].append("B1-B2 distance mismatch: " + str(current_b1b2) + " vs " + str(b1b2_length))
	
	var current_t1t2: float = (parent_node.virt_skel.get_bone_position(target_bone_1) - 
							   parent_node.virt_skel.get_bone_position(target_bone_2)).length()
	if abs(current_t1t2 - t1t2_length) > 0.01:
		validation["distances_match"] = false
		validation["constraint_errors"].append("T1-T2 distance mismatch: " + str(current_t1t2) + " vs " + str(t1t2_length))
	
	return validation
#endregion
