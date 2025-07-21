@tool
extends Marker3D

## Simplified IK Pole for Godot 4.x
## Controls the bend direction of a bone chain (like elbow or knee direction)

const FBIKM_NODE_ID = 2

enum POLE_SIDE {FORWARD, BACKWARD, LEFT, RIGHT}

@export var tip_bone_id: String = "-1" : set = _set_tip_bone
@export var root_bone_id: String = "-1" : set = _set_root_bone
@export var turn_to: POLE_SIDE = POLE_SIDE.FORWARD
@export var influence: float = 1.0

var _bone_names: String = "NONE:-1"

func _ready():
	if Engine.is_editor_hint():
		_connect_to_parent()

func _connect_to_parent():
	var parent_node = get_parent()
	if parent_node and parent_node.has_signal("bone_names_updated"):
		if not parent_node.bone_names_updated.is_connected(_on_bone_names_updated):
			parent_node.bone_names_updated.connect(_on_bone_names_updated)

func _on_bone_names_updated(bone_names: String):
	_bone_names = bone_names
	notify_property_list_changed()

func _set_tip_bone(value: String):
	tip_bone_id = value
	
func _set_root_bone(value: String):
	root_bone_id = value

func _get_property_list():
	var properties = []
	
	properties.append({
		"name": "tip_bone_id",
		"type": TYPE_STRING,
		"usage": PROPERTY_USAGE_DEFAULT,
		"hint": PROPERTY_HINT_ENUM,
		"hint_string": _bone_names
	})
	
	properties.append({
		"name": "root_bone_id",
		"type": TYPE_STRING,
		"usage": PROPERTY_USAGE_DEFAULT,
		"hint": PROPERTY_HINT_ENUM,
		"hint_string": _bone_names
	})
	
	return properties

## Interface methods for the FBIK manager
func get_fbik_type() -> String:
	return "pole"

func get_target_position() -> Vector3:
	return global_position

func get_tip_bone() -> String:
	return tip_bone_id
	
func get_root_bone() -> String:
	return root_bone_id

func get_pole_side() -> POLE_SIDE:
	return turn_to

func get_influence() -> float:
	return influence

## Calculate pole constraint for a 3-bone chain (like arm: shoulder->elbow->wrist)
func apply_pole_constraint(bone_positions: Array, bone_lengths: Array, target_pos: Vector3, pole_pos: Vector3) -> Array:
	if bone_positions.size() != 3 or bone_lengths.size() != 2:
		return bone_positions
		
	var start_pos = bone_positions[0]  # Shoulder
	var mid_pos = bone_positions[1]    # Elbow  
	var end_pos = bone_positions[2]    # Wrist
	
	var length1 = bone_lengths[0]  # Upper arm length
	var length2 = bone_lengths[1]  # Forearm length
	
	# Calculate the ideal middle joint position using pole constraint
	var new_positions = bone_positions.duplicate()
	
	# Vector from start to target
	var start_to_target = target_pos - start_pos
	var target_distance = start_to_target.length()
	
	# Clamp target distance to reachable range
	var max_reach = length1 + length2
	var min_reach = abs(length1 - length2)
	target_distance = clamp(target_distance, min_reach, max_reach)
	
	# Calculate joint angles using law of cosines
	var cos_angle = (length1 * length1 + target_distance * target_distance - length2 * length2) / (2.0 * length1 * target_distance)
	cos_angle = clamp(cos_angle, -1.0, 1.0)
	var angle = acos(cos_angle)
	
	# Create plane containing start, target, and pole
	var forward = start_to_target.normalized()
	var to_pole = (pole_pos - start_pos).normalized()
	
	# Calculate the "right" vector in the bending plane
	var right = forward.cross(to_pole).normalized()
	if right.is_zero_approx():
		# Pole is collinear with start-target, use a default right vector
		right = Vector3.UP.cross(forward).normalized()
		if right.is_zero_approx():
			right = Vector3.RIGHT.cross(forward).normalized()
	
	# Calculate the "up" vector in the bending plane
	var up = right.cross(forward).normalized()
	
	# Apply pole side offset
	var side_offset = Vector3.ZERO
	match turn_to:
		POLE_SIDE.FORWARD:
			side_offset = forward
		POLE_SIDE.BACKWARD:
			side_offset = -forward
		POLE_SIDE.LEFT:
			side_offset = -right
		POLE_SIDE.RIGHT:
			side_offset = right
	
	# Blend between natural up direction and pole direction
	var pole_direction = to_pole.lerp(side_offset, 0.3).normalized()
	up = up.lerp(pole_direction, influence).normalized()
	
	# Calculate middle joint position
	var mid_direction = forward.rotated(right, -angle)
	new_positions[1] = start_pos + mid_direction * length1
	
	# Adjust end position to maintain bone length
	var mid_to_end = (target_pos - new_positions[1]).normalized()
	new_positions[2] = new_positions[1] + mid_to_end * length2
	
	return new_positions

## Utility function to get bone chain between root and tip
func get_bone_chain(bone_data: Dictionary) -> Array:
	var chain = []
	var current = tip_bone_id
	
	# Build chain from tip to root
	while current != "-1" and bone_data.has(current) and current != root_bone_id:
		chain.push_front(current)
		current = bone_data[current].parent
		
		# Prevent infinite loops
		if chain.size() > 20:
			break
	
	# Add root bone
	if current == root_bone_id:
		chain.push_front(root_bone_id)
	
	return chain
