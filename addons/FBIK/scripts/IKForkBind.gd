@tool
extends Node
class_name IKForkBind

## FBIKM - Fork Bind for Godot 4.4.1
## by Nemo Czanderlitch/Nino Čandrlić
## @R3X-G1L       (godot assets store)
## R3X-G1L6AME5H  (github)
##
## Creates a fork constraint where multiple bones (bone_1, bone_2, bone_3) maintain fixed
## distances to a target bone. This is useful for structures like shoulder blades connecting
## to the spine, or multiple ribs connecting to a central vertebra.
##
## Structure:
##     Bone_2
##       |
##       |
## Bone_1 ---- Target ---- Bone_3
##
## All three bones maintain their original distances to the target bone, creating a stable
## fork-like structure that can bend and rotate while preserving the original relationships.
##
## The reverse_fork option changes the solving direction:
## - Normal: Bones pull the target toward themselves
## - Reverse: Target pulls the bones toward itself

## Node identifier for type checking
const FBIKM_NODE_ID: int = 5

## Fork bone configuration
var bone_1: String = "-1"    ## First fork bone (e.g., left shoulder blade)
var bone_2: String = "-1"    ## Second fork bone (e.g., right shoulder blade) 
var bone_3: String = "-1"    ## Third fork bone (e.g., upper spine connection)
var bone_target: String = "-1"  ## Target bone that all others connect to (e.g., central spine)

## Constraint behavior
@export var reverse_fork: bool = false  ## If true, target pulls bones; if false, bones pull target

## Bind identifier (assigned during evaluation)
var bind_id: int = -1

## Distance constraints (calculated during setup)
var length_1: float = 0.0  ## Distance from bone_1 to target
var length_2: float = 0.0  ## Distance from bone_2 to target
var length_3: float = 0.0  ## Distance from bone_3 to target

## Editor dropdown boilerplate
var _bone_names: String = "VOID:-1"

#region Property System for Editor Integration
## Custom property getter for editor dropdowns
func _get(property: StringName):
	match property:
		&"bone_1":
			return bone_1
		&"bone_2":
			return bone_2
		&"bone_3":
			return bone_3
		&"bone_target":
			return bone_target
		_:
			return null

## Custom property setter for editor dropdowns
func _set(property: StringName, value) -> bool:
	match property:
		&"bone_1":
			bone_1 = str(value)
			return true
		&"bone_2":
			bone_2 = str(value)
			return true
		&"bone_3":
			bone_3 = str(value)
			return true
		&"bone_target":
			bone_target = str(value)
			return true
		_:
			return false

