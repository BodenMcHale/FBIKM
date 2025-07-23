@tool
extends Marker3D
const FBIKM_NODE_ID = 11  # THIS NODE'S IDENTIFIER

"""
		FBIKM - Ragdoll Controller
				by Nemo Czanderlitch/Nino Čandrlić
						@R3X-G1L       (godot assets store)
						R3X-G1L6AME5H  (github)
		Controls ragdoll movement and transitions. Allows for active ragdoll
		control where the character can be moved and manipulated while in
		physics mode. Acts as a target for ragdoll movement.
"""

# Control properties
@export var active_ragdoll: bool = false
@export_range(0.0, 1.0) var control_strength: float = 0.5
@export_range(0.1, 5.0) var response_speed: float = 2.0
@export_range(0.0, 1.0) var stability_threshold: float = 0.8

# Movement properties
@export var target_velocity: Vector3 = Vector3.ZERO
@export_range(0.0, 100.0) var max_force: float = 50.0
@export var maintain_upright: bool = true
@export_range(0.0, 90.0) var max_lean_angle: float = 30.0

# State tracking
var ragdoll_state: RagdollState = RagdollState.ANIMATED
var transition_progress: float = 0.0
var physics_ragdoll: Node = null

enum RagdollState {
	ANIMATED,       # Pure IK control
	TRANSITIONING,  # Blending IK and physics
	RAGDOLL,        # Pure physics
	ACTIVE_RAGDOLL  # Physics with active control
}

signal state_changed(new_state: RagdollState)

## BOILERPLATE FOR DROPDOWN MENU ##
var _bone_names = "VOID:-1"

## BOILERPLATE FOR INTEGRATION WITH FBIKM ########################################
func _ready():
	if Engine.is_editor_hint():
		if get_parent().get("FBIKM_NODE_ID") == 0:  ## This is KinematicsManager's ID
			get_parent().connect("bone_names_obtained", _update_parameters)
			_find_physics_ragdoll()

func _update_parameters(bone_names: String) -> void:
	_bone_names = bone_names
	notify_property_list_changed()

func _find_physics_ragdoll():
	"""Find the physics ragdoll node in the same manager"""
	var manager = get_parent()
	for child in manager.get_children():
		if child.get("FBIKM_NODE_ID") == 10:  # PhysicsRagdoll ID
			physics_ragdoll = child
			break

## RAGDOLL STATE MANAGEMENT #######################################################
func activate_ragdoll(impact_force: Vector3 = Vector3.ZERO, impact_bone: String = ""):
	"""Transition to ragdoll mode with optional impact"""
	if ragdoll_state == RagdollState.RAGDOLL or ragdoll_state == RagdollState.ACTIVE_RAGDOLL:
		return
		
	_change_state(RagdollState.TRANSITIONING)
	
	# Apply impact if specified
	if physics_ragdoll and impact_force.length() > 0:
		if impact_bone == "":
			impact_bone = physics_ragdoll.get_closest_bone_to_point(global_transform.origin)
		physics_ragdoll.apply_force_to_bone(impact_bone, impact_force)
	
	# Start transition
	var tween = create_tween()
	tween.tween_method(_transition_to_ragdoll, 0.0, 1.0, 1.0)
	tween.tween_callback(_complete_ragdoll_transition)

func activate_active_ragdoll():
	"""Switch to active ragdoll mode (physics + control)"""
	if ragdoll_state != RagdollState.RAGDOLL:
		activate_ragdoll()
		await state_changed
	
	if ragdoll_state == RagdollState.RAGDOLL:
		_change_state(RagdollState.ACTIVE_RAGDOLL)

func deactivate_ragdoll():
	"""Return to pure IK animation"""
	if ragdoll_state == RagdollState.ANIMATED:
		return
		
	_change_state(RagdollState.TRANSITIONING)
	
	var tween = create_tween()
	tween.tween_method(_transition_to_animation, 1.0, 0.0, 1.5)
	tween.tween_callback(_complete_animation_transition)

func _transition_to_ragdoll(progress: float):
	"""Smooth transition from animation to ragdoll"""
	transition_progress = progress
	
	if physics_ragdoll:
		if progress > 0.5:
			physics_ragdoll.enable_ragdoll()
		
		# Gradually reduce IK influence
		var manager = get_parent()
		if manager and manager.has_method("set"):
			manager.enabled = progress < 0.8

func _transition_to_animation(progress: float):
	"""Smooth transition from ragdoll to animation"""
	transition_progress = 1.0 - progress
	
	if physics_ragdoll:
		if progress < 0.5:
			physics_ragdoll.disable_ragdoll()
		
		# Gradually increase IK influence
		var manager = get_parent()
		if manager:
			manager.enabled = progress < 0.3

func _complete_ragdoll_transition():
	"""Finalize ragdoll activation"""
	_change_state(RagdollState.RAGDOLL)
	
	var manager = get_parent()
	if manager:
		manager.enabled = false

func _complete_animation_transition():
	"""Finalize return to animation"""
	_change_state(RagdollState.ANIMATED)
	
	var manager = get_parent()
	if manager:
		manager.enabled = true

func _change_state(new_state: RagdollState):
	"""Change ragdoll state and emit signal"""
	ragdoll_state = new_state
	state_changed.emit(new_state)

