extends RefCounted
class_name VirtualSkeleton

## FBIKM - Virtual Skeleton for Godot 4.4.1
## by Nemo Czanderlitch/Nino Čandrlić
## @R3X-G1L       (godot assets store)
## R3X-G1L6AME5H  (github)
##
## This is a higher level representation of the Godot Skeleton3D Node; it holds more data.
## It stores child bones, thus allowing for solving branches in the Skeleton.
## Additionally, it holds more rotation data for smoother solutions.

## Bone modifier flags using enum for type safety
enum MODIFIER {
	NONE = 0,
	BIND = 1,
	FORK_BIND = 2,
	CAGE_BIND = 4,
	SOLID = 8,
	DAMPED_TRANSFORM = 16,
	LOOK_AT = 32
}

## Core data structures
var bones: Dictionary = {}
var skel: Skeleton3D  # Updated from Skeleton to Skeleton3D
var roots: PackedStringArray = []  # Updated from PoolStringArray

## Constructor - initializes the virtual skeleton from a real Skeleton3D
func _init(skeleton: Skeleton3D, build_with_initial_transform: bool) -> void:
	skel = skeleton
	
	# Build bone hierarchy
	for id in range(skeleton.get_bone_count()):
		add_bone(
			str(id), 
			str(skeleton.get_bone_parent(id)),
			skeleton.get_bone_global_pose(id),
			build_with_initial_transform
		)
	
	# Process bone directions in breadth-first order
	var bone_queue: PackedStringArray = []
	for root in roots:
		bone_queue.append_array(PackedStringArray(get_bone_children(root)))
	
	if bone_queue.is_empty():
		return
		
	var current_bone: String = bone_queue[0]
	bone_queue.remove_at(0)
	
	while true: 
		var num_of_children: int = get_bone_children_count(current_bone)
		
		if num_of_children == 0:
			# Leaf node - calculate direction from parent
			var parent_id: String = get_bone_parent(current_bone)
			if parent_id != "-1":
				bones[current_bone].start_direction = get_bone_position(current_bone) - get_bone_position(parent_id)
			
			if bone_queue.is_empty():
				break
			
			# Pop the first item in queue
			current_bone = bone_queue[0]
			bone_queue.remove_at(0)
		else:
			# Inside chain - add children to queue and calculate direction
			for child_bone in get_bone_children(current_bone):
				bone_queue.push_back(child_bone)
			
			var parent_id: String = get_bone_parent(current_bone)
			if parent_id != "-1":
				bones[current_bone].start_direction = get_bone_position(current_bone) - get_bone_position(parent_id)
			
			# Pop the first item in queue
			current_bone = bone_queue[0]
			bone_queue.remove_at(0)

## Add a bone to the virtual skeleton with all necessary data
func add_bone(bone_id: String, parent_id: String, transform: Transform3D, build_with_initial_transform: bool) -> void:
	var direction := Vector3.ZERO
	var preexisting_children: Array = []
	
	# If a parent exists, calculate distance and link them
	if bones.has(parent_id):
		direction = transform.origin - bones[parent_id].position
		bones[parent_id].children.push_back(bone_id)
	
	# Check if this bone is a parent to any existing nodes
	for bone in bones.keys():
		if bones[bone].parent == bone_id:
			preexisting_children.push_back(bone)
			bones[bone].start_direction = bones[bone].position - transform.origin
			bones[bone].length = bones[bone].start_direction.length()
	
	# Create bone data structure
	bones[bone_id] = {
		### Tree data
		"parent": parent_id, 
		"children": preexisting_children,
		
		### Solve position data
		"position": transform.origin,
		"length": direction.length(),
		"length_multiplier": 1.0,
		
		### Solve rotation data
		"rotation": transform.basis.get_rotation_quaternion(),  # Updated method name
		"start_rotation": transform.basis.get_rotation_quaternion(),
		"start_direction": direction.normalized(),
		
		### Solve subbase data
		"weighted_vector_sum": Vector3.ZERO,
		"weight_sum": 0.0,
		
		### Constraint data
		"modifier_flags": MODIFIER.NONE,
	}
	
	# Add initial bone position for runtime purposes
	if build_with_initial_transform:
		bones[bone_id].init_tr = transform
	
	# Check if bone is the root
	if parent_id == "-1":
		roots.push_back(bone_id)
		bones[bone_id].initial_position = transform.origin

