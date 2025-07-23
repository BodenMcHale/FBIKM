# PhysicsRagdoll.gd
# Bridges FBIKM virtual skeleton with physics simulation
extends Node3D
class_name PhysicsRagdoll

@export var skeleton_path: NodePath
@export var fbikm_manager_path: NodePath
@export var ragdoll_enabled: bool = false
@export var physics_strength: float = 1.0
@export var damping: float = 0.8

# Physics bodies for each bone
var physics_bones: Dictionary = {}
var bone_joints: Dictionary = {}
var skeleton: Skeleton3D
var fbikm_manager: Node

# Bone mapping for common humanoid skeleton
var bone_physics_map = {
	"Hips": {"mass": 10.0, "size": Vector3(0.3, 0.2, 0.2)},
	"Spine": {"mass": 8.0, "size": Vector3(0.25, 0.3, 0.15)},
	"Head": {"mass": 5.0, "size": Vector3(0.15, 0.2, 0.15)},
	"LeftUpperArm": {"mass": 3.0, "size": Vector3(0.08, 0.25, 0.08)},
	"LeftLowerArm": {"mass": 2.0, "size": Vector3(0.06, 0.2, 0.06)},
	"RightUpperArm": {"mass": 3.0, "size": Vector3(0.08, 0.25, 0.08)},
	"RightLowerArm": {"mass": 2.0, "size": Vector3(0.06, 0.2, 0.06)},
	"LeftUpperLeg": {"mass": 6.0, "size": Vector3(0.12, 0.35, 0.12)},
	"LeftLowerLeg": {"mass": 4.0, "size": Vector3(0.08, 0.3, 0.08)},
	"RightUpperLeg": {"mass": 6.0, "size": Vector3(0.12, 0.35, 0.12)},
	"RightLowerLeg": {"mass": 4.0, "size": Vector3(0.08, 0.3, 0.08)}
}

func _ready():
	skeleton = get_node(skeleton_path) if skeleton_path else null
	fbikm_manager = get_node(fbikm_manager_path) if fbikm_manager_path else null
	
	if not skeleton or not fbikm_manager:
		push_error("PhysicsRagdoll: Missing skeleton or FBIKM manager")
		return
	
	_setup_physics_bones()
	_setup_bone_joints()

func _setup_physics_bones():
	"""Create physics bodies for each bone"""
	for bone_name in bone_physics_map.keys():
		var bone_idx = skeleton.find_bone(bone_name)
		if bone_idx == -1:
			continue
			
		var physics_body = _create_physics_bone(bone_name, bone_idx)
		physics_bones[bone_name] = physics_body
		add_child(physics_body)

func _create_physics_bone(bone_name: String, bone_idx: int) -> RigidBody3D:
	"""Create a single physics bone"""
	var rigid_body = RigidBody3D.new()
	rigid_body.name = "Physics_" + bone_name
	
	# Set up collision shape
	var collision_shape = CollisionShape3D.new()
	var box_shape = BoxShape3D.new()
	box_shape.size = bone_physics_map[bone_name]["size"]
	collision_shape.shape = box_shape
	rigid_body.add_child(collision_shape)
	
	# Set physics properties
	rigid_body.mass = bone_physics_map[bone_name]["mass"]
	rigid_body.linear_damp = damping
	rigid_body.angular_damp = damping
	
	# Position at bone location
	var bone_pose = skeleton.get_bone_global_pose(bone_idx)
	rigid_body.global_transform = skeleton.global_transform * bone_pose
	
	# Initially kinematic (FBIKM controlled)
	rigid_body.freeze_mode = RigidBody3D.FREEZE_MODE_KINEMATIC
	rigid_body.freeze = true
	
	return rigid_body

func _setup_bone_joints():
	"""Create joints between physics bones"""
	var joint_connections = [
		["Hips", "Spine"],
		["Spine", "Head"],
		["Spine", "LeftUpperArm"],
		["LeftUpperArm", "LeftLowerArm"],
		["Spine", "RightUpperArm"], 
		["RightUpperArm", "RightLowerArm"],
		["Hips", "LeftUpperLeg"],
		["LeftUpperLeg", "LeftLowerLeg"],
		["Hips", "RightUpperLeg"],
		["RightUpperLeg", "RightLowerLeg"]
	]
	
	for connection in joint_connections:
		var parent_name = connection[0]
		var child_name = connection[1]
		
		if not physics_bones.has(parent_name) or not physics_bones.has(child_name):
			continue
			
		var joint = _create_bone_joint(parent_name, child_name)
		if joint:
			bone_joints[parent_name + "_" + child_name] = joint
			add_child(joint)

