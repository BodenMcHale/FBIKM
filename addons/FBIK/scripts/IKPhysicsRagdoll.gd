@tool
extends Node
const FBIKM_NODE_ID = 10  # THIS NODE'S IDENTIFIER

"""
		FBIKM - Physics Ragdoll
				by Nemo Czanderlitch/Nino Čandrlić
						@R3X-G1L       (godot assets store)
						R3X-G1L6AME5H  (github)
		Creates physics bodies for each bone, allowing for full physics simulation
		of the character. Can be toggled between kinematic (IK-driven) and 
		dynamic (physics-driven) modes.
"""

# Physics bodies for each bone
var physics_bones: Dictionary = {}
var bone_joints: Dictionary = {}
var ragdoll_enabled: bool = false

# Physics properties
@export var auto_create_bodies: bool = true
@export_range(0.1, 10.0) var global_mass_multiplier: float = 1.0
@export_range(0.0, 1.0) var linear_damping: float = 0.8
@export_range(0.0, 1.0) var angular_damping: float = 0.8
@export_range(0.0, 1.0) var physics_strength: float = 1.0

# Bone physics configuration
var bone_physics_map = {
	"Hips": {"mass": 10.0, "size": Vector3(0.3, 0.2, 0.2), "type": "box"},
	"Spine": {"mass": 8.0, "size": Vector3(0.25, 0.3, 0.15), "type": "box"},
	"Spine1": {"mass": 6.0, "size": Vector3(0.2, 0.25, 0.12), "type": "box"},
	"Spine2": {"mass": 5.0, "size": Vector3(0.18, 0.2, 0.1), "type": "box"},
	"Neck": {"mass": 2.0, "size": Vector3(0.08, 0.15, 0.08), "type": "capsule"},
	"Head": {"mass": 5.0, "size": Vector3(0.15, 0.2, 0.15), "type": "sphere"},
	
	# Arms
	"LeftShoulder": {"mass": 2.0, "size": Vector3(0.1, 0.1, 0.1), "type": "sphere"},
	"LeftUpperArm": {"mass": 3.0, "size": Vector3(0.08, 0.25, 0.08), "type": "capsule"},
	"LeftLowerArm": {"mass": 2.0, "size": Vector3(0.06, 0.2, 0.06), "type": "capsule"},
	"LeftHand": {"mass": 0.5, "size": Vector3(0.05, 0.08, 0.02), "type": "box"},
	
	"RightShoulder": {"mass": 2.0, "size": Vector3(0.1, 0.1, 0.1), "type": "sphere"},
	"RightUpperArm": {"mass": 3.0, "size": Vector3(0.08, 0.25, 0.08), "type": "capsule"},
	"RightLowerArm": {"mass": 2.0, "size": Vector3(0.06, 0.2, 0.06), "type": "capsule"},
	"RightHand": {"mass": 0.5, "size": Vector3(0.05, 0.08, 0.02), "type": "box"},
	
	# Legs  
	"LeftUpperLeg": {"mass": 6.0, "size": Vector3(0.12, 0.35, 0.12), "type": "capsule"},
	"LeftLowerLeg": {"mass": 4.0, "size": Vector3(0.08, 0.3, 0.08), "type": "capsule"},
	"LeftFoot": {"mass": 1.0, "size": Vector3(0.08, 0.05, 0.2), "type": "box"},
	
	"RightUpperLeg": {"mass": 6.0, "size": Vector3(0.12, 0.35, 0.12), "type": "capsule"},
	"RightLowerLeg": {"mass": 4.0, "size": Vector3(0.08, 0.3, 0.08), "type": "capsule"},
	"RightFoot": {"mass": 1.0, "size": Vector3(0.08, 0.05, 0.2), "type": "box"}
}

