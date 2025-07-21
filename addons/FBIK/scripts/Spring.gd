@tool
extends Node3D  # Updated from Spatial
class_name Spring

## FBIKM - Spring for Godot 4.4.1
## by Nemo Czanderlitch/Nino Čandrlić
## @R3X-G1L       (godot assets store)
## R3X-G1L6AME5H  (github)
##
## A simple script to add life to Inverse Solver Animations. It is meant to be applied to Chain's
## target node. Given that the IK solver strictly follows its target, the movement looks very
## mechanical. If the target were to be a bit bouncy, the IK would be a bit more lively as well.
## This is the purpose of this script.
##
## Physics-based spring system that applies realistic motion to IK targets, making animations
## feel more natural and less robotic.

## Configuration properties
@export var constrained_node: NodePath  ## The node that will follow this spring motion
@export_range(0.005, 1.0) var stiffness: float = 0.25  ## How quickly the spring returns to target
@export_range(0.005, 1.0) var mass: float = 0.9  ## Mass affects acceleration and momentum
@export_range(0.005, 1.0) var damping: float = 0.75  ## How quickly oscillations fade out
@export_range(0.0, 1.0) var gravity: float = 0.0  ## Downward force applied to the spring

## Rotational spring properties
@export var solve_rotations: bool = false  ## Whether to apply spring physics to rotation
@export_range(0.005, 1.0) var rotation_stiffness: float = 1.0  ## Rotational spring strength
@export_range(0.005, 1.0) var rotation_damping: float = 1.0  ## Rotational damping

## Internal spring state for position
var dynamic_pos: Vector3  ## Current spring position (offset from target)
var force: Vector3  ## Current force being applied
var acc: Vector3  ## Current acceleration
var vel: Vector3  ## Current velocity

## Internal spring state for rotation
var dynamic_rot: Quaternion  # Updated type from Quat
var rot_force: Quaternion
var rot_acc: Quaternion
var rot_vel: Quaternion

#region Initialization
func _ready() -> void:
	# Set the dynamic (spring) values to current transform
	dynamic_pos = transform.origin
	dynamic_rot = transform.basis.get_rotation_quaternion()  # Updated method

func _physics_process(delta: float) -> void:
	# Apply the new transform to target
	if constrained_node != NodePath():
		var target_node: Node = get_node_or_null(constrained_node)
		if target_node != null:
			target_node.transform = spring(transform)
#endregion

#region Core Spring Physics
## Calculate spring physics and return the resulting transform
func spring(target: Transform3D) -> Transform3D:  # Updated type
	# Springy momentum physics for position
	force = (target.origin - dynamic_pos) * stiffness
	force.y -= gravity / 10.0
	acc = force / mass
	vel += acc * (1.0 - damping)
	dynamic_pos += vel + force

	# Springy rotations (if enabled)
	if solve_rotations:
		var target_rot: Quaternion = target.basis.get_rotation_quaternion()
		rot_force = (target_rot - dynamic_rot) * rotation_stiffness
		rot_acc = rot_force / mass
		rot_vel += rot_acc * (1.0 - rotation_damping)
		dynamic_rot += rot_force + rot_vel
		dynamic_rot = dynamic_rot.normalized()
	else:
		dynamic_rot = target.basis.get_rotation_quaternion()
	
	return Transform3D(Basis(dynamic_rot), dynamic_pos)
#endregion

#region Public Interface
## Set the spring target position directly
func set_spring_target(target_pos: Vector3) -> void:
	transform.origin = target_pos

## Set the spring target transform directly
func set_spring_target_transform(target_transform: Transform3D) -> void:
	transform = target_transform

## Reset spring to current target with no velocity
func reset_spring() -> void:
	dynamic_pos = transform.origin
	dynamic_rot = transform.basis.get_rotation_quaternion()
	force = Vector3.ZERO
	acc = Vector3.ZERO
	vel = Vector3.ZERO
	rot_force = Quaternion.IDENTITY
	rot_acc = Quaternion.IDENTITY
	rot_vel = Quaternion.IDENTITY

## Add impulse to the spring system
func add_impulse(impulse: Vector3) -> void:
	vel += impulse / mass

## Add rotational impulse to the spring system
func add_rotational_impulse(axis: Vector3, angle: float) -> void:
	if solve_rotations:
		var impulse_quat: Quaternion = Quaternion(axis.normalized(), angle)
		rot_vel = rot_vel * impulse_quat

## Get current spring velocity
func get_spring_velocity() -> Vector3:
	return vel

## Get current spring position
func get_spring_position() -> Vector3:
	return dynamic_pos

