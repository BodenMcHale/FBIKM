@tool
extends Marker3D  # Updated from Position3D
class_name IKPole

## FBIKM - Pole for Godot 4.4.1
## by Nemo Czanderlitch/Nino Čandrlić
## @R3X-G1L       (godot assets store)
## R3X-G1L6AME5H  (github)
##
## This node serves as a "pole target" or "elbow target" for IK chains. It ensures that joints
## bend in a specific direction by acting as a magnetic point that influences the orientation
## of the intermediate joints in a chain.
##
## Pole constraints are essential for controlling how multi-joint chains (like arms and legs)
## bend. Without a pole constraint, an arm might bend in an unnatural direction when reaching
## for a target. The pole ensures the elbow points toward this node, creating natural poses.
##
## Example: For an arm chain (shoulder -> elbow -> wrist), the pole target controls where
## the elbow points, preventing the arm from bending backward or into weird orientations.

## Node identifier for type checking
const FBIKM_NODE_ID: int = 2

## Enum for which side of the bone should face the pole target
enum SIDE {
	FORWARD,   ## Bone's forward vector points toward pole
	BACKWARD,  ## Bone's backward vector points toward pole
	LEFT,      ## Bone's left vector points toward pole
	RIGHT      ## Bone's right vector points toward pole
}

## Chain configuration
var tip_bone_id: String = "-1"   ## End bone of the chain (e.g., wrist for arm)
var root_bone_id: String = "-1"  ## Start bone of the chain (e.g., shoulder for arm)

## Pole behavior configuration
@export var turn_to: SIDE = SIDE.FORWARD  ## Which side of intermediate bones should face the pole

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

## Return current transform for the IK solver
func get_target() -> Transform3D:  # Updated return type
	return transform
#endregion

#region Validation and Helper Methods
## Validate that the pole configuration is correct
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
	
	# Validate chain length - need at least 3 bones for meaningful pole constraint
	var chain_length: int = get_chain_length()
	if chain_length < 3:
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

## Get the length of the chain (number of bones from tip to root)
func get_chain_length() -> int:
	var parent_node: Node = get_parent()
	if parent_node == null or parent_node.virt_skel == null:
		return 0
	
	if not parent_node.virt_skel.has_bone(tip_bone_id) or not parent_node.virt_skel.has_bone(root_bone_id):
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

## Get the middle bone(s) that will be primarily affected by the pole
func get_affected_bones() -> PackedStringArray:
	var chain_bones: PackedStringArray = get_chain_bones()
	var affected: PackedStringArray = []
	
	# Exclude tip and root bones - pole affects the middle joints
	for i in range(1, chain_bones.size() - 1):
		affected.append(chain_bones[i])
	
	return affected

## Calculate the ideal pole distance for natural bending
func get_recommended_pole_distance() -> float:
	if not is_valid():
		return 1.0
	
	var parent_node: Node = get_parent()
	var chain_bones: PackedStringArray = get_chain_bones()
	
	if chain_bones.size() < 3:
		return 1.0
	
	# Calculate total chain length
	var total_length: float = 0.0
	for i in range(chain_bones.size() - 1):
		var bone_id: String = chain_bones[i]
		total_length += parent_node.virt_skel.get_bone_length(bone_id)
	
	# Recommended pole distance is typically 50-100% of chain length
	return total_length * 0.75

## Check if pole is positioned optimally
func is_optimally_positioned() -> bool:
	if not is_valid():
		return false
	
	var recommended_distance: float = get_recommended_pole_distance()
	var actual_distance: float = get_distance_to_chain_center()
	
	# Allow 50% tolerance around recommended distance
	var tolerance: float = recommended_distance * 0.5
	return abs(actual_distance - recommended_distance) <= tolerance

## Get distance from pole to center of the chain
func get_distance_to_chain_center() -> float:
	if not is_valid():
		return 0.0
	
	var parent_node: Node = get_parent()
	var chain_bones: PackedStringArray = get_chain_bones()
	
	if chain_bones.is_empty():
		return 0.0
	
	# Calculate chain center
	var center: Vector3 = Vector3.ZERO
	for bone_id in chain_bones:
		center += parent_node.virt_skel.get_bone_position(bone_id)
	center /= float(chain_bones.size())
	
	return global_position.distance_to(center)

