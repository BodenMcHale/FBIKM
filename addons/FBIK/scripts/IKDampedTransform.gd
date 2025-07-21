@tool
extends Node
class_name IKDampedTransform

## FBIKM - Damped Transform for Godot 4.4.1
## by Nemo Czanderlitch/Nino Čandrlić
## @R3X-G1L       (godot assets store)
## R3X-G1L6AME5H  (github)
##
## Applies physics-based motion to the specified bone and its children.
## Useful for tails, ears, hair, cloth, and other "hanging" or flexible elements.
## This creates natural secondary animation that responds to the character's movement
## with realistic spring and damping behavior.
##
## The system simulates mass, stiffness, and damping for each bone in the chain,
## creating believable physics without the complexity of a full physics simulation.

## Node identifier for type checking
const FBIKM_NODE_ID: int = 8

## Target bone configuration
var bone_id: String = "-1"  ## The root bone that will have physics applied (along with its children)

## Physics properties for the root bone
@export_range(0.005, 1.0) var stiffness: float = 0.1  ## How quickly bones return to their target position
@export_range(0.005, 1.0) var damping: float = 0.75   ## How quickly oscillations fade out
@export var mass: float = 0.9                         ## Mass affects inertia and response to forces
@export var gravity: float = 0.0                      ## Downward force applied to bones

## Multipliers for child bones (creates tapering effect down the chain)
## For example:
##   1st bone: mass = mass
##   2nd bone: mass = mass * mass_passed_down
##   3rd bone: mass = mass * mass_passed_down^2
##   etc.
@export_range(0.005, 2.0) var stiffness_passed_down: float = 1.0  ## Stiffness multiplier for children
@export_range(0.005, 2.0) var damping_passed_down: float = 1.0    ## Damping multiplier for children  
@export_range(0.005, 2.0) var mass_passed_down: float = 1.0       ## Mass multiplier for children

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
## Validate that the damped transform configuration is correct
func is_valid() -> bool:
	if bone_id == "-1":
		return false
	
	var parent_node: Node = get_parent()
	if parent_node == null or parent_node.get("FBIKM_NODE_ID") != 0:
		return false
	
	# Check if bone exists in the skeleton
	if parent_node.virt_skel == null:
		return false
	
	return parent_node.virt_skel.has_bone(bone_id)

## Get all bones that will be affected by this damped transform
func get_affected_bones() -> PackedStringArray:
	var bones: PackedStringArray = []
	
	if not is_valid():
		return bones
	
	var parent_node: Node = get_parent()
	
	# Start with the root bone
	var bone_queue: PackedStringArray = [bone_id]
	var processed: Dictionary = {}
	
	while not bone_queue.is_empty():
		var current_bone: String = bone_queue[0]
		bone_queue.remove_at(0)
		
		if processed.has(current_bone):
			continue
		
		processed[current_bone] = true
		bones.append(current_bone)
		
		# Add children to queue
		var children: Array = parent_node.virt_skel.get_bone_children(current_bone)
		for child in children:
			if not processed.has(child):
				bone_queue.append(child)
	
	return bones

## Calculate physics properties for a specific bone in the chain
func get_bone_physics_properties(target_bone_id: String) -> Dictionary:
	var properties: Dictionary = {}
	
	if not is_valid():
		return properties
	
	var parent_node: Node = get_parent()
	
	# Calculate depth from root bone
	var depth: int = 0
	var current_bone: String = target_bone_id
	var max_iterations: int = 100  # Prevent infinite loops
	
	while current_bone != bone_id and current_bone != "-1" and max_iterations > 0:
		current_bone = parent_node.virt_skel.get_bone_parent(current_bone)
		depth += 1
		max_iterations -= 1
	
	if current_bone != bone_id:
		# Target bone is not a child of the root bone
		return properties
	
	# Apply multipliers based on depth
	var depth_multiplier: float = 1.0
	for i in range(depth):
		depth_multiplier *= mass_passed_down
	
	properties["stiffness"] = stiffness * pow(stiffness_passed_down, depth)
	properties["damping"] = damping * pow(damping_passed_down, depth)
	properties["mass"] = mass * depth_multiplier
	properties["gravity"] = gravity
	properties["depth"] = depth
	
	# Clamp values to reasonable ranges
	properties["stiffness"] = clamp(properties["stiffness"], 0.001, 1.0)
	properties["damping"] = clamp(properties["damping"], 0.001, 1.0)
	properties["mass"] = max(properties["mass"], 0.001)
	
	return properties

## Check if the physics properties create a stable system
func is_stable_configuration() -> bool:
	# Check basic stability criteria
	if stiffness <= 0.0 or damping <= 0.0 or mass <= 0.0:
		return false
	
	# Check that multipliers are reasonable
	if (stiffness_passed_down <= 0.0 or damping_passed_down <= 0.0 or 
		mass_passed_down <= 0.0):
		return false
	
	# For stability, damping should generally be less than critical damping
	# Critical damping ratio ≈ 2 * sqrt(stiffness * mass)
	var critical_damping: float = 2.0 * sqrt(stiffness * mass)
	return damping < critical_damping * 2.0  # Allow some overdamping

