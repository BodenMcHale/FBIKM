extends RefCounted

"""
		FBIKM - Virtual Skeleton
				by Nemo Czanderlitch/Nino Čandrlić
						@R3X-G1L       (godot assets store)
						R3X-G1L6AME5H  (github)
		This is an higher level representation of the Godot Skeleton Node; it holds more data.
		It stores child bones, thusly allowing for solving branches in the Skeleton.
		Additionally, it holds more rotation data for smoother solutions.
"""

enum MODIFIER {
	NONE = 0,
	BIND = 1,
	FORK_BIND = 2,
	CAGE_BIND = 4,
	SOLID = 8,
	DAMPED_TRANSFORM = 16,
	LOOK_AT = 32
}

var bones := Dictionary()
var skel: Skeleton3D
var roots := PackedStringArray([])

### INIT - Fixed for Godot 4.4.1
func _init(skeleton: Skeleton3D, build_with_initial_transform: bool):
	skel = skeleton
	
	# Ensure skeleton is valid
	if not skeleton or skeleton.get_bone_count() == 0:
		push_error("VirtualSkeleton: Invalid skeleton or no bones found")
		return
	
	# Initialize bones using the correct Godot 4 API
	for id in range(skeleton.get_bone_count()):
		# Use get_bone_pose (local pose) instead of get_bone_global_pose for initialization
		var bone_transform: Transform3D
		
		# Try to get the rest transform first, fall back to pose
		bone_transform = skeleton.get_bone_rest(id)
		
		# Validate transform
		if _is_transform_valid(bone_transform):
			add_bone(str(id), 
						str(skeleton.get_bone_parent(id)),
						bone_transform,
						build_with_initial_transform)
		else:
			print("Warning: Bone ", skeleton.get_bone_name(id), " (ID: ", id, ") has invalid rest transform. Using identity.")
			add_bone(str(id), 
						str(skeleton.get_bone_parent(id)),
						Transform3D.IDENTITY,
						build_with_initial_transform)
	
	# Setup bone hierarchy and directions
	_setup_bone_directions()

# Separate function to set up bone directions after all bones are created
func _setup_bone_directions():
	var bone_queue := PackedStringArray([])
	
	# Start with root bones
	for root in roots:
		var children = self.get_bone_children(root)
		for child in children:
			bone_queue.append(child)
	
	if bone_queue.size() == 0:
		return
		
	var current_bone = bone_queue[0]
	bone_queue = bone_queue.slice(1)
	
	while current_bone != "":
		var num_of_children = self.get_bone_children_count(current_bone)
		
		if num_of_children == 0:
			# Leaf node
			var parent_id = self.get_bone_parent(current_bone)
			if parent_id != "-1" and bones.has(parent_id):
				var direction = bones[current_bone].position - bones[parent_id].position
				bones[current_bone].start_direction = direction.normalized() if direction.length() > 0.001 else Vector3.FORWARD
				bones[current_bone].length = direction.length()
			else:
				bones[current_bone].start_direction = Vector3.FORWARD
			
			if bone_queue.size() == 0:
				break
			
			current_bone = bone_queue[0]
			bone_queue = bone_queue.slice(1)
		else:
			# Branch node
			for child_bone in self.get_bone_children(current_bone):
				bone_queue.push_back(child_bone)
			
			var parent_id = self.get_bone_parent(current_bone)
			if parent_id != "-1" and bones.has(parent_id):
				var direction = bones[current_bone].position - bones[parent_id].position
				bones[current_bone].start_direction = direction.normalized() if direction.length() > 0.001 else Vector3.FORWARD
				bones[current_bone].length = direction.length()
			else:
				bones[current_bone].start_direction = Vector3.FORWARD
				
			if bone_queue.size() > 0:
				current_bone = bone_queue[0]
				bone_queue = bone_queue.slice(1)
			else:
				break

# Safety check for transform validity
func _is_transform_valid(transform: Transform3D) -> bool:
	# Check for NaN or infinite values in origin
	var origin = transform.origin
	if not (is_finite(origin.x) and is_finite(origin.y) and is_finite(origin.z)):
		return false
	
	# Check for NaN or infinite values in basis
	var basis = transform.basis
	for i in range(3):
		var column = basis[i]
		if not (is_finite(column.x) and is_finite(column.y) and is_finite(column.z)):
			return false
	
	# Check if basis determinant is reasonable (not degenerate)
	var det = basis.determinant()
	if not is_finite(det) or abs(det) < 0.0001:
		return false
	
	return true