# Joint connections (parent -> child)
var joint_connections = [
	["Hips", "Spine"],
	["Spine", "Spine1"],
	["Spine1", "Spine2"], 
	["Spine2", "Neck"],
	["Neck", "Head"],
	
	["Spine2", "LeftShoulder"],
	["LeftShoulder", "LeftUpperArm"],
	["LeftUpperArm", "LeftLowerArm"],
	["LeftLowerArm", "LeftHand"],
	
	["Spine2", "RightShoulder"],
	["RightShoulder", "RightUpperArm"],
	["RightUpperArm", "RightLowerArm"],
	["RightLowerArm", "RightHand"],
	
	["Hips", "LeftUpperLeg"],
	["LeftUpperLeg", "LeftLowerLeg"],
	["LeftLowerLeg", "LeftFoot"],
	
	["Hips", "RightUpperLeg"],
	["RightUpperLeg", "RightLowerLeg"],
	["RightLowerLeg", "RightFoot"]
]

## BOILERPLATE FOR DROPDOWN MENU ##
var _bone_names = "VOID:-1"

## INIT ###########################################################################
func _ready():
	if Engine.is_editor_hint():
		if get_parent().get("FBIKM_NODE_ID") == 0:  ## This is KinematicsManager's ID
			get_parent().connect("bone_names_obtained", _update_parameters)
			if auto_create_bodies:
				await get_tree().process_frame  # Wait for skeleton setup
				_setup_physics_bodies()

func _update_parameters(bone_names: String) -> void:
	_bone_names = bone_names
	notify_property_list_changed()

func _setup_physics_bodies():
	"""Create physics bodies for skeleton bones"""
	var manager = get_parent()
	if not manager or not manager.has_method("get_node_or_null"):
		return
		
	var skeleton = manager.get_node_or_null(manager.skeleton)
	if not skeleton:
		return
		
	# Create physics bodies for each configured bone
	for bone_name in bone_physics_map.keys():
		var bone_idx = skeleton.find_bone(bone_name)
		if bone_idx == -1:
			continue
			
		var physics_body = _create_physics_bone(bone_name, bone_idx, skeleton)
		if physics_body:
			physics_bones[bone_name] = physics_body
			add_child(physics_body)
	
	# Create joints between connected bones
	_setup_bone_joints()

func _create_physics_bone(bone_name: String, bone_idx: int, skeleton: Skeleton3D) -> RigidBody3D:
	"""Create a single physics bone with appropriate shape"""
	var rigid_body = RigidBody3D.new()
	rigid_body.name = "Physics_" + bone_name
	
	# Get bone configuration
	var bone_config = bone_physics_map[bone_name]
	
	# Create collision shape based on type
	var collision_shape = CollisionShape3D.new()
	var shape = _create_shape_for_bone(bone_config)
	collision_shape.shape = shape
	rigid_body.add_child(collision_shape)
	
	# Set physics properties
	rigid_body.mass = bone_config["mass"] * global_mass_multiplier
	rigid_body.linear_damp = linear_damping
	rigid_body.angular_damp = angular_damping
	
	# Position at bone location
	var bone_pose = skeleton.get_bone_global_pose(bone_idx)
	rigid_body.transform = skeleton.global_transform * bone_pose
	
	# Start as kinematic (IK controlled)
	rigid_body.freeze_mode = RigidBody3D.FREEZE_MODE_KINEMATIC
	rigid_body.freeze = true
	
	return rigid_body

func _create_shape_for_bone(bone_config: Dictionary) -> Shape3D:
	"""Create appropriate collision shape for bone type"""
	var size = bone_config["size"]
	var type = bone_config.get("type", "box")
	
	match type:
		"box":
			var box_shape = BoxShape3D.new()
			box_shape.size = size
			return box_shape
		"sphere":
			var sphere_shape = SphereShape3D.new()
			sphere_shape.radius = size.x * 0.5
			return sphere_shape
		"capsule":
			var capsule_shape = CapsuleShape3D.new()
			capsule_shape.radius = size.x * 0.5
			capsule_shape.height = size.y
			return capsule_shape
		_:
			var box_shape = BoxShape3D.new()
			box_shape.size = size
			return box_shape

func _setup_bone_joints():
	"""Create joints between connected physics bones"""
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
	"""Create a realistic joint between two bones"""
	var joint = Generic6DOFJoint3D.new()
	joint.name = "Joint_" + parent_name + "_" + child_name
	
	var parent_body = physics_bones[parent_name]
	var child_body = physics_bones[child_name]
	
	joint.node_a = parent_body.get_path()
	joint.node_b = child_body.get_path()
	
	# Configure joint limits based on bone types
	_configure_joint_for_bones(joint, parent_name, child_name)
	
	return joint