## Estimate the settling time for the physics system
func get_estimated_settling_time() -> float:
	if not is_stable_configuration():
		return -1.0  # Unstable system
	
	# Rough estimation based on damping ratio
	var natural_frequency: float = sqrt(stiffness / mass)
	var damping_ratio: float = damping / (2.0 * sqrt(stiffness * mass))
	
	if damping_ratio >= 1.0:
		# Overdamped system
		return 4.0 / (damping_ratio * natural_frequency)
	else:
		# Underdamped system  
		return 4.0 / (damping_ratio * natural_frequency)

## Get the chain length (number of bones affected)
func get_chain_length() -> int:
	return get_affected_bones().size()
#endregion

#region Physics Simulation Helpers
## Apply an impulse to the entire chain
func apply_impulse(impulse: Vector3) -> void:
	if not is_valid():
		return
	
	var parent_node: Node = get_parent()
	var affected_bones: PackedStringArray = get_affected_bones()
	
	# Apply scaled impulse to each bone based on its mass
	for bone in affected_bones:
		var properties: Dictionary = get_bone_physics_properties(bone)
		if properties.has("mass"):
			var scaled_impulse: Vector3 = impulse / properties["mass"]
			# Note: Actual impulse application would be handled by the VirtualSkeleton
			# This is more of a conceptual interface
			pass

## Simulate wind effect on the chain
func apply_wind_force(wind_direction: Vector3, wind_strength: float) -> void:
	if not is_valid():
		return
	
	var affected_bones: PackedStringArray = get_affected_bones()
	
	# Apply wind force proportional to bone mass and surface area
	for bone in affected_bones:
		var properties: Dictionary = get_bone_physics_properties(bone)
		if properties.has("mass"):
			# Lighter bones (deeper in chain) are more affected by wind
			var wind_multiplier: float = 1.0 / properties["mass"]
			var wind_impulse: Vector3 = wind_direction.normalized() * wind_strength * wind_multiplier
			# Apply the wind impulse (would be handled by physics system)
			pass

## Reset all velocities in the chain to zero
func reset_chain_physics() -> void:
	if not is_valid():
		return
	
	var parent_node: Node = get_parent()
	var affected_bones: PackedStringArray = get_affected_bones()
	
	# Reset velocities (this would be handled by the VirtualSkeleton)
	for bone in affected_bones:
		# parent_node.virt_skel.set_bone_velocity(bone, Vector3.ZERO)
		pass
#endregion

#region Debug and Visualization
## Get debug information about the damped transform
func get_debug_info() -> Dictionary:
	var info: Dictionary = {}
	info["bone_id"] = bone_id
	info["is_valid"] = is_valid()
	info["is_stable"] = is_stable_configuration()
	info["estimated_settling_time"] = get_estimated_settling_time()
	info["chain_length"] = get_chain_length()
	
	# Physics properties
	info["stiffness"] = stiffness
	info["damping"] = damping
	info["mass"] = mass
	info["gravity"] = gravity
	
	# Multipliers
	info["stiffness_passed_down"] = stiffness_passed_down
	info["damping_passed_down"] = damping_passed_down
	info["mass_passed_down"] = mass_passed_down
	
	# Affected bones
	info["affected_bones"] = get_affected_bones()
	
	# Bone name for reference
	var parent_node: Node = get_parent()
	if parent_node != null and parent_node.skel != null:
		if bone_id != "-1" and int(bone_id) < parent_node.skel.get_bone_count():
			info["bone_name"] = parent_node.skel.get_bone_name(int(bone_id))
	
	# Physics analysis for each affected bone
	var bone_physics: Array = []
	for bone in get_affected_bones():
		var bone_props: Dictionary = get_bone_physics_properties(bone)
		bone_props["bone_id"] = bone
		if parent_node != null and parent_node.skel != null and int(bone) < parent_node.skel.get_bone_count():
			bone_props["bone_name"] = parent_node.skel.get_bone_name(int(bone))
		bone_physics.append(bone_props)
	
	info["bone_physics"] = bone_physics
	
	return info

## Print debug information to console
func print_debug_info() -> void:
	var info: Dictionary = get_debug_info()
	print("=== IK Damped Transform Debug Info ===")
	for key in info.keys():
		if key == "bone_physics":
			print("  bone_physics:")
			for bone_data in info[key]:
				print("    ", bone_data)
		else:
			print("  ", key, ": ", info[key])
	print("=====================================")

## Get physics visualization data for editor gizmos
func get_physics_visualization() -> Dictionary:
	var viz: Dictionary = {}
	
	if not is_valid():
		return viz
	
	var parent_node: Node = get_parent()
	var affected_bones: PackedStringArray = get_affected_bones()
	
	viz["bone_positions"] = []
	viz["bone_properties"] = []
	viz["chain_connections"] = []
	
	# Collect bone positions and properties
	for i in range(affected_bones.size()):
		var bone: String = affected_bones[i]
		var pos: Vector3 = parent_node.virt_skel.get_bone_position(bone)
		var props: Dictionary = get_bone_physics_properties(bone)
		
		viz["bone_positions"].append(pos)
		viz["bone_properties"].append(props)
		
		# Add connection to parent (except for root)
		if i > 0:
			viz["chain_connections"].append([i-1, i])
	
	return viz