## ACTIVE RAGDOLL CONTROL #########################################################
func _physics_process(delta):
	if ragdoll_state == RagdollState.ACTIVE_RAGDOLL:
		_update_active_ragdoll(delta)
	elif ragdoll_state == RagdollState.RAGDOLL and active_ragdoll:
		# Auto-promote to active ragdoll if enabled
		_change_state(RagdollState.ACTIVE_RAGDOLL)

func _update_active_ragdoll(delta):
	"""Update active ragdoll control"""
	if not physics_ragdoll:
		return
	
	# Move ragdoll toward this controller's position
	_apply_position_control()
	
	# Maintain upright orientation if enabled
	if maintain_upright:
		_apply_upright_control()
	
	# Apply target velocity
	if target_velocity.length() > 0:
		_apply_velocity_control()

func _apply_position_control():
	"""Pull ragdoll toward controller position"""
	if not physics_ragdoll.physics_bones.has("Hips"):
		return
		
	var hips_body = physics_ragdoll.physics_bones["Hips"]
	var target_pos = global_transform.origin
	var current_pos = hips_body.global_transform.origin
	
	var direction = (target_pos - current_pos)
	var distance = direction.length()
	
	if distance > 0.1:  # Dead zone
		var force = direction.normalized() * min(distance * control_strength * max_force, max_force)
		hips_body.apply_central_impulse(force * get_physics_process_delta_time())

func _apply_upright_control():
	"""Try to keep ragdoll upright"""
	if not physics_ragdoll.physics_bones.has("Spine"):
		return
		
	var spine_body = physics_ragdoll.physics_bones["Spine"]
	var up_vector = spine_body.global_transform.basis.y
	var world_up = Vector3.UP
	
	var angle = up_vector.angle_to(world_up)
	if angle > deg_to_rad(max_lean_angle):
		var correction_axis = up_vector.cross(world_up).normalized()
		var correction_torque = correction_axis * angle * control_strength * 10.0
		spine_body.apply_torque_impulse(correction_torque * get_physics_process_delta_time())

func _apply_velocity_control():
	"""Apply target velocity to ragdoll"""
	if not physics_ragdoll.physics_bones.has("Hips"):
		return
		
	var hips_body = physics_ragdoll.physics_bones["Hips"]
	var current_velocity = hips_body.linear_velocity
	var velocity_diff = target_velocity - current_velocity
	
	var force = velocity_diff * control_strength * max_force * 0.1
	hips_body.apply_central_impulse(force * get_physics_process_delta_time())

## CONTROL API ####################################################################
func move_to_position(target_pos: Vector3, speed: float = 1.0):
	"""Move controller (and active ragdoll) to position"""
	global_transform.origin = target_pos
	response_speed = speed

func set_target_velocity(velocity: Vector3):
	"""Set desired movement velocity for active ragdoll"""
	target_velocity = velocity

func apply_force_at_position(force: Vector3, world_pos: Vector3):
	"""Apply force to ragdoll at specific world position"""
	if not physics_ragdoll:
		return
		
	var closest_bone = physics_ragdoll.get_closest_bone_to_point(world_pos)
	if closest_bone != "":
		physics_ragdoll.apply_force_to_bone(closest_bone, force, world_pos)

func get_ragdoll_center_of_mass() -> Vector3:
	"""Get approximate center of mass of ragdoll"""
	if not physics_ragdoll or physics_ragdoll.physics_bones.size() == 0:
		return global_transform.origin
		
	var total_mass = 0.0
	var weighted_position = Vector3.ZERO
	
	for bone_name in physics_ragdoll.physics_bones.keys():
		var physics_body = physics_ragdoll.physics_bones[bone_name]
		var mass = physics_body.mass
		total_mass += mass
		weighted_position += physics_body.global_transform.origin * mass
	
	return weighted_position / total_mass if total_mass > 0 else global_transform.origin

func is_ragdoll_stable() -> bool:
	"""Check if ragdoll is in stable state"""
	if not physics_ragdoll:
		return true
		
	return physics_ragdoll.is_ragdoll_stable()

## GAME INTEGRATION HELPERS #######################################################
func handle_damage(damage: float, impact_pos: Vector3, impact_force: Vector3):
	"""Handle damage and potentially activate ragdoll"""
	if damage > 25.0:  # Threshold for ragdoll activation
		var closest_bone = ""
		if physics_ragdoll:
			closest_bone = physics_ragdoll.get_closest_bone_to_point(impact_pos)
		activate_ragdoll(impact_force, closest_bone)

func auto_recover_after_delay(delay: float = 3.0):
	"""Automatically recover from ragdoll after delay"""
	if ragdoll_state == RagdollState.RAGDOLL or ragdoll_state == RagdollState.ACTIVE_RAGDOLL:
		await get_tree().create_timer(delay).timeout
		if is_ragdoll_stable():
			deactivate_ragdoll()

## TARGET FUNCTIONALITY (like other FBIK nodes) ##################################
func get_target() -> Transform3D:
	"""Return target transform (used by FBIK solver if needed)"""
	return global_transform

## DEBUG AND VISUALIZATION ########################################################
func _draw_debug_info():
	"""Draw debug information in editor"""
	if Engine.is_editor_hint() and ragdoll_state != RagdollState.ANIMATED:
		# Could add debug visualization here
		pass