## Check if spring is approximately at rest
func is_at_rest(threshold: float = 0.01) -> bool:
	var pos_diff: float = dynamic_pos.distance_to(transform.origin)
	var vel_magnitude: float = vel.length()
	
	if solve_rotations:
		var rot_diff: float = dynamic_rot.angle_to(transform.basis.get_rotation_quaternion())
		return pos_diff < threshold and vel_magnitude < threshold and rot_diff < deg_to_rad(1.0)
	else:
		return pos_diff < threshold and vel_magnitude < threshold
#endregion

#region Validation and Helper Methods
## Validate that the spring configuration is correct
func is_valid() -> bool:
	if constrained_node == NodePath():
		return false
	
	var target_node: Node = get_node_or_null(constrained_node)
	return target_node != null and target_node is Node3D

## Check if the physics properties create a stable system
func is_stable_configuration() -> bool:
	# Check basic stability criteria
	if stiffness <= 0.0 or damping <= 0.0 or mass <= 0.0:
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

## Set constrained node by name (searches in parent)
func set_constrained_node_by_name(node_name: String) -> bool:
	var parent: Node = get_parent()
	if parent == null:
		return false
	
	var target_node: Node = parent.find_child(node_name, false, false)
	if target_node != null and target_node is Node3D:
		constrained_node = get_path_to(target_node)
		return true
	
	return false

## Get the constrained node name
func get_constrained_node_name() -> String:
	if constrained_node == NodePath():
		return ""
	
	var target_node: Node = get_node_or_null(constrained_node)
	return target_node.name if target_node != null else ""
#endregion

#region Debug and Visualization
## Get debug information about the spring state
func get_debug_info() -> Dictionary:
	var info: Dictionary = {}
	info["is_valid"] = is_valid()
	info["is_stable"] = is_stable_configuration()
	info["estimated_settling_time"] = get_estimated_settling_time()
	info["is_at_rest"] = is_at_rest()
	
	# Current state
	info["target_position"] = transform.origin
	info["spring_position"] = dynamic_pos
	info["velocity"] = vel
	info["acceleration"] = acc
	info["force"] = force
	
	# Configuration
	info["constrained_node"] = constrained_node
	info["constrained_node_name"] = get_constrained_node_name()
	info["solve_rotations"] = solve_rotations
	
	# Physics parameters
	info["stiffness"] = stiffness
	info["mass"] = mass
	info["damping"] = damping
	info["gravity"] = gravity
	
	if solve_rotations:
		info["target_rotation"] = transform.basis.get_rotation_quaternion()
		info["spring_rotation"] = dynamic_rot
		info["rotation_stiffness"] = rotation_stiffness
		info["rotation_damping"] = rotation_damping
	
	return info

## Print debug information to console
func print_debug_info() -> void:
	var info: Dictionary = get_debug_info()
	print("=== Spring Debug Info ===")
	for key in info.keys():
		print("  ", key, ": ", info[key])
	print("=========================")

## Validate spring setup and provide suggestions
func validate_spring_setup() -> Dictionary:
	var validation: Dictionary = {}
	validation["is_effective"] = true
	validation["warnings"] = []
	validation["suggestions"] = []
	
	if not is_valid():
		validation["is_effective"] = false
		validation["warnings"].append("Invalid spring configuration - no constrained node")
		validation["suggestions"].append("Set a valid constrained_node path")
		return validation
	
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
	
	if not is_stable_configuration():
		validation["warnings"].append("Spring configuration may be unstable")
		validation["suggestions"].append("Check stiffness, mass, and damping values")
	
	if validation["warnings"].is_empty():
		validation["suggestions"].append("Spring setup looks good!")
	
	return validation

## Apply preset configurations for common use cases
func apply_preset(preset_name: String) -> void:
	match preset_name.to_lower():
		"bouncy":
			stiffness = 0.15
			mass = 0.5
			damping = 0.4
			gravity = 0.2
			solve_rotations = false
		
		"smooth":
			stiffness = 0.3
			mass = 0.8
			damping = 0.9
			gravity = 0.1
			solve_rotations = false
		
		"heavy":
			stiffness = 0.2
			mass = 1.5
			damping = 0.8
			gravity = 0.5
			solve_rotations = false
		
		"floaty":
			stiffness = 0.1
			mass = 0.3
			damping = 0.6
			gravity = -0.1
			solve_rotations = false
		
		"rigid":
			stiffness = 0.8
			mass = 0.9
			damping = 0.95
			gravity = 0.0
			solve_rotations = true
			rotation_stiffness = 0.9
			rotation_damping = 0.9
		
		_:
			push_warning("Unknown preset: " + preset_name)

## Get available presets
func get_available_presets() -> PackedStringArray:
	return PackedStringArray(["bouncy", "smooth", "heavy", "floaty", "rigid"])
#endregion
