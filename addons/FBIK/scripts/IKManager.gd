@tool
extends Node

## Simplified FBIK Manager for Godot 4.x
## Based on Lost-Rabbit-Digital/FBIKM but streamlined

const FBIKM_NODE_ID = 0

## Core references
@export var skeleton_path: NodePath
@export var enabled: bool = false : set = _set_enabled
@export var max_iterations: int = 5
@export var tolerance: float = 0.01

var skeleton: Skeleton3D
var bone_data: Dictionary = {}
var chains: Array[Node] = []
var lookats: Array[Node] = []
var poles: Array[Node] = []

signal bone_names_updated(bone_names: String)

func _ready():
	if Engine.is_editor_hint():
		_setup_editor_environment()
	else:
		_setup_runtime_environment()

func _setup_editor_environment():
	if skeleton_path:
		_update_skeleton_reference()

func _setup_runtime_environment():
	if skeleton_path:
		_update_skeleton_reference()
		_collect_ik_nodes()

func _set_enabled(value: bool):
	enabled = value
	if not enabled and skeleton:
		skeleton.clear_bones_global_pose_override()

func _update_skeleton_reference():
	var skel_node = get_node_or_null(skeleton_path)
	if skel_node and skel_node is Skeleton3D:
		skeleton = skel_node
		_build_bone_data()
		_emit_bone_names()
	else:
		skeleton = null
		bone_data.clear()

func _build_bone_data():
	if not skeleton:
		return
		
	bone_data.clear()
	
	for i in range(skeleton.get_bone_count()):
		var bone_id = str(i)
		var parent_id = str(skeleton.get_bone_parent(i)) if skeleton.get_bone_parent(i) >= 0 else "-1"
		var pose = skeleton.get_bone_global_pose(i)
		
		bone_data[bone_id] = {
			"parent": parent_id,
			"children": [],
			"position": pose.origin,
			"rotation": pose.basis.get_rotation_quaternion(),
			"start_position": pose.origin,
			"start_rotation": pose.basis.get_rotation_quaternion(),
			"length": 0.0
		}
	
	# Build parent-child relationships and calculate bone lengths
	for bone_id in bone_data.keys():
		var parent_id = bone_data[bone_id].parent
		if parent_id != "-1" and bone_data.has(parent_id):
			bone_data[parent_id].children.append(bone_id)
			var length = bone_data[bone_id].position.distance_to(bone_data[parent_id].position)
			bone_data[bone_id].length = length

func _emit_bone_names():
	if not skeleton:
		return
		
	var bone_names = "NONE:-1"
	for i in range(skeleton.get_bone_count()):
		bone_names += "," + skeleton.get_bone_name(i) + ":" + str(i)
	
	bone_names_updated.emit(bone_names)

func _collect_ik_nodes():
	chains.clear()
	lookats.clear()
	poles.clear()
	
	for child in get_children():
		if child.has_method("get_fbik_type"):
			match child.get_fbik_type():
				"chain":
					chains.append(child)
				"lookat":
					lookats.append(child)
				"pole":
					poles.append(child)

func _physics_process(_delta):
	if enabled and skeleton and not bone_data.is_empty():
		_solve_ik()

func _solve_ik():
	if chains.is_empty():
		return
		
	var global_transform_inv = skeleton.global_transform.affine_inverse()
	
	# Apply LookAt constraints first
	_solve_lookats(global_transform_inv)
	
	# Apply Pole constraints to chains
	_apply_pole_constraints(global_transform_inv)
	
	# FABRIK algorithm implementation
	for iteration in range(max_iterations):
		var total_error = 0.0
		
		# Backward pass - move from tip toward target
		for chain in chains:
			if chain.has_method("get_target_position") and chain.has_method("get_tip_bone") and chain.has_method("get_root_bone"):
				var target_pos = global_transform_inv * chain.get_target_position()
				var tip_bone = chain.get_tip_bone()
				var root_bone = chain.get_root_bone()
				
				if bone_data.has(tip_bone):
					var error = bone_data[tip_bone].position.distance_to(target_pos)
					total_error += error
					
					if error > tolerance:
						_solve_backward(tip_bone, root_bone, target_pos)
		
		# Forward pass - restore bone lengths from root
		_solve_forward()
		
		# Check convergence
		if total_error < tolerance:
			break
	
	# Apply results to skeleton
	_apply_to_skeleton()