## Set bone modifiers for constraints and special behaviors
func set_bone_modifier(bone_id: String, modifier: int, node = null) -> void:
	match modifier:
		MODIFIER.LOOK_AT:
			bones[bone_id].modifier_flags |= MODIFIER.LOOK_AT
		
		MODIFIER.BIND:
			if node != null:
				# Set bind modifier on the first bone
				bones[node.bone_1].modifier_flags |= MODIFIER.BIND
				
				# Initialize bind_ids array if it doesn't exist
				if not bones[node.bone_1].has("bind_ids"):
					bones[node.bone_1].bind_ids = []
				
				bones[node.bone_1].bind_ids.push_back(node.bind_id)
		
		MODIFIER.FORK_BIND:
			if node != null:
				bones[node.bone_1].modifier_flags |= MODIFIER.FORK_BIND
				
				if not bones[node.bone_1].has("fork_bind_ids"):
					bones[node.bone_1].fork_bind_ids = []
				
				bones[node.bone_1].fork_bind_ids.push_back(node.bind_id)
		
		MODIFIER.CAGE_BIND:
			if node != null:
				bones[node.backbone_1].modifier_flags |= MODIFIER.CAGE_BIND
				bones[node.backbone_1].cage_bind_id = node.bind_id
		
		_:
			# Apply modifier to bone and all its children
			var bone_queue: PackedStringArray = []
			var current_bone: String = bone_id
			
			while current_bone != "-1":
				# Add children to queue
				for child in bones[current_bone].children:
					bone_queue.push_back(child)
				
				# Apply modifier
				bones[current_bone].modifier_flags |= modifier
				bones[current_bone].modifier_master = bone_id
				
				# Special handling for damped transform
				if modifier & MODIFIER.DAMPED_TRANSFORM and node != null:
					bones[current_bone].velocity = Vector3.ZERO
					update_bone_damped_transform(current_bone, node)
				
				# Move to next bone
				if bones[current_bone].children.size() != 0:
					current_bone = bone_queue[0]
					bone_queue.remove_at(0)
				else:
					current_bone = "-1"

## Destructor - clean up skeleton overrides
func _notification(what: int) -> void:
	if what == NOTIFICATION_PREDELETE:
		if skel != null:
			skel.clear_bones_global_pose_override()
		bones.clear()

## Apply virtual skeleton changes to the real skeleton
func bake() -> void:
	for bone_id in bones.keys():
		var new_pose := Transform3D()
		new_pose.origin = bones[bone_id].position
		new_pose.basis = Basis(bones[bone_id].rotation)
		skel.set_bone_global_pose_override(int(bone_id), new_pose, 1.0, true)

## Reset bone transforms to their initial values
func revert() -> void:
	if skel != null:
		skel.clear_bones_global_pose_override()

#region Getter Methods
## Navigation methods
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

## Solving methods
func get_bone_position(bone_id: String) -> Vector3:
	return bones[bone_id].position

func get_bone_rotation(bone_id: String) -> Quaternion:  # Updated type
	return bones[bone_id].rotation

func get_bone_length(bone_id: String) -> float:
	return bones[bone_id].length * bones[bone_id].length_multiplier

func get_bone_weight(bone_id: String) -> float:
	return bones[bone_id].weight_sum

func get_bone_start_direction(bone_id: String) -> Vector3:
	return bones[bone_id].start_direction

func get_bone_start_rotation(bone_id: String) -> Quaternion:  # Updated type
	return bones[bone_id].start_rotation

func has_bone(bone_id: String) -> bool:
	return bones.has(bone_id)