## Get the angle between pole direction and current chain bending
func get_pole_alignment_angle() -> float:
	if not is_valid():
		return 0.0
	
	var parent_node: Node = get_parent()
	var affected_bones: PackedStringArray = get_affected_bones()
	
	if affected_bones.is_empty():
		return 0.0
	
	# Use the first affected bone (closest to tip) for analysis
	var affected_bone: String = affected_bones[0]
	var bone_pos: Vector3 = parent_node.virt_skel.get_bone_position(affected_bone)
	var pole_direction: Vector3 = (global_position - bone_pos).normalized()
	
	# Get current bone orientation based on turn_to setting
	var bone_rotation: Quaternion = parent_node.virt_skel.get_bone_rotation(affected_bone)
	var bone_direction: Vector3
	
	match turn_to:
		SIDE.FORWARD:
			bone_direction = bone_rotation * Vector3.FORWARD
		SIDE.BACKWARD:
			bone_direction = bone_rotation * Vector3.BACK
		SIDE.LEFT:
			bone_direction = bone_rotation * Vector3.LEFT
		SIDE.RIGHT:
			bone_direction = bone_rotation * Vector3.RIGHT
	
	return bone_direction.angle_to(pole_direction)
#endregion

#region Utility Methods
## Set bones by name instead of ID
func set_chain_by_names(tip_name: String, root_name: String) -> bool:
	var parent_node: Node = get_parent()
	if parent_node == null or parent_node.skel == null:
		return false
	
	var skel: Skeleton3D = parent_node.skel
	var found_tip: String = "-1"
	var found_root: String = "-1"
	
	# Find bone IDs by name
	for i in range(skel.get_bone_count()):
		var name: String = skel.get_bone_name(i)
		if name == tip_name:
			found_tip = str(i)
		elif name == root_name:
			found_root = str(i)
	
	if found_tip != "-1" and found_root != "-1":
		tip_bone_id = found_tip
		root_bone_id = found_root
		notify_property_list_changed()
		return true
	
	return false

## Get bone names for configured bones
func get_bone_names() -> Dictionary:
	var names: Dictionary = {}
	var parent_node: Node = get_parent()
	
	if parent_node == null or parent_node.skel == null:
		return names
	
	var skel: Skeleton3D = parent_node.skel
	
	if tip_bone_id != "-1" and int(tip_bone_id) < skel.get_bone_count():
		names["tip"] = skel.get_bone_name(int(tip_bone_id))
	if root_bone_id != "-1" and int(root_bone_id) < skel.get_bone_count():
		names["root"] = skel.get_bone_name(int(root_bone_id))
	
	return names

## Position pole automatically for natural bending
func auto_position_pole() -> void:
	if not is_valid():
		return
	
	var parent_node: Node = get_parent()
	var chain_bones: PackedStringArray = get_chain_bones()
	
	if chain_bones.size() < 3:
		return
	
	# Calculate chain center and natural bending direction
	var chain_center: Vector3 = Vector3.ZERO
	for bone_id in chain_bones:
		chain_center += parent_node.virt_skel.get_bone_position(bone_id)
	chain_center /= float(chain_bones.size())
	
	# Get tip and root positions
	var tip_pos: Vector3 = parent_node.virt_skel.get_bone_position(tip_bone_id)
	var root_pos: Vector3 = parent_node.virt_skel.get_bone_position(root_bone_id)
	
	# Calculate perpendicular direction from chain line
	var chain_direction: Vector3 = (tip_pos - root_pos).normalized()
	var to_center: Vector3 = chain_center - root_pos
	var perpendicular: Vector3 = to_center - chain_direction * to_center.dot(chain_direction)
	
	if perpendicular.length() < 0.001:
		# Chain is straight, use a default perpendicular direction
		perpendicular = Vector3.UP if abs(chain_direction.dot(Vector3.UP)) < 0.9 else Vector3.RIGHT
	
	perpendicular = perpendicular.normalized()
	
	# Position pole at recommended distance
	var recommended_distance: float = get_recommended_pole_distance()
	global_position = chain_center + perpendicular * recommended_distance

## Mirror pole position across a plane (useful for symmetric setups)
func mirror_position(plane_normal: Vector3, plane_point: Vector3) -> void:
	var plane: Plane = Plane(plane_normal.normalized(), plane_point)
	global_position = plane.project(global_position) + (plane.project(global_position) - global_position)
#endregion

