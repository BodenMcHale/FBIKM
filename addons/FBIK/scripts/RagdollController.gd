# RagdollController.gd
# High-level controller for transitioning between animation and ragdoll states
extends Node
class_name RagdollController

@export var physics_ragdoll: PhysicsRagdoll
@export var fbikm_manager: Node
@export var transition_time: float = 0.5

var ragdoll_state: RagdollState = RagdollState.ANIMATED
var transition_tween: Tween

enum RagdollState {
	ANIMATED,    # FBIKM drives everything
	RAGDOLL,     # Physics drives everything  
	TRANSITIONING # Blending between the two
}

signal ragdoll_state_changed(new_state: RagdollState)

func _ready():
	if not physics_ragdoll:
		physics_ragdoll = get_parent().get_node("PhysicsRagdoll")
	if not fbikm_manager:
		fbikm_manager = get_parent().get_node("KinematicsManager")

# Public API for game systems
func activate_ragdoll(impact_force: Vector3 = Vector3.ZERO, impact_bone: String = ""):
	"""Transition from animation to ragdoll physics"""
	if ragdoll_state == RagdollState.RAGDOLL:
		return
		
	_change_state(RagdollState.TRANSITIONING)
	
	# Apply impact force if provided
	if impact_force != Vector3.ZERO and impact_bone != "":
		physics_ragdoll.apply_force_to_bone(impact_bone, impact_force)
	
	# Smooth transition
	if transition_tween:
		transition_tween.kill()
	
	transition_tween = create_tween()
	transition_tween.tween_method(_blend_to_ragdoll, 0.0, 1.0, transition_time)
	transition_tween.tween_callback(_complete_ragdoll_transition)

func deactivate_ragdoll():
	"""Transition from ragdoll back to animation"""
	if ragdoll_state == RagdollState.ANIMATED:
		return
		
	_change_state(RagdollState.TRANSITIONING)
	
	if transition_tween:
		transition_tween.kill()
	
	transition_tween = create_tween()
	transition_tween.tween_method(_blend_to_animation, 1.0, 0.0, transition_time)
	transition_tween.tween_callback(_complete_animation_transition)

func _blend_to_ragdoll(blend_factor: float):
	"""Smoothly blend from animation to ragdoll"""
	# Reduce FBIKM influence
	if fbikm_manager:
		fbikm_manager.enabled = true  # Keep solving but reduce influence
		
	# Gradually unfreeze physics bodies
	var physics_strength = blend_factor
	for physics_body in physics_ragdoll.physics_bones.values():
		if blend_factor > 0.5:
			physics_body.freeze = false
			physics_body.freeze_mode = RigidBody3D.FREEZE_MODE_STATIC

func _blend_to_animation(blend_factor: float):
	"""Smoothly blend from ragdoll back to animation"""
	# Gradually increase FBIKM influence and reduce physics
	if blend_factor < 0.5:
		for physics_body in physics_ragdoll.physics_bones.values():
			physics_body.freeze = true
			physics_body.freeze_mode = RigidBody3D.FREEZE_MODE_KINEMATIC

func _complete_ragdoll_transition():
	physics_ragdoll.enable_ragdoll()
	if fbikm_manager:
		fbikm_manager.enabled = false
	_change_state(RagdollState.RAGDOLL)

func _complete_animation_transition():
	physics_ragdoll.disable_ragdoll()
	if fbikm_manager:
		fbikm_manager.enabled = true
	_change_state(RagdollState.ANIMATED)

func _change_state(new_state: RagdollState):
	ragdoll_state = new_state
	ragdoll_state_changed.emit(new_state)

# Game integration helpers
func handle_damage(damage_amount: float, impact_point: Vector3, impact_force: Vector3):
	"""Handle damage and potentially trigger ragdoll"""
	if damage_amount > 50.0:  # High damage triggers ragdoll
		var closest_bone = _find_closest_bone_to_point(impact_point)
		activate_ragdoll(impact_force, closest_bone)

func _find_closest_bone_to_point(point: Vector3) -> String:
	"""Find the physics bone closest to a world position"""
	var closest_bone = ""
	var closest_distance = INF
	
	for bone_name in physics_ragdoll.physics_bones.keys():
		var physics_body = physics_ragdoll.physics_bones[bone_name]
		var distance = physics_body.global_position.distance_to(point)
		if distance < closest_distance:
			closest_distance = distance
			closest_bone = bone_name
	
	return closest_bone

func is_stable() -> bool:
	"""Check if character is in a stable state"""
	if ragdoll_state == RagdollState.ANIMATED:
		return true
	elif ragdoll_state == RagdollState.RAGDOLL:
		return physics_ragdoll.is_ragdoll_stable()
	else:
		return false

# Auto-recovery system
func _physics_process(delta):
	if ragdoll_state == RagdollState.RAGDOLL:
		# Auto-recover after ragdoll settles
		if physics_ragdoll.is_ragdoll_stable():
			await get_tree().create_timer(2.0).timeout
			if ragdoll_state == RagdollState.RAGDOLL:  # Still ragdolled
				deactivate_ragdoll()