func _create_bone_joint(parent_name: String, child_name: String) -> Generic6DOFJoint3D:
	"""Create a joint between two physics bones"""
	var joint = Generic6DOFJoint3D.new()
	joint.name = "Joint_" + parent_name + "_" + child_name
	
	var parent_body = physics_bones[parent_name]
	var child_body = physics_bones[child_name]
	
	joint.node_a = parent_body.get_path()
	joint.node_b = child_body.get_path()
	
	# Set up joint limits (adjust based on bone type)
	_configure_joint_limits(joint, parent_name, child_name)
	
	return joint

func _configure_joint_limits(joint: Generic6DOFJoint3D, parent_name: String, child_name: String):
	"""Configure realistic joint movement limits"""
	# Basic configuration - customize per joint type
	for axis in range(3):
		joint.set_flag_x(Generic6DOFJoint3D.FLAG_ENABLE_LINEAR_LIMIT, true)
		joint.set_flag_y(Generic6DOFJoint3D.FLAG_ENABLE_LINEAR_LIMIT, true)
		joint.set_flag_z(Generic6DOFJoint3D.FLAG_ENABLE_LINEAR_LIMIT, true)
		
		# Tight linear limits
		joint.set_param_x(Generic6DOFJoint3D.PARAM_LINEAR_UPPER_LIMIT, 0.05)
		joint.set_param_x(Generic6DOFJoint3D.PARAM_LINEAR_LOWER_LIMIT, -0.05)
		joint.set_param_y(Generic6DOFJoint3D.PARAM_LINEAR_UPPER_LIMIT, 0.05)
		joint.set_param_y(Generic6DOFJoint3D.PARAM_LINEAR_LOWER_LIMIT, -0.05)
		joint.set_param_z(Generic6DOFJoint3D.PARAM_LINEAR_UPPER_LIMIT, 0.05)
		joint.set_param_z(Generic6DOFJoint3D.PARAM_LINEAR_LOWER_LIMIT, -0.05)

func _physics_process(delta):
	if not ragdoll_enabled:
		_update_physics_from_fbikm()
	else:
		_update_skeleton_from_physics()

func _update_physics_from_fbikm():
	"""Update physics bodies to match FBIKM virtual skeleton"""
	if not fbikm_manager or not skeleton:
		return
		
	# Get virtual skeleton from FBIKM
	var virt_skel = fbikm_manager.get("virt_skel")
	if not virt_skel:
		return
	
	for bone_name in physics_bones.keys():
		var bone_idx = skeleton.find_bone(bone_name)
		if bone_idx == -1:
			continue
			
		var physics_body = physics_bones[bone_name]
		
		# Get bone transform from FBIKM virtual skeleton
		var bone_id = str(bone_idx)
		if virt_skel.has_bone(bone_id):
			var virt_pos = virt_skel.get_bone_position(bone_id)
			var virt_rot = virt_skel.get_bone_rotation(bone_id)
			
			# Apply to physics body
			var target_transform = Transform3D(Basis(virt_rot), virt_pos)
			physics_body.global_transform = skeleton.global_transform * target_transform

func _update_skeleton_from_physics():
	"""Update skeleton to match physics bodies (ragdoll mode)"""
	for bone_name in physics_bones.keys():
		var bone_idx = skeleton.find_bone(bone_name)
		if bone_idx == -1:
			continue
			
		var physics_body = physics_bones[bone_name]
		var local_transform = skeleton.global_transform.inverse() * physics_body.global_transform
		
		# Apply to skeleton
		skeleton.set_bone_global_pose_override(bone_idx, local_transform, 1.0, true)

func enable_ragdoll():
	"""Switch to physics-driven ragdoll mode"""
	ragdoll_enabled = true
	
	# Unfreeze all physics bodies
	for physics_body in physics_bones.values():
		physics_body.freeze = false
		physics_body.freeze_mode = RigidBody3D.FREEZE_MODE_STATIC

func disable_ragdoll():
	"""Switch back to FBIKM-driven mode"""
	ragdoll_enabled = false
	
	# Freeze all physics bodies
	for physics_body in physics_bones.values():
		physics_body.freeze = true
		physics_body.freeze_mode = RigidBody3D.FREEZE_MODE_KINEMATIC

func apply_force_to_bone(bone_name: String, force: Vector3, position: Vector3 = Vector3.ZERO):
	"""Apply physics force to a specific bone"""
	if physics_bones.has(bone_name):
		var physics_body = physics_bones[bone_name]
		if position == Vector3.ZERO:
			physics_body.apply_central_force(force)
		else:
			physics_body.apply_force(force, position)

# Utility functions for game integration
func get_bone_velocity(bone_name: String) -> Vector3:
	if physics_bones.has(bone_name):
		return physics_bones[bone_name].linear_velocity
	return Vector3.ZERO

func is_ragdoll_stable() -> bool:
	"""Check if ragdoll has settled (low velocities)"""
	var total_velocity = 0.0
	for physics_body in physics_bones.values():
		total_velocity += physics_body.linear_velocity.length()
	return total_velocity < 1.0