# Safe quaternion extraction from basis
func _safe_get_rotation_quaternion(basis: Basis) -> Quaternion:
	# First check if basis is valid
	var det = basis.determinant()
	if not is_finite(det) or abs(det) < 0.0001:
		return Quaternion.IDENTITY
	
	# Try to orthonormalize
	var normalized_basis = basis.orthonormalized()
	
	# Get quaternion from normalized basis
	var quat = normalized_basis.get_rotation_quaternion()
	
	# Validate quaternion components
	if not (is_finite(quat.x) and is_finite(quat.y) and is_finite(quat.z) and is_finite(quat.w)):
		return Quaternion.IDENTITY
	
	# Check if quaternion is normalized (should be close to 1)
	var length_sq = quat.length_squared()
	if not is_finite(length_sq) or abs(length_sq - 1.0) > 0.1:
		return Quaternion.IDENTITY
	
	return quat

func add_bone(bone_id: String, parent_id: String, transform: Transform3D, build_with_initial_transform: bool) -> void:
	var direction := Vector3.ZERO
	var preexisting_children := []
	
	# If a parent exists, link them and calculate direction
	if bones.has(parent_id) and parent_id != "-1":
		direction = transform.origin - bones[parent_id].position
		bones[parent_id].children.push_back(bone_id)
	
	# Check if this bone is a parent to any existing nodes
	for bone in bones.keys():
		if bones[bone].parent == bone_id:
			preexisting_children.push_back(bone)
			var child_direction = bones[bone].position - transform.origin
			bones[bone].start_direction = child_direction.normalized() if child_direction.length() > 0.001 else Vector3.FORWARD
			bones[bone].length = child_direction.length()
	
	# Safe rotation extraction
	var safe_rotation = _safe_get_rotation_quaternion(transform.basis)
	
	# Create bone data
	bones[bone_id] = {
		# Tree data
		parent                 = parent_id, 
		children               = preexisting_children,
		# Position data
		position               = transform.origin,
		length                 = direction.length(),
		length_multiplier      = 1.0,
		# Rotation data
		rotation               = safe_rotation,
		start_rotation         = safe_rotation,
		start_direction        = direction.normalized() if direction.length() > 0.001 else Vector3.FORWARD,
		# Solving data
		weighted_vector_sum    = Vector3.ZERO,
		weight_sum             = 0.0,
		# Constraint data
		modifier_flags         = MODIFIER.NONE,
	}
	
	# Store initial transform if requested
	if build_with_initial_transform:
		bones[bone_id].init_tr = transform
	
	# Mark as root if no parent
	if parent_id == "-1":
		roots.push_back(bone_id)
		bones[bone_id].initial_position = transform.origin

func set_bone_modifier(bone_id: String, modifier: int, node = null) -> void:
	if not bones.has(bone_id):
		return
		
	if modifier == MODIFIER.LOOK_AT:
		bones[bone_id].modifier_flags |= MODIFIER.LOOK_AT
	
	elif modifier == MODIFIER.BIND:
		if node != null and bones.has(node.bone_1):
			bones[node.bone_1].modifier_flags |= MODIFIER.BIND
			
			if not bones[node.bone_1].has("bind_ids"):
				bones[node.bone_1].bind_ids = []
			
			bones[node.bone_1].bind_ids.push_back(node.bind_id)
		
	elif modifier == MODIFIER.FORK_BIND:
		if node != null and bones.has(node.bone_1):
			bones[node.bone_1].modifier_flags |= MODIFIER.FORK_BIND
			
			if not bones[node.bone_1].has("fork_bind_ids"):
				bones[node.bone_1].fork_bind_ids = []
			
			bones[node.bone_1].fork_bind_ids.push_back(node.bind_id)
	
	elif modifier == MODIFIER.CAGE_BIND:
		if node != null and bones.has(node.backbone_1):
			bones[node.backbone_1].modifier_flags |= MODIFIER.CAGE_BIND
			bones[node.backbone_1].cage_bind_id = node.bind_id
	
	else:
		# Apply modifier to bone chain
		var bone_queue: PackedStringArray = []
		var current_bone = bone_id
		
		while current_bone != "-1" and bones.has(current_bone):
			# Add children to queue
			for child in bones[current_bone].children:
				bone_queue.push_back(child)
			
			# Apply modifier
			bones[current_bone].modifier_flags |= modifier
			bones[current_bone].modifier_master = bone_id
			
			if modifier & MODIFIER.DAMPED_TRANSFORM and node != null:
				bones[current_bone].velocity = Vector3.ZERO
				update_bone_damped_transform(current_bone, node)
			
			# Move to next bone
			if bone_queue.size() > 0:
				current_bone = bone_queue[0]
				bone_queue = bone_queue.slice(1)
			else:
				break

