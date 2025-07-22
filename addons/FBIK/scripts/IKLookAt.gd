@tool
extends Marker3D

"""
		FBIKM - Look At
				by Nemo Czanderlitch/Nino Čandrlić
						@R3X-G1L       (godot assets store)
						R3X-G1L6AME5H  (github)
		Makes one of the specified bone's sides face this node. Useful in having the head look at something.

"""
const FBIKM_NODE_ID = 3

enum LOOK_SIDE {UP, DOWN, LEFT, RIGHT, FORWARD, BACK}

@export var bone_id: String = "-1" : set = _set_bone_id
@export var look_from_side: LOOK_SIDE = LOOK_SIDE.UP
@export var spin_override_angle: float = 0.0

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

func _set_bone_id(value: String):
	bone_id = value

func _get_property_list():
	var properties = []
	
	properties.append({
		"name": "bone_id",
		"type": TYPE_STRING,
		"usage": PROPERTY_USAGE_DEFAULT,
		"hint": PROPERTY_HINT_ENUM,
		"hint_string": _bone_names
	})
	
	return properties

## Interface methods for the FBIK manager
func get_fbik_type() -> String:
	return "lookat"

func get_target_position() -> Vector3:
	return global_position

func get_target_bone() -> String:
	return bone_id

func get_look_side() -> LOOK_SIDE:
	return look_from_side

func get_spin_angle() -> float:
	return spin_override_angle

## Utility function to create rotation from direction
static func look_rotation_from_direction(direction: Vector3, up: Vector3 = Vector3.UP) -> Basis:
	if direction.is_zero_approx():
		return Basis.IDENTITY
		
	var forward = direction.normalized()
	var right = up.cross(forward).normalized()
	
	# Handle case where forward and up are parallel
	if right.is_zero_approx():
		right = Vector3.RIGHT if abs(forward.dot(Vector3.UP)) > 0.9 else Vector3.UP.cross(forward).normalized()
	
	var corrected_up = forward.cross(right).normalized()
	
	return Basis(right, corrected_up, forward)

## Calculate the rotation needed for the bone to look at the target
func calculate_look_rotation(bone_position: Vector3, target_position: Vector3, current_rotation: Quaternion) -> Quaternion:
	var direction = (target_position - bone_position).normalized()
	
	if direction.is_zero_approx():
		return current_rotation
	
	var look_basis: Basis
	
	match look_from_side:
		LOOK_SIDE.UP:
			look_basis = look_rotation_from_direction(direction, Vector3.BACK)
		LOOK_SIDE.DOWN:
			look_basis = look_rotation_from_direction(-direction, Vector3.FORWARD)
		LOOK_SIDE.LEFT:
			look_basis = look_rotation_from_direction(direction, Vector3.UP)
			look_basis = look_basis.rotated(direction, -PI/2)
		LOOK_SIDE.RIGHT:
			look_basis = look_rotation_from_direction(direction, Vector3.UP)
			look_basis = look_basis.rotated(direction, PI/2)
		LOOK_SIDE.FORWARD:
			look_basis = look_rotation_from_direction(direction, Vector3.UP)
		LOOK_SIDE.BACK:
			look_basis = look_rotation_from_direction(-direction, Vector3.UP)
	
	# Apply spin override
	if abs(spin_override_angle) > 0.001:
		look_basis = look_basis.rotated(direction, deg_to_rad(spin_override_angle))
	
	return look_basis.get_rotation_quaternion()