#region Debug and Visualization
## Get debug information about the pole constraint
func get_debug_info() -> Dictionary:
	var info: Dictionary = {}
	info["tip_bone_id"] = tip_bone_id
	info["root_bone_id"] = root_bone_id
	info["turn_to"] = SIDE.keys()[turn_to]
	info["is_valid"] = is_valid()
	info["chain_length"] = get_chain_length()
	info["pole_position"] = global_position
	info["distance_to_chain_center"] = get_distance_to_chain_center()
	info["recommended_pole_distance"] = get_recommended_pole_distance()
	info["is_optimally_positioned"] = is_optimally_positioned()
	info["pole_alignment_angle_degrees"] = rad_to_deg(get_pole_alignment_angle())
	
	# Chain information
	info["chain_bones"] = get_chain_bones()
	info["affected_bones"] = get_affected_bones()
	info["bone_names"] = get_bone_names()
	
	# Performance metrics
	var parent_node: Node = get_parent()
	if parent_node != null and parent_node.virt_skel != null:
		var chain_bones: PackedStringArray = get_chain_bones()
		var total_chain_length: float = 0.0
		for i in range(chain_bones.size() - 1):
			total_chain_length += parent_node.virt_skel.get_bone_length(chain_bones[i])
		info["total_chain_length"] = total_chain_length
	
	return info

## Print debug information to console
func print_debug_info() -> void:
	var info: Dictionary = get_debug_info()
	print("=== IK Pole Debug Info ===")
	for key in info.keys():
		print("  ", key, ": ", info[key])
	print("==========================")

## Get visualization data for editor gizmos
func get_visualization_data() -> Dictionary:
	var data: Dictionary = {}
	
	if not is_valid():
		return data
	
	var parent_node: Node = get_parent()
	var chain_bones: PackedStringArray = get_chain_bones()
	
	# Pole position and target information
	data["pole_position"] = global_position
	data["pole_target_transform"] = transform
	
	# Chain bone positions for visualization
	data["chain_positions"] = []
	for bone_id in chain_bones:
		data["chain_positions"].append(parent_node.virt_skel.get_bone_position(bone_id))
	
	# Chain center and recommended position
	if not chain_bones.is_empty():
		var center: Vector3 = Vector3.ZERO
		for pos in data["chain_positions"]:
			center += pos
		center /= float(data["chain_positions"].size())
		data["chain_center"] = center
		
		# Recommended pole position
		var recommended_distance: float = get_recommended_pole_distance()
		var to_pole: Vector3 = (global_position - center).normalized()
		data["recommended_position"] = center + to_pole * recommended_distance
	
	# Affected bones highlighting
	data["affected_bone_positions"] = []
	for bone_id in get_affected_bones():
		data["affected_bone_positions"].append(parent_node.virt_skel.get_bone_position(bone_id))
	
	# Pole influence vectors (from affected bones to pole)
	data["influence_vectors"] = []
	for bone_id in get_affected_bones():
		var bone_pos: Vector3 = parent_node.virt_skel.get_bone_position(bone_id)
		data["influence_vectors"].append({
			"from": bone_pos,
			"to": global_position,
			"direction": (global_position - bone_pos).normalized()
		})
	
	return data

## Validate pole constraint effectiveness
func validate_pole_setup() -> Dictionary:
	var validation: Dictionary = {}
	validation["is_effective"] = true
	validation["warnings"] = []
	validation["suggestions"] = []
	
	if not is_valid():
		validation["is_effective"] = false
		validation["warnings"].append("Invalid pole configuration")
		return validation
	
	# Check chain length
	var chain_length: int = get_chain_length()
	if chain_length < 3:
		validation["warnings"].append("Chain too short for meaningful pole constraint")
		validation["suggestions"].append("Pole constraints work best with chains of 3+ bones")
	
	# Check pole positioning
	if not is_optimally_positioned():
		validation["warnings"].append("Pole may be positioned suboptimally")
		validation["suggestions"].append("Try using auto_position_pole() for better placement")
	
	# Check pole distance
	var distance: float = get_distance_to_chain_center()
	var recommended: float = get_recommended_pole_distance()
	
	if distance < recommended * 0.2:
		validation["warnings"].append("Pole too close to chain - may cause instability")
		validation["suggestions"].append("Move pole further from chain center")
	elif distance > recommended * 3.0:
		validation["warnings"].append("Pole very far from chain - may have weak influence")
		validation["suggestions"].append("Move pole closer to chain for stronger effect")
	
	# Check alignment
	var alignment_angle: float = rad_to_deg(get_pole_alignment_angle())
	if alignment_angle > 120.0:
		validation["warnings"].append("Poor pole alignment - bones pointing away from pole")
		validation["suggestions"].append("Reposition pole or check turn_to setting")
	
	if validation["warnings"].is_empty():
		validation["suggestions"].append("Pole setup looks good!")
	
	return validation
#endregion