### WRITE VIRTUAL SKELETON TO REAL SKELETON - Fixed for Godot 4.4.1
func bake() -> void:
	if not skel:
		return
		
	for bone_id in bones.keys():
		var bone_idx = int(bone_id)
		if bone_idx < 0 or bone_idx >= skel.get_bone_count():
			continue
			
		var new_pose = Transform3D()
		new_pose.origin = bones[bone_id].position
		
		# Safe rotation application
		var rotation = bones[bone_id].rotation
		if not (is_finite(rotation.x) and is_finite(rotation.y) and is_finite(rotation.z) and is_finite(rotation.w)):
			rotation = Quaternion.IDENTITY
		
		new_pose.basis = Basis(rotation)
		
		# Use the correct Godot 4 method - set_bone_pose for local transforms
		skel.set_bone_pose(bone_idx, new_pose)

## Reset bone transform to its initial value
func revert() -> void:
	if skel:
		# Reset all bone poses to rest
		skel.reset_bone_poses()

### GETTERS - All with safety checks
func get_bone_parent(bone_id: String) -> String:
	if bones.has(bone_id):
		return bones[bone_id].parent
	return "-1"

func get_bone_children_count(bone_id: String) -> int:
	if bones.has(bone_id):
		return bones[bone_id].children.size()
	return 0

func get_bone_children(bone_id: String) -> Array:
	if bones.has(bone_id):
		return bones[bone_id].children
	return []

func get_bone_position(bone_id: String) -> Vector3:
	if bones.has(bone_id):
		return bones[bone_id].position
	return Vector3.ZERO

func get_bone_rotation(bone_id: String) -> Quaternion:
	if bones.has(bone_id):
		return bones[bone_id].rotation
	return Quaternion.IDENTITY

func get_bone_length(bone_id: String) -> float:
	if bones.has(bone_id):
		return bones[bone_id].length * bones[bone_id].length_multiplier
	return 0.0

func get_bone_weight(bone_id: String) -> float:
	if bones.has(bone_id):
		return bones[bone_id].weight_sum
	return 0.0

func get_bone_start_direction(bone_id: String) -> Vector3:
	if bones.has(bone_id):
		return bones[bone_id].start_direction
	return Vector3.FORWARD

func get_bone_start_rotation(bone_id: String) -> Quaternion:
	if bones.has(bone_id):
		return bones[bone_id].start_rotation
	return Quaternion.IDENTITY

func has_bone(bone_id: String) -> bool:
	return bones.has(bone_id)

func get_bone_modifiers(bone_id: String) -> int:
	if bones.has(bone_id):
		return bones[bone_id].modifier_flags
	return MODIFIER.NONE

func get_bone_modifier_master(bone_id: String) -> String:
	if bones.has(bone_id) and bones[bone_id].has("modifier_master"):
		return bones[bone_id].modifier_master
	return ""

func get_bone_damped_transform(bone_id: String) -> Array:
	if bones.has(bone_id) and bones[bone_id].has("damped_transform"):
		return bones[bone_id].damped_transform
	return []

func get_bone_bind_ids(bone_id: String) -> Array:
	if bones.has(bone_id) and bones[bone_id].has("bind_ids"):
		return bones[bone_id].bind_ids
	return []

func get_bone_fork_bind_ids(bone_id: String) -> Array:
	if bones.has(bone_id) and bones[bone_id].has("fork_bind_ids"):
		return bones[bone_id].fork_bind_ids
	return []

func get_bone_cage_bind_id(bone_id: String) -> int:
	if bones.has(bone_id) and bones[bone_id].has("cage_bind_id"):
		return bones[bone_id].cage_bind_id
	return -1

### SETTERS - All with safety checks
func set_bone_position(bone_id: String, position: Vector3) -> void:
	if bones.has(bone_id) and is_finite(position.x) and is_finite(position.y) and is_finite(position.z):
		bones[bone_id].position = position