func _solve_backward(tip_bone: String, root_bone: String, target_pos: Vector3):
	var current_bone = tip_bone
	var current_target = target_pos
	
	# Move tip to target
	bone_data[current_bone].position = current_target
	
	# Work backward through the chain
	while current_bone != root_bone and bone_data.has(current_bone):
		var parent = bone_data[current_bone].parent
		if parent == "-1" or not bone_data.has(parent):
			break
			
		var bone_length = bone_data[current_bone].length
		var direction = (bone_data[parent].position - bone_data[current_bone].position).normalized()
		current_target = bone_data[current_bone].position + direction * bone_length
		
		bone_data[parent].position = current_target
		current_bone = parent

func _solve_forward():
	# Start from root bones and maintain bone lengths
	for bone_id in bone_data.keys():
		if bone_data[bone_id].parent == "-1":  # Root bone
			_solve_forward_recursive(bone_id)

func _solve_forward_recursive(bone_id: String):
	var bone = bone_data[bone_id]
	
	for child_id in bone.children:
		if bone_data.has(child_id):
			var child = bone_data[child_id]
			var direction = (child.position - bone.position).normalized()
			child.position = bone.position + direction * child.length
			_solve_forward_recursive(child_id)

func _apply_to_skeleton():
	for bone_id in bone_data.keys():
		var bone = bone_data[bone_id]
		var new_transform = Transform3D()
		new_transform.origin = bone.position
		new_transform.basis = Basis(bone.rotation)
		
		skeleton.set_bone_global_pose_override(int(bone_id), new_transform, 1.0, true)

## Utility functions for child nodes
func get_bone_names() -> String:
	if not skeleton:
		return "NONE:-1"
		
	var names = "NONE:-1"
	for i in range(skeleton.get_bone_count()):
		names += "," + skeleton.get_bone_name(i) + ":" + str(i)
	return names

func has_bone(bone_id: String) -> bool:
	return bone_data.has(bone_id)

func get_bone_position(bone_id: String) -> Vector3:
	if bone_data.has(bone_id):
		return bone_data[bone_id].position
	return Vector3.ZERO

func _solve_lookats(global_transform_inv: Transform3D):
	for lookat in lookats:
		if not lookat.has_method("get_target_bone") or not lookat.has_method("get_target_position"):
			continue
			
		var bone_id = lookat.get_target_bone()
		if not bone_data.has(bone_id):
			continue
			
		var target_pos = global_transform_inv * lookat.get_target_position()
		var bone_pos = bone_data[bone_id].position
		
		# Get parent bone position for proper rotation calculation
		var parent_id = bone_data[bone_id].parent
		if parent_id != "-1" and bone_data.has(parent_id):
			var parent_pos = bone_data[parent_id].position
			var new_rotation = lookat.calculate_look_rotation(parent_pos, target_pos, bone_data[parent_id].rotation)
			bone_data[parent_id].rotation = new_rotation
			
			# Update child bone position based on new parent rotation
			var bone_length = bone_data[bone_id].length
			var direction = (bone_pos - parent_pos).normalized()
			bone_data[bone_id].position = parent_pos + direction * bone_length

func _apply_pole_constraints(global_transform_inv: Transform3D):
	for pole in poles:
		if not pole.has_method("get_tip_bone") or not pole.has_method("get_root_bone"):
			continue
			
		var chain = pole.get_bone_chain(bone_data)
		if chain.size() != 3:  # Need exactly 3 bones for pole constraint
			continue
			
		var bone_positions = []
		var bone_lengths = []
		
		# Get current positions
		for i in range(chain.size()):
			bone_positions.append(bone_data[chain[i]].position)
			
		# Get bone lengths
		for i in range(chain.size() - 1):
			bone_lengths.append(bone_data[chain[i + 1]].length)
		
		# Apply pole constraint
		var pole_pos = global_transform_inv * pole.get_target_position()
		var target_pos = bone_positions[2]  # Keep original target for end effector
		
		var new_positions = pole.apply_pole_constraint(bone_positions, bone_lengths, target_pos, pole_pos)
		
		# Update bone positions
		for i in range(min(chain.size(), new_positions.size())):
			bone_data[chain[i]].position = new_positions[i]