## Modifier methods
func get_bone_modifiers(bone_id: String) -> int:
	return bones[bone_id].modifier_flags

func get_bone_modifier_master(bone_id: String) -> String:
	return bones[bone_id].get("modifier_master", "")

func get_bone_damped_transform(bone_id: String) -> Array:
	return bones[bone_id].get("damped_transform", [])

func get_bone_bind_ids(bone_id: String) -> PackedInt32Array:  # Updated type
	return PackedInt32Array(bones[bone_id].get("bind_ids", []))

func get_bone_fork_bind_ids(bone_id: String) -> PackedInt32Array:  # Updated type
	return PackedInt32Array(bones[bone_id].get("fork_bind_ids", []))

func get_bone_cage_bind_id(bone_id: String) -> int:
	return bones[bone_id].get("cage_bind_id", -1)
#endregion

#region Setter Methods
func set_bone_position(bone_id: String, position: Vector3) -> void:
	bones[bone_id].position = position

func set_biassed_bone_position(bone_id: String, position: Vector3, weight: float) -> void:
	bones[bone_id].weight_sum += weight
	bones[bone_id].weighted_vector_sum += position * weight
	bones[bone_id].position = bones[bone_id].weighted_vector_sum / bones[bone_id].weight_sum

func set_bone_rotation(bone_id: String, rotation: Quaternion) -> void:  # Updated type
	bones[bone_id].rotation = rotation

## Modifier methods
func set_bone_length_multiplier(bone_id: String, multiplier: float) -> void:
	bones[bone_id].length_multiplier = multiplier

func add_velocity_to_bone(bone_id: String, velocity: Vector3) -> Vector3:
	if not bones[bone_id].has("velocity"):
		bones[bone_id].velocity = Vector3.ZERO
	bones[bone_id].velocity += velocity
	return bones[bone_id].velocity
#endregion

## Update damped transform physics properties for a bone
func update_bone_damped_transform(bone_id: String, node) -> void:
	bones[bone_id].damped_transform = []
	var parent_id: String = bones[bone_id].parent
	
	if bones.has(parent_id) and bones[parent_id].has("damped_transform"):
		# Inherit from parent with multipliers
		bones[bone_id].damped_transform.push_back(
			clamp(bones[parent_id].damped_transform[0] * node.stiffness_passed_down, 0.0, 1.0)
		)
		bones[bone_id].damped_transform.push_back(
			clamp(bones[parent_id].damped_transform[1] * node.damping_passed_down, 0.0, 1.0)
		)
		bones[bone_id].damped_transform.push_back(
			clamp(bones[parent_id].damped_transform[2] * node.mass_passed_down, 0.0, 1.0)
		)
	else:
		# Use base values
		bones[bone_id].damped_transform.push_back(node.stiffness)
		bones[bone_id].damped_transform.push_back(node.damping)
		bones[bone_id].damped_transform.push_back(node.mass)
	
	bones[bone_id].damped_transform.push_back(node.gravity)

#region Cleanup Methods
## Clear all weight data for next solving iteration
func wipe_weights() -> void:
	for bone in bones.keys():
		bones[bone].weight_sum = 0.0
		bones[bone].weighted_vector_sum = Vector3.ZERO

## Clear all modifier data
func wipe_modifiers() -> void:
	for bone in bones.values():
		if bone.modifier_flags == MODIFIER.NONE:
			continue
			
		# Remove modifier-specific data
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
#endregion

#region Debug Methods
## Debug method to show bone properties
func cshow(properties: String = "parent,children", N: int = -1) -> void:
	var props: PackedStringArray = properties.split(",")
	var count: int = 0
	
	for i in bones.keys():
		if N >= 0 and count >= N:
			break
			
		print("## ", skel.get_bone_name(int(i)).to_upper(), " ####################################")
		for prop in props:
			if bones[i].has(prop):
				print("\t\t\t", prop, " - ", bones[i][prop])
		count += 1
#endregion