## Define custom properties for the editor inspector
func _get_property_list() -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	
	# Fork bones
	result.push_back({
		"name": "bone_1",
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
	
	result.push_back({
		"name": "bone_3",
		"type": TYPE_INT,
		"usage": PROPERTY_USAGE_DEFAULT,
		"hint": PROPERTY_HINT_ENUM,
		"hint_string": _bone_names
	})
	
	# Target bone
	result.push_back({
		"name": "bone_target",
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
## Validate that the fork bind configuration is correct
func is_valid() -> bool:
	# Check that all bones are defined
	if (bone_1 == "-1" or bone_2 == "-1" or 
		bone_3 == "-1" or bone_target == "-1"):
		return false
	
	var parent_node: Node = get_parent()
	if parent_node == null or parent_node.get("FBIKM_NODE_ID") != 0:
		return false
	
	# Check if all bones exist in the skeleton
	if parent_node.virt_skel == null:
		return false
	
	return (parent_node.virt_skel.has_bone(bone_1) and 
			parent_node.virt_skel.has_bone(bone_2) and 
			parent_node.virt_skel.has_bone(bone_3) and 
			parent_node.virt_skel.has_bone(bone_target))

## Check if the fork configuration forms a valid 3D structure
func is_valid_3d_structure() -> bool:
	if not is_valid():
		return false
	
	var parent_node: Node = get_parent()
	var pos_1: Vector3 = parent_node.virt_skel.get_bone_position(bone_1)
	var pos_2: Vector3 = parent_node.virt_skel.get_bone_position(bone_2)
	var pos_3: Vector3 = parent_node.virt_skel.get_bone_position(bone_3)
	var pos_target: Vector3 = parent_node.virt_skel.get_bone_position(bone_target)
	
	# Check that not all bones are collinear (would create degenerate constraint)
	var v1: Vector3 = pos_1 - pos_target
	var v2: Vector3 = pos_2 - pos_target
	var v3: Vector3 = pos_3 - pos_target
	
	# Calculate cross products to check for colinearity
	var cross12: Vector3 = v1.cross(v2)
	var cross13: Vector3 = v1.cross(v3)
	var cross23: Vector3 = v2.cross(v3)
	
	# If all cross products are near zero, bones are collinear
	var min_cross_magnitude: float = 0.001
	return (cross12.length() > min_cross_magnitude or 
			cross13.length() > min_cross_magnitude or 
			cross23.length() > min_cross_magnitude)

## Check if bones form a reasonable fork structure (not too compressed or stretched)
func has_reasonable_proportions() -> bool:
	if not is_valid():
		return false
	
	# Check that distances are reasonable relative to each other
	var lengths: Array[float] = [length_1, length_2, length_3]
	lengths.sort()
	
	var min_length: float = lengths[0]
	var max_length: float = lengths[2]
	
	# Avoid extreme ratios (one bone much longer than others)
	var ratio: float = max_length / min_length if min_length > 0.001 else 1000.0
	return ratio < 10.0  # Maximum 10:1 ratio

## Get all fork bone IDs as an array
func get_fork_bones() -> PackedStringArray:
	var bones: PackedStringArray = []
	if bone_1 != "-1":
		bones.append(bone_1)
	if bone_2 != "-1":
		bones.append(bone_2)
	if bone_3 != "-1":
		bones.append(bone_3)
	return bones

## Calculate the center point of the fork (average of bone positions)
func get_fork_center() -> Vector3:
	if not is_valid():
		return Vector3.ZERO
	
	var parent_node: Node = get_parent()
	var center: Vector3 = Vector3.ZERO
	var count: int = 0
	
	for bone_id in get_fork_bones():
		center += parent_node.virt_skel.get_bone_position(bone_id)
		count += 1
	
	if bone_target != "-1":
		center += parent_node.virt_skel.get_bone_position(bone_target)
		count += 1
	
	return center / float(count) if count > 0 else Vector3.ZERO

## Calculate the volume of the tetrahedron formed by the four bones
func get_fork_volume() -> float:
	if not is_valid():
		return 0.0
	
	var parent_node: Node = get_parent()
	var pos_1: Vector3 = parent_node.virt_skel.get_bone_position(bone_1)
	var pos_2: Vector3 = parent_node.virt_skel.get_bone_position(bone_2)
	var pos_3: Vector3 = parent_node.virt_skel.get_bone_position(bone_3)
	var pos_target: Vector3 = parent_node.virt_skel.get_bone_position(bone_target)
	
	# Calculate volume using scalar triple product
	var v1: Vector3 = pos_1 - pos_target
	var v2: Vector3 = pos_2 - pos_target
	var v3: Vector3 = pos_3 - pos_target
	
	return abs(v1.dot(v2.cross(v3))) / 6.0

## Get the bounding box of all fork bones
func get_fork_bounds() -> AABB:
	if not is_valid():
		return AABB()
	
	var parent_node: Node = get_parent()
	var all_bones: PackedStringArray = get_fork_bones()
	all_bones.append(bone_target)
	
	if all_bones.is_empty():
		return AABB()
	
	var first_pos: Vector3 = parent_node.virt_skel.get_bone_position(all_bones[0])
	var bounds: AABB = AABB(first_pos, Vector3.ZERO)
	
	for i in range(1, all_bones.size()):
		var pos: Vector3 = parent_node.virt_skel.get_bone_position(all_bones[i])
		bounds = bounds.expand(pos)
	
	return bounds

## Calculate constraint forces for analysis
func get_constraint_forces() -> Dictionary:
	var forces: Dictionary = {}
	
	if not is_valid():
		return forces
	
	var parent_node: Node = get_parent()
	
	# Calculate displacement vectors from current to target distances
	var pos_1: Vector3 = parent_node.virt_skel.get_bone_position(bone_1)
	var pos_2: Vector3 = parent_node.virt_skel.get_bone_position(bone_2)
	var pos_3: Vector3 = parent_node.virt_skel.get_bone_position(bone_3)
	var pos_target: Vector3 = parent_node.virt_skel.get_bone_position(bone_target)
	
	# Current distances
	var current_dist_1: float = pos_1.distance_to(pos_target)
	var current_dist_2: float = pos_2.distance_to(pos_target)
	var current_dist_3: float = pos_3.distance_to(pos_target)
	
	# Force magnitudes (difference from target distances)
	forces["force_1_magnitude"] = abs(current_dist_1 - length_1)
	forces["force_2_magnitude"] = abs(current_dist_2 - length_2)
	forces["force_3_magnitude"] = abs(current_dist_3 - length_3)
	forces["total_force"] = forces["force_1_magnitude"] + forces["force_2_magnitude"] + forces["force_3_magnitude"]
	
	# Force directions (unit vectors pointing toward target distances)
	if current_dist_1 > 0.001:
		var dir_1: Vector3 = (pos_target - pos_1).normalized()
		forces["force_1_direction"] = dir_1 * sign(length_1 - current_dist_1)
	
	if current_dist_2 > 0.001:
		var dir_2: Vector3 = (pos_target - pos_2).normalized()
		forces["force_2_direction"] = dir_2 * sign(length_2 - current_dist_2)
	
	if current_dist_3 > 0.001:
		var dir_3: Vector3 = (pos_target - pos_3).normalized()
		forces["force_3_direction"] = dir_3 * sign(length_3 - current_dist_3)
	
	return forces
#endregion

#region Utility Methods
## Set bones by name instead of ID
func set_bones_by_name(bone_1_name: String, bone_2_name: String, bone_3_name: String, target_name: String) -> bool:
	var parent_node: Node = get_parent()
	if parent_node == null or parent_node.skel == null:
		return false
	
	var skel: Skeleton3D = parent_node.skel
	var found_bones: Dictionary = {}
	
	# Find all bone IDs by name
	for i in range(skel.get_bone_count()):
		var name: String = skel.get_bone_name(i)
		if name == bone_1_name:
			found_bones["bone_1"] = str(i)
		elif name == bone_2_name:
			found_bones["bone_2"] = str(i)
		elif name == bone_3_name:
			found_bones["bone_3"] = str(i)
		elif name == target_name:
			found_bones["bone_target"] = str(i)
	
	# Only apply if all bones were found
	if found_bones.size() == 4:
		bone_1 = found_bones["bone_1"]
		bone_2 = found_bones["bone_2"]
		bone_3 = found_bones["bone_3"]
		bone_target = found_bones["bone_target"]
		notify_property_list_changed()
		return true
	
	return false

## Get bone names for all configured bones
func get_bone_names() -> Dictionary:
	var names: Dictionary = {}
	var parent_node: Node = get_parent()
	
	if parent_node == null or parent_node.skel == null:
		return names
	
	var skel: Skeleton3D = parent_node.skel
	
	if bone_1 != "-1" and int(bone_1) < skel.get_bone_count():
		names["bone_1"] = skel.get_bone_name(int(bone_1))
	if bone_2 != "-1" and int(bone_2) < skel.get_bone_count():
		names["bone_2"] = skel.get_bone_name(int(bone_2))
	if bone_3 != "-1" and int(bone_3) < skel.get_bone_count():
		names["bone_3"] = skel.get_bone_name(int(bone_3))
	if bone_target != "-1" and int(bone_target) < skel.get_bone_count():
		names["bone_target"] = skel.get_bone_name(int(bone_target))
	
	return names

## Create a mirrored fork bind (useful for symmetric structures)
func create_mirrored_fork(name_mapping: Dictionary) -> IKForkBind:
	var mirrored_fork: IKForkBind = IKForkBind.new()
	var bone_names: Dictionary = get_bone_names()
	
	# Apply name mapping to create mirrored version
	for bone_key in bone_names.keys():
		var original_name: String = bone_names[bone_key]
		if name_mapping.has(original_name):
			var mirrored_name: String = name_mapping[original_name]
			match bone_key:
				"bone_1":
					mirrored_fork.set_bones_by_name(mirrored_name, "", "", "")
				"bone_2":
					mirrored_fork.set_bones_by_name("", mirrored_name, "", "")
				"bone_3":
					mirrored_fork.set_bones_by_name("", "", mirrored_name, "")
				"bone_target":
					mirrored_fork.set_bones_by_name("", "", "", mirrored_name)
	
	# Copy settings
	mirrored_fork.reverse_fork = reverse_fork
	
	return mirrored_fork
#endregion

#region Debug and Visualization
## Get debug information about the fork bind constraint
func get_debug_info() -> Dictionary:
	var info: Dictionary = {}
	info["bone_1"] = bone_1
	info["bone_2"] = bone_2
	info["bone_3"] = bone_3
	info["bone_target"] = bone_target
	info["reverse_fork"] = reverse_fork
	info["bind_id"] = bind_id
	info["is_valid"] = is_valid()
	info["is_valid_3d_structure"] = is_valid_3d_structure()
	info["has_reasonable_proportions"] = has_reasonable_proportions()
	
	# Distance information
	info["length_1"] = length_1
	info["length_2"] = length_2
	info["length_3"] = length_3
	
	# Geometric properties
	info["fork_center"] = get_fork_center()
	info["fork_volume"] = get_fork_volume()
	info["fork_bounds"] = get_fork_bounds()
	
	# Current constraint state
	info["constraint_forces"] = get_constraint_forces()
	
	# Bone names for reference
	info["bone_names"] = get_bone_names()
	
	return info

## Print debug information to console
func print_debug_info() -> void:
	var info: Dictionary = get_debug_info()
	print("=== IK Fork Bind Debug Info ===")
	for key in info.keys():
		if key == "constraint_forces":
			print("  constraint_forces:")
			for force_key in info[key].keys():
				print("    ", force_key, ": ", info[key][force_key])
		elif key == "bone_names":
			print("  bone_names:")
			for name_key in info[key].keys():
				print("    ", name_key, ": ", info[key][name_key])
		else:
			print("  ", key, ": ", info[key])
	print("==============================")

## Get fork geometry for visualization
func get_fork_geometry() -> Dictionary:
	var geometry: Dictionary = {}
	
	if not is_valid():
		return geometry
	
	var parent_node: Node = get_parent()
	
	# Get all bone positions
	geometry["bone_1_pos"] = parent_node.virt_skel.get_bone_position(bone_1)
	geometry["bone_2_pos"] = parent_node.virt_skel.get_bone_position(bone_2)
	geometry["bone_3_pos"] = parent_node.virt_skel.get_bone_position(bone_3)
	geometry["target_pos"] = parent_node.virt_skel.get_bone_position(bone_target)
	
	# Define connections for wireframe display
	geometry["connections"] = [
		[bone_1, bone_target],   # Fork arm 1
		[bone_2, bone_target],   # Fork arm 2
		[bone_3, bone_target]    # Fork arm 3
	]
	
	# Define triangular faces for solid display
	geometry["faces"] = [
		[bone_1, bone_2, bone_target],
		[bone_2, bone_3, bone_target],
		[bone_3, bone_1, bone_target]
	]
	
	# Distance visualization
	geometry["distances"] = [
		{"from": bone_1, "to": bone_target, "length": length_1},
		{"from": bone_2, "to": bone_target, "length": length_2},
		{"from": bone_3, "to": bone_target, "length": length_3}
	]
	
	return geometry

## Validate constraint satisfaction
func validate_constraints() -> Dictionary:
	var validation: Dictionary = {}
	
	if not is_valid():
		validation["error"] = "Fork configuration is invalid"
		return validation
	
	var parent_node: Node = get_parent()
	validation["constraints_satisfied"] = true
	validation["constraint_errors"] = []
	validation["max_error"] = 0.0
	
	# Check each distance constraint
	var pos_target: Vector3 = parent_node.virt_skel.get_bone_position(bone_target)
	
	# Bone 1 constraint
	var pos_1: Vector3 = parent_node.virt_skel.get_bone_position(bone_1)
	var current_dist_1: float = pos_1.distance_to(pos_target)
	var error_1: float = abs(current_dist_1 - length_1)
	if error_1 > 0.01:
		validation["constraints_satisfied"] = false
		validation["constraint_errors"].append("Bone 1 distance error: " + str(error_1))
	validation["max_error"] = max(validation["max_error"], error_1)
	
	# Bone 2 constraint
	var pos_2: Vector3 = parent_node.virt_skel.get_bone_position(bone_2)
	var current_dist_2: float = pos_2.distance_to(pos_target)
	var error_2: float = abs(current_dist_2 - length_2)
	if error_2 > 0.01:
		validation["constraints_satisfied"] = false
		validation["constraint_errors"].append("Bone 2 distance error: " + str(error_2))
	validation["max_error"] = max(validation["max_error"], error_2)
	
	# Bone 3 constraint
	var pos_3: Vector3 = parent_node.virt_skel.get_bone_position(bone_3)
	var current_dist_3: float = pos_3.distance_to(pos_target)
	var error_3: float = abs(current_dist_3 - length_3)
	if error_3 > 0.01:
		validation["constraints_satisfied"] = false
		validation["constraint_errors"].append("Bone 3 distance error: " + str(error_3))
	validation["max_error"] = max(validation["max_error"], error_3)
	
	# Overall assessment
	if validation["constraints_satisfied"]:
		validation["status"] = "All constraints satisfied"
	else:
		validation["status"] = "Constraint violations detected"
	
	return validation
#endregion
