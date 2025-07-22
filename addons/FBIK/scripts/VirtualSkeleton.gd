extends RefCounted
class_name VirtualSkeleton

"""
		FBIKM - Virtual Skeleton
				by Nemo Czanderlitch/Nino Čandrlić
						@R3X-G1L       (godot assets store)
						R3X-G1L6AME5H  (github)
		This is an higher level representation of the Godot Skeleton3D Node; it holds more data.
		It stores child bones, thusly allowing for solving branches in the Skeleton.
		Additionally, it holds more rotation data for smoother solutions.
		
		UPDATED FOR GODOT 4.4.1 - Fixed bone referencing and transform handling
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

var bones := {}
var skel: Skeleton3D
var roots := PackedStringArray([])

# Bone name to ID mapping for efficient lookups
var bone_name_to_id := {}
var bone_id_to_name := {}

### INIT
func _init(skeleton: Skeleton3D, build_with_initial_transform: bool) -> void:
	skel = skeleton
	_build_bone_mappings()
	
	for id in range(skeleton.get_bone_count()):
		add_bone(str(id), 
				str(skeleton.get_bone_parent(id)),
				skeleton.get_bone_global_pose(id),
				build_with_initial_transform)
	
	_calculate_bone_directions()

func _build_bone_mappings() -> void:
	"""Build efficient bone name <-> ID mappings"""
	bone_name_to_id.clear()
	bone_id_to_name.clear()
	
	for i in range(skel.get_bone_count()):
		var bone_name := skel.get_bone_name(i)
		bone_name_to_id[bone_name] = i
		bone_id_to_name[i] = bone_name
		
		# Also map by string ID for compatibility
		bone_name_to_id[str(i)] = i

func _calculate_bone_directions() -> void:
	"""Calculate initial bone directions after all bones are added"""
	# Put all bones whose parent is -1 in a solving queue 
	var bone_queue := PackedStringArray([])
	for root in roots:
		bone_queue.append_array(PackedStringArray(get_bone_children(root)))
	
	if bone_queue.is_empty():
		return
	
	var current_bone := bone_queue[0]
	bone_queue.remove_at(0)
	
	while true: 
		var num_of_children := get_bone_children_count(current_bone)
		if num_of_children == 0:
			# Leaf node
			var parent_id := get_bone_parent(current_bone)
			if parent_id != "-1":
				bones[current_bone].start_direction = get_bone_position(current_bone) - get_bone_position(parent_id)
			
			if bone_queue.size() == 0:
				break
			
			# Pop the first item in queue
			current_bone = bone_queue[0]
			bone_queue.remove_at(0)
		else:
			# Inside Chain
			for child_bone in get_bone_children(current_bone):
				# Push branch on the queue so it can be solved later
				bone_queue.push_back(child_bone)
			
			var parent_id := get_bone_parent(current_bone)
			if parent_id != "-1":
				bones[current_bone].start_direction = get_bone_position(current_bone) - get_bone_position(parent_id)
			
			# Pop the first item in queue
			current_bone = bone_queue[0]
			bone_queue.remove_at(0)

func add_bone(bone_id: String, parent_id: String, transform: Transform3D, build_with_initial_transform: bool) -> void:
	var direction := Vector3.ZERO
	var preexisting_children := []
	
	# If a parent exists, immediately solve the distance from it to child, as well as link them
	if bones.has(parent_id) and parent_id != "-1":
		direction = transform.origin - bones[parent_id].position
		bones[parent_id].children.push_back(bone_id)
	
	# Check if this bone is a parent to any of the existing nodes
	for bone in bones.keys():
		if bones[bone].parent == bone_id:
			preexisting_children.push_back(bone)
			bones[bone].start_direction = bones[bone].position - transform.origin
			bones[bone].length = bones[bone].start_direction.length()
	
	# Add the bone
	bones[bone_id] = {
		### Tree data
		"parent": parent_id, 
		"children": preexisting_children,
		### Solve position data
		"position": transform.origin,
		"length": direction.length(),
		"length_multiplier": 1.0,
		### Solve rotation data
		"rotation": transform.basis.get_rotation_quaternion(),
		"start_rotation": transform.basis.get_rotation_quaternion(),
		"start_direction": direction.normalized() if direction.length() > 0.001 else Vector3.FORWARD,
		### Solve Subbase data
		"weighted_vector_sum": Vector3.ZERO,
		"weight_sum": 0.0,
		### Constraint data
		"modifier_flags": MODIFIER.NONE,
	}
	
	# Add initial bone position for runtime purposes
	if build_with_initial_transform:
		bones[bone_id]["init_tr"] = transform
	
	# Check if bone is the root
	if parent_id == "-1":
		roots.push_back(bone_id)
		bones[bone_id]["initial_position"] = transform.origin

func find_bone_by_name(bone_name: String) -> String:
	"""Find bone ID by name, supporting both string names and numeric IDs"""
	# Direct name lookup
	if bone_name_to_id.has(bone_name):
		return str(bone_name_to_id[bone_name])
	
	# Try direct string ID
	if bones.has(bone_name):
		return bone_name
		
	# Try to find by partial name match (case insensitive)
	var lower_name := bone_name.to_lower()
	for name in bone_name_to_id.keys():
		if name.to_lower() == lower_name:
			return str(bone_name_to_id[name])
	
	# Try to find by contains (for names like "hand.L" vs "hand_L")
	for name in bone_name_to_id.keys():
		if name.to_lower().contains(lower_name) or lower_name.contains(name.to_lower()):
			return str(bone_name_to_id[name])
	
	print("WARNING: Bone '" + bone_name + "' not found in skeleton!")
	print("Available bones: ", bone_name_to_id.keys())
	return "-1"

func set_bone_modifier(bone_id: String, modifier: int, node = null) -> void:
	# Convert bone name to ID if needed
	var actual_bone_id := find_bone_by_name(bone_id) if not bones.has(bone_id) else bone_id
	
	if not bones.has(actual_bone_id) or actual_bone_id == "-1":
		print("Cannot set modifier: bone not found: ", bone_id)
		return
	
	if modifier == MODIFIER.LOOK_AT:
		bones[actual_bone_id]["modifier_flags"] = bones[actual_bone_id]["modifier_flags"] | MODIFIER.LOOK_AT
	
	elif modifier == MODIFIER.BIND:
		if node != null:
			var bone1_id := find_bone_by_name(node.bone_1)
			var bone2_id := find_bone_by_name(node.bone_2)
			var bone3_id := find_bone_by_name(node.bone_3)
			
			if bone1_id != "-1":
				bones[bone1_id]["modifier_flags"] = bones[bone1_id]["modifier_flags"] | MODIFIER.BIND
				
				if not bones[bone1_id].has("bind_ids"):
					bones[bone1_id]["bind_ids"] = []
				bones[bone1_id]["bind_ids"].push_back(node.bind_id)
	
	elif modifier == MODIFIER.FORK_BIND:
		if node != null:
			var bone1_id := find_bone_by_name(node.bone_1)
			
			if bone1_id != "-1":
				bones[bone1_id]["modifier_flags"] = bones[bone1_id]["modifier_flags"] | MODIFIER.FORK_BIND
				
				if not bones[bone1_id].has("fork_bind_ids"):
					bones[bone1_id]["fork_bind_ids"] = []
				bones[bone1_id]["fork_bind_ids"].push_back(node.bind_id)
	
	elif modifier == MODIFIER.CAGE_BIND:
		if node != null:
			var backbone1_id := find_bone_by_name(node.backbone_1)
			
			if backbone1_id != "-1":
				bones[backbone1_id]["modifier_flags"] = bones[backbone1_id]["modifier_flags"] | MODIFIER.CAGE_BIND
				bones[backbone1_id]["cage_bind_id"] = node.bind_id
	
	else:
		var bone_queue: PackedStringArray = []
		var current_bone := actual_bone_id
		
		while true:
			if current_bone == "-1" or not bones.has(current_bone):
				break
			
			for child in bones[current_bone]["children"]:
				bone_queue.push_back(child)
			
			bones[current_bone]["modifier_flags"] = bones[current_bone]["modifier_flags"] | modifier
			bones[current_bone]["modifier_master"] = actual_bone_id
			
			if modifier & MODIFIER.DAMPED_TRANSFORM and node != null:
				bones[current_bone]["velocity"] = Vector3.ZERO
				update_bone_damped_transform(current_bone, node)
			
			if bones[current_bone]["children"].size() != 0:
				current_bone = bone_queue[0]
				bone_queue.remove_at(0)
			else:
				current_bone = "-1"

### WRITE VIRTUAL SKELETON TO REAL SKELETON
func bake() -> void:
	for bone_id in bones.keys():
		var bone_idx := int(bone_id)
		var new_pose := Transform3D()
		new_pose.origin = bones[bone_id]["position"]
		new_pose.basis = Basis(bones[bone_id]["rotation"])
		
		# Use the modern Godot 4.4.1 method
		skel.set_bone_global_pose(bone_idx, new_pose)

## Reset bone transform to its initial value
func revert() -> void:
	# Modern way to reset poses in Godot 4.4.1
	skel.reset_bone_poses()

### GETTERS #####################################################################################################
func get_bone_parent(bone_id: String) -> String:
	bone_id = find_bone_by_name(bone_id) if not bones.has(bone_id) else bone_id
	if bones.has(bone_id):
		return bones[bone_id]["parent"]
	else:
		return "-1"

func get_bone_children_count(bone_id: String) -> int:
	bone_id = find_bone_by_name(bone_id) if not bones.has(bone_id) else bone_id
	if bones.has(bone_id):
		return bones[bone_id]["children"].size()
	return 0

func get_bone_children(bone_id: String) -> Array:
	bone_id = find_bone_by_name(bone_id) if not bones.has(bone_id) else bone_id
	if bones.has(bone_id):
		return bones[bone_id]["children"]
	return []

func get_bone_position(bone_id: String) -> Vector3:
	bone_id = find_bone_by_name(bone_id) if not bones.has(bone_id) else bone_id
	if bones.has(bone_id):
		return bones[bone_id]["position"]
	return Vector3.ZERO

func get_bone_rotation(bone_id: String) -> Quaternion:
	bone_id = find_bone_by_name(bone_id) if not bones.has(bone_id) else bone_id
	if bones.has(bone_id):
		return bones[bone_id]["rotation"]
	return Quaternion.IDENTITY

func get_bone_length(bone_id: String) -> float:
	bone_id = find_bone_by_name(bone_id) if not bones.has(bone_id) else bone_id
	if bones.has(bone_id):
		return bones[bone_id]["length"] * bones[bone_id]["length_multiplier"]
	return 0.0

func get_bone_weight(bone_id: String) -> float:
	bone_id = find_bone_by_name(bone_id) if not bones.has(bone_id) else bone_id
	if bones.has(bone_id):
		return bones[bone_id]["weight_sum"]
	return 0.0

func get_bone_start_direction(bone_id: String) -> Vector3:
	bone_id = find_bone_by_name(bone_id) if not bones.has(bone_id) else bone_id
	if bones.has(bone_id):
		return bones[bone_id]["start_direction"]
	return Vector3.FORWARD

func get_bone_start_rotation(bone_id: String) -> Quaternion:
	bone_id = find_bone_by_name(bone_id) if not bones.has(bone_id) else bone_id
	if bones.has(bone_id):
		return bones[bone_id]["start_rotation"]
	return Quaternion.IDENTITY

func has_bone(bone_id: String) -> bool:
	# First check direct ID
	if bones.has(bone_id):
		return true
	# Then try to find by name
	var found_id := find_bone_by_name(bone_id)
	return found_id != "-1" and bones.has(found_id)

## Modifier stuff
func get_bone_modifiers(bone_id: String) -> int:
	bone_id = find_bone_by_name(bone_id) if not bones.has(bone_id) else bone_id
	if bones.has(bone_id):
		return bones[bone_id]["modifier_flags"]
	return MODIFIER.NONE

func get_bone_modifier_master(bone_id: String) -> String:
	bone_id = find_bone_by_name(bone_id) if not bones.has(bone_id) else bone_id
	if bones.has(bone_id) and bones[bone_id].has("modifier_master"):
		return bones[bone_id]["modifier_master"]
	return "-1"

func get_bone_damped_transform(bone_id: String) -> Array:
	bone_id = find_bone_by_name(bone_id) if not bones.has(bone_id) else bone_id
	if bones.has(bone_id) and bones[bone_id].has("damped_transform"):
		return bones[bone_id]["damped_transform"]
	return []

func get_bone_bind_ids(bone_id: String) -> PackedInt32Array:
	bone_id = find_bone_by_name(bone_id) if not bones.has(bone_id) else bone_id
	if bones.has(bone_id) and bones[bone_id].has("bind_ids"):
		return PackedInt32Array(bones[bone_id]["bind_ids"])
	return PackedInt32Array()

func get_bone_fork_bind_ids(bone_id: String) -> PackedInt32Array:
	bone_id = find_bone_by_name(bone_id) if not bones.has(bone_id) else bone_id
	if bones.has(bone_id) and bones[bone_id].has("fork_bind_ids"):
		return PackedInt32Array(bones[bone_id]["fork_bind_ids"])
	return PackedInt32Array()

func get_bone_cage_bind_id(bone_id: String) -> int:
	bone_id = find_bone_by_name(bone_id) if not bones.has(bone_id) else bone_id
	if bones.has(bone_id) and bones[bone_id].has("cage_bind_id"):
		return bones[bone_id]["cage_bind_id"]
	return -1

### SETTERS #####################################################################################################
func set_bone_position(bone_id: String, position: Vector3) -> void:
	bone_id = find_bone_by_name(bone_id) if not bones.has(bone_id) else bone_id
	if bones.has(bone_id):
		bones[bone_id]["position"] = position

func set_biassed_bone_position(bone_id: String, position: Vector3, weight: float) -> void:
	bone_id = find_bone_by_name(bone_id) if not bones.has(bone_id) else bone_id
	if bones.has(bone_id):
		bones[bone_id]["weight_sum"] += weight
		bones[bone_id]["weighted_vector_sum"] += position * weight
		bones[bone_id]["position"] = bones[bone_id]["weighted_vector_sum"] / bones[bone_id]["weight_sum"]

func set_bone_rotation(bone_id: String, rotation: Quaternion) -> void:
	bone_id = find_bone_by_name(bone_id) if not bones.has(bone_id) else bone_id
	if bones.has(bone_id):
		bones[bone_id]["rotation"] = rotation

func set_bone_length_multiplier(bone_id: String, multiplier: float) -> void:
	bone_id = find_bone_by_name(bone_id) if not bones.has(bone_id) else bone_id
	if bones.has(bone_id):
		bones[bone_id]["length_multiplier"] = multiplier

func add_velocity_to_bone(bone_id: String, velocity: Vector3) -> Vector3:
	bone_id = find_bone_by_name(bone_id) if not bones.has(bone_id) else bone_id
	if bones.has(bone_id):
		if not bones[bone_id].has("velocity"):
			bones[bone_id]["velocity"] = Vector3.ZERO
		bones[bone_id]["velocity"] += velocity
		return bones[bone_id]["velocity"]
	return Vector3.ZERO

## Physics Simulations
func update_bone_damped_transform(bone_id: String, node) -> void:
	bone_id = find_bone_by_name(bone_id) if not bones.has(bone_id) else bone_id
	if not bones.has(bone_id):
		return
		
	bones[bone_id]["damped_transform"] = []
	var parent_id := get_bone_parent(bone_id)
	
	if parent_id != "-1" and bones.has(parent_id) and bones[parent_id].has("damped_transform"):
		bones[bone_id]["damped_transform"].push_back(clamp(bones[parent_id]["damped_transform"][0] * node.stiffness_passed_down, 0.0, 1.0))
		bones[bone_id]["damped_transform"].push_back(clamp(bones[parent_id]["damped_transform"][1] * node.damping_passed_down, 0.0, 1.0))
		bones[bone_id]["damped_transform"].push_back(clamp(bones[parent_id]["damped_transform"][2] * node.mass_passed_down, 0.0, 1.0))
	else:
		bones[bone_id]["damped_transform"].push_back(node.stiffness)
		bones[bone_id]["damped_transform"].push_back(node.damping)
		bones[bone_id]["damped_transform"].push_back(node.mass)
	
	bones[bone_id]["damped_transform"].push_back(node.gravity)

### CLEAN UP ####################################################################################################
func wipe_weights() -> void:
	for bone in bones.keys():
		bones[bone]["weight_sum"] = 0.0
		bones[bone]["weighted_vector_sum"] = Vector3.ZERO

func wipe_modifiers() -> void:
	for bone in bones.values():
		if bone["modifier_flags"] == MODIFIER.NONE:
			continue
		if bone["modifier_flags"] & MODIFIER.BIND:
			bone.erase("bind_ids")
		if bone["modifier_flags"] & MODIFIER.FORK_BIND:
			bone.erase("fork_bind_ids")
		if bone["modifier_flags"] & MODIFIER.CAGE_BIND:
			bone.erase("cage_bind_id")
		if bone["modifier_flags"] & MODIFIER.SOLID:
			bone.erase("modifier_master")
		if bone["modifier_flags"] & MODIFIER.DAMPED_TRANSFORM:
			bone.erase("modifier_master")
			bone.erase("velocity")
			bone.erase("damped_transform")
		bone["modifier_flags"] = MODIFIER.NONE

### DEBUG ######################################################################################################
func cshow(properties: String = "parent,children", N: int = -1) -> void:
	var props := properties.split(",")
	var count := 0
	for bone_id in bones.keys():
		if N >= 0 and count >= N:
			break
		
		var bone_name := "UNKNOWN"
		if bone_id_to_name.has(int(bone_id)):
			bone_name = bone_id_to_name[int(bone_id)]
		
		print("## ", bone_name.to_upper(), " (ID: ", bone_id, ") ####################################")
		for prop in props:
			if bones[bone_id].has(prop):
				print("\t\t\t" + prop + " - ", bones[bone_id][prop])
		count += 1

func get_bone_name_for_id(bone_id: String) -> String:
	"""Get the actual bone name for a given ID"""
	var id := int(bone_id) if bone_id.is_valid_int() else -1
	if bone_id_to_name.has(id):
		return bone_id_to_name[id]
	return "UNKNOWN"

func list_all_bones() -> void:
	"""Debug function to list all available bones"""
	print("=== AVAILABLE BONES ===")
	for i in range(skel.get_bone_count()):
		var name := skel.get_bone_name(i)
		print("ID: ", i, " Name: '", name, "'")
	print("=======================")