func _configure_joint_for_bones(joint: Generic6DOFJoint3D, parent_name: String, child_name: String):
	"""Configure joint limits based on anatomical constraints"""
	# Linear limits (keep bones connected)
	joint.set_flag_x(Generic6DOFJoint3D.FLAG_ENABLE_LINEAR_LIMIT, true)
	joint.set_flag_y(Generic6DOFJoint3D.FLAG_ENABLE_LINEAR_LIMIT, true)
	joint.set_flag_z(Generic6DOFJoint3D.FLAG_ENABLE_LINEAR_LIMIT, true)
	
	joint.set_param_x(Generic6DOFJoint3D.PARAM_LINEAR_UPPER_LIMIT, 0.02)
	joint.set_param_x(Generic6DOFJoint3D.PARAM_LINEAR_LOWER_LIMIT, -0.02)
	joint.set_param_y(Generic6DOFJoint3D.PARAM_LINEAR_UPPER_LIMIT, 0.02)
	joint.set_param_y(Generic6DOFJoint3D.PARAM_LINEAR_LOWER_LIMIT, -0.02)
	joint.set_param_z(Generic6DOFJoint3D.PARAM_LINEAR_UPPER_LIMIT, 0.02)
	joint.set_param_z(Generic6DOFJoint3D.PARAM_LINEAR_LOWER_LIMIT, -0.02)
	
	# Angular limits (anatomical movement)
	var is_spine = "Spine" in parent_name or "Spine" in child_name
	var is_limb = ("Arm" in parent_name or "Leg" in parent_name)
	
	if is_spine:
		# Spine joints: limited rotation
		joint.set_flag_x(Generic6DOFJoint3D.FLAG_ENABLE_ANGULAR_LIMIT, true)
		joint.set_flag_y(Generic6DOFJoint3D.FLAG_ENABLE_ANGULAR_LIMIT, true)
		joint.set_flag_z(Generic6DOFJoint3D.FLAG_ENABLE_ANGULAR_LIMIT, true)
		
		joint.set_param_x(Generic6DOFJoint3D.PARAM_ANGULAR_UPPER_LIMIT, deg_to_rad(30))
		joint.set_param_x(Generic6DOFJoint3D.PARAM_ANGULAR_LOWER_LIMIT, deg_to_rad(-30))
		joint.set_param_y(Generic6DOFJoint3D.PARAM_ANGULAR_UPPER_LIMIT, deg_to_rad(30))
		joint.set_param_y(Generic6DOFJoint3D.PARAM_ANGULAR_LOWER_LIMIT, deg_to_rad(-30))
		joint.set_param_z(Generic6DOFJoint3D.PARAM_ANGULAR_UPPER_LIMIT, deg_to_rad(30))
		joint.set_param_z(Generic6DOFJoint3D.PARAM_ANGULAR_LOWER_LIMIT, deg_to_rad(-30))
	elif is_limb:
		# Limb joints: more freedom
		joint.set_flag_x(Generic6DOFJoint3D.FLAG_ENABLE_ANGULAR_LIMIT, true)
		joint.set_flag_y(Generic6DOFJoint3D.FLAG_ENABLE_ANGULAR_LIMIT, true)
		joint.set_flag_z(Generic6DOFJoint3D.FLAG_ENABLE_ANGULAR_LIMIT, true)
		
		joint.set_param_x(Generic6DOFJoint3D.PARAM_ANGULAR_UPPER_LIMIT, deg_to_rad(90))
		joint.set_param_x(Generic6DOFJoint3D.PARAM_ANGULAR_LOWER_LIMIT, deg_to_rad(-90))
		joint.set_param_y(Generic6DOFJoint3D.PARAM_ANGULAR_UPPER_LIMIT, deg_to_rad(90))
		joint.set_param_y(Generic6DOFJoint3D.PARAM_ANGULAR_LOWER_LIMIT, deg_to_rad(-90))
		joint.set_param_z(Generic6DOFJoint3D.PARAM_ANGULAR_UPPER_LIMIT, deg_to_rad(90))
		joint.set_param_z(Generic6DOFJoint3D.PARAM_ANGULAR_LOWER_LIMIT, deg_to_rad(-90))