## Analyze the frequency response of the system
func analyze_frequency_response() -> Dictionary:
	var analysis: Dictionary = {}
	
	if not is_stable_configuration():
		analysis["error"] = "System is not stable"
		return analysis
	
	# Calculate natural frequency and damping ratio
	var natural_freq: float = sqrt(stiffness / mass)
	var damping_ratio: float = damping / (2.0 * sqrt(stiffness * mass))
	
	analysis["natural_frequency_hz"] = natural_freq / (2.0 * PI)
	analysis["damping_ratio"] = damping_ratio
	
	if damping_ratio < 1.0:
		# Underdamped
		analysis["system_type"] = "Underdamped"
		analysis["damped_frequency_hz"] = natural_freq * sqrt(1.0 - damping_ratio * damping_ratio) / (2.0 * PI)
		analysis["overshoot_percent"] = exp(-PI * damping_ratio / sqrt(1.0 - damping_ratio * damping_ratio)) * 100.0
	elif damping_ratio == 1.0:
		# Critically damped
		analysis["system_type"] = "Critically Damped"
		analysis["overshoot_percent"] = 0.0
	else:
		# Overdamped
		analysis["system_type"] = "Overdamped"
		analysis["overshoot_percent"] = 0.0
	
	return analysis

## Validate physics parameters and provide suggestions
func validate_physics_setup() -> Dictionary:
	var validation: Dictionary = {}
	validation["is_valid"] = true
	validation["warnings"] = []
	validation["suggestions"] = []
	
	# Check for common issues
	if stiffness > 0.8:
		validation["warnings"].append("High stiffness may cause jittery motion")
		validation["suggestions"].append("Consider reducing stiffness to 0.1-0.5 range")
	
	if damping < 0.1:
		validation["warnings"].append("Low damping may cause excessive oscillation")
		validation["suggestions"].append("Consider increasing damping to 0.3-0.8 range")
	
	if mass < 0.1:
		validation["warnings"].append("Very low mass may cause unstable behavior")
		validation["suggestions"].append("Consider increasing mass to 0.5+ range")
	
	if abs(gravity) > 2.0:
		validation["warnings"].append("High gravity values may dominate other forces")
		validation["suggestions"].append("Consider reducing gravity magnitude")
	
	# Check multiplier relationships
	if stiffness_passed_down > 1.5:
		validation["warnings"].append("Increasing stiffness down the chain may cause instability")
		validation["suggestions"].append("Consider using stiffness_passed_down < 1.0 for more natural motion")
	
	if mass_passed_down < 0.5:
		validation["warnings"].append("Rapidly decreasing mass may cause abrupt motion changes")
		validation["suggestions"].append("Consider using mass_passed_down closer to 1.0")
	
	# Performance warnings
	var chain_length: int = get_chain_length()
	if chain_length > 10:
		validation["warnings"].append("Long chains (" + str(chain_length) + " bones) may impact performance")
		validation["suggestions"].append("Consider splitting into multiple shorter chains")
	
	if validation["warnings"].is_empty():
		validation["suggestions"].append("Physics setup looks good!")
	
	return validation
#endregion

#region Utility Methods
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

## Create preset configurations for common use cases
func apply_preset(preset_name: String) -> void:
	match preset_name.to_lower():
		"tail_light":
			stiffness = 0.15
			damping = 0.6
			mass = 0.3
			gravity = 0.5
			stiffness_passed_down = 0.8
			damping_passed_down = 0.9
			mass_passed_down = 0.7
		
		"tail_heavy":
			stiffness = 0.25
			damping = 0.8
			mass = 1.2
			gravity = 1.0
			stiffness_passed_down = 0.9
			damping_passed_down = 1.0
			mass_passed_down = 0.8
		
		"hair":
			stiffness = 0.08
			damping = 0.4
			mass = 0.2
			gravity = 0.3
			stiffness_passed_down = 0.7
			damping_passed_down = 0.8
			mass_passed_down = 0.6
		
		"ears":
			stiffness = 0.3
			damping = 0.9
			mass = 0.5
			gravity = 0.2
			stiffness_passed_down = 0.9
			damping_passed_down = 1.1
			mass_passed_down = 0.9
		
		"cloth":
			stiffness = 0.12
			damping = 0.7
			mass = 0.4
			gravity = 0.8
			stiffness_passed_down = 0.85
			damping_passed_down = 0.95
			mass_passed_down = 0.75
		
		_:
			push_warning("Unknown preset: " + preset_name)

## Get available presets
func get_available_presets() -> PackedStringArray:
	return PackedStringArray(["tail_light", "tail_heavy", "hair", "ears", "cloth"])
#endregion