func set_biassed_bone_position(bone_id: String, position: Vector3, weight: float) -> void:
	if not bones.has(bone_id) or not is_finite(weight) or weight <= 0:
		return
		
	if not (is_finite(position.x) and is_finite(position.y) and is_finite(position.z)):
		return
		
	bones[bone_id].weight_sum += weight
	bones[bone_id].weighted_vector_sum += position * weight
	
	if bones[bone_id].weight_sum > 0:
		bones[bone_id].position = bones[bone_id].weighted_vector_sum / bones[bone_id].weight_sum

func set_bone_rotation(bone_id: String, rotation: Quaternion) -> void:
	if not bones.has(bone_id):
		return
		
	# Validate quaternion before setting
	if is_finite(rotation.x) and is_finite(rotation.y) and is_finite(rotation.z) and is_finite(rotation.w):
		# Check if quaternion is reasonably normalized
		var length_sq = rotation.length_squared()
		if is_finite(length_sq) and length_sq > 0.1 and length_sq < 10.0:
			bones[bone_id].rotation = rotation.normalized()
		else:
			bones[bone_id].rotation = Quaternion.IDENTITY
	else:
		bones[bone_id].rotation = Quaternion.IDENTITY

func set_bone_length_multiplier(bone_id: String, multiplier: float) -> void:
	if bones.has(bone_id) and is_finite(multiplier) and multiplier > 0:
		bones[bone_id].length_multiplier = multiplier

func add_velocity_to_bone(bone_id: String, velocity: Vector3) -> Vector3:
	if not bones.has(bone_id):
		return Vector3.ZERO
		
	if not bones[bone_id].has("velocity"):
		bones[bone_id].velocity = Vector3.ZERO
		
	if is_finite(velocity.x) and is_finite(velocity.y) and is_finite(velocity.z):
		bones[bone_id].velocity += velocity
		
	return bones[bone_id].velocity

func update_bone_damped_transform(bone_id: String, node) -> void:
	if not bones.has(bone_id) or not node:
		return
		
	bones[bone_id].damped_transform = []
	var parent_id = bones[bone_id].parent
	
	if bones.has(parent_id) and bones[parent_id].has("damped_transform"):
		bones[bone_id].damped_transform.push_back(clampf(bones[parent_id].damped_transform[0] * node.stiffness_passed_down, 0.0, 1.0))
		bones[bone_id].damped_transform.push_back(clampf(bones[parent_id].damped_transform[1] * node.damping_passed_down, 0.0, 1.0))
		bones[bone_id].damped_transform.push_back(clampf(bones[parent_id].damped_transform[2] * node.mass_passed_down, 0.0, 1.0))
	else:
		bones[bone_id].damped_transform.push_back(node.stiffness)
		bones[bone_id].damped_transform.push_back(node.damping)
		bones[bone_id].damped_transform.push_back(node.mass)
	
	bones[bone_id].damped_transform.push_back(node.gravity)

### CLEAN UP
func wipe_weights() -> void:
	for bone in bones.keys():
		bones[bone].weight_sum = 0
		bones[bone].weighted_vector_sum = Vector3.ZERO

func wipe_modifiers() -> void:
	for bone in bones.values():
		if bone.modifier_flags == MODIFIER.NONE:
			continue
		if bone.modifier_flags & MODIFIER.BIND:
			bone.erase("bind_ids")
		if bone.modifier_flags & MODIFIER.FORK_BIND:
			bone.erase("fork_bind_ids")
		if bone.modifier_flags & MODIFIER.SOLID:
			bone.erase("modifier_master")
		if bone.modifier_flags & MODIFIER.DAMPED_TRANSFORM:
			bone.erase("modifier_master")
			bone.erase("velocity")
			bone.erase("damped_transform")
		bone.modifier_flags = MODIFIER.NONE

### DEBUG
func cshow(properties: String = "parent,children", N: int = -1) -> void:
	if not skel:
		print("No skeleton assigned")
		return
		
	var props: PackedStringArray = properties.split(",")
	var count = 0
	for bone_id in bones.keys():
		if N >= 0 and count >= N:
			break
		var bone_idx = int(bone_id)
		var bone_name = skel.get_bone_name(bone_idx) if bone_idx >= 0 and bone_idx < skel.get_bone_count() else "UNKNOWN"
		print("## ", bone_name.to_upper(), " (", bone_id, ") ####################################")
		for prop in props:
			if bones[bone_id].has(prop):
				print("\t\t\t" + prop + " - ", bones[bone_id][prop])
		count += 1