## RAGDOLL CONTROL ################################################################
func enable_ragdoll():
	"""Switch to physics-driven mode"""
	ragdoll_enabled = true
	for physics_body in physics_bones.values():
		physics_body.freeze = false

func disable_ragdoll():
	"""Switch to IK-driven mode"""
	ragdoll_enabled = false
	for physics_body in physics_bones.values():
		physics_body.freeze = true

func apply_force_to_bone(bone_name: String, force: Vector3, position: Vector3 = Vector3.ZERO):
	"""Apply force to specific bone"""
	if physics_bones.has(bone_name):
		var physics_body = physics_bones[bone_name]
		if position == Vector3.ZERO:
			physics_body.apply_central_impulse(force)
		else:
			physics_body.apply_impulse(force, position)

func get_bone_velocity(bone_name: String) -> Vector3:
	"""Get bone's current velocity"""
	if physics_bones.has(bone_name):
		return physics_bones[bone_name].linear_velocity
	return Vector3.ZERO

func is_ragdoll_stable() -> bool:
	"""Check if ragdoll has settled"""
	var total_velocity = 0.0
	for physics_body in physics_bones.values():
		total_velocity += physics_body.linear_velocity.length()
	return total_velocity < 2.0

## INTEGRATION WITH FBIKM ########################################################
func update_from_virtual_skeleton(virt_skel):
	"""Update physics bodies from FBIKM virtual skeleton"""
	if ragdoll_enabled:
		return  # Don't override physics when ragdolling
		
	var manager = get_parent()
	var skeleton = manager.get_node_or_null(manager.skeleton)
	if not skeleton or not virt_skel:
		return
	
	for bone_name in physics_bones.keys():
		var bone_idx = skeleton.find_bone(bone_name)
		if bone_idx == -1:
			continue
			
		var physics_body = physics_bones[bone_name]
		var bone_id = str(bone_idx)
		
		if virt_skel.has_bone(bone_id):
			var virt_pos = virt_skel.get_bone_position(bone_id)
			var virt_rot = virt_skel.get_bone_rotation(bone_id)
			
			var target_transform = Transform3D(Basis(virt_rot), virt_pos)
			physics_body.global_transform = skeleton.global_transform * target_transform

func update_virtual_skeleton_from_physics(virt_skel):
	"""Update virtual skeleton from physics bodies"""
	if not ragdoll_enabled:
		return
		
	var manager = get_parent()
	var skeleton = manager.get_node_or_null(manager.skeleton)
	if not skeleton or not virt_skel:
		return
	
	for bone_name in physics_bones.keys():
		var bone_idx = skeleton.find_bone(bone_name)
		if bone_idx == -1:
			continue
			
		var physics_body = physics_bones[bone_name]
		var local_transform = skeleton.global_transform.affine_inverse() * physics_body.global_transform
		
		var bone_id = str(bone_idx)
		if virt_skel.has_bone(bone_id):
			virt_skel.set_bone_position(bone_id, local_transform.origin)
			virt_skel.set_bone_rotation(bone_id, local_transform.basis.get_rotation_quaternion())

## UTILITY FUNCTIONS ##############################################################
func get_closest_bone_to_point(point: Vector3) -> String:
	"""Find physics bone closest to world position"""
	var closest_bone = ""
	var closest_distance = INF
	
	for bone_name in physics_bones.keys():
		var physics_body = physics_bones[bone_name]
		var distance = physics_body.global_transform.origin.distance_to(point)
		if distance < closest_distance:
			closest_distance = distance
			closest_bone = bone_name
	
	return closest_bone

func set_bone_kinematic(bone_name: String, kinematic: bool):
	"""Set specific bone to kinematic or dynamic"""
	if physics_bones.has(bone_name):
		var physics_body = physics_bones[bone_name]
		physics_body.freeze = kinematic
