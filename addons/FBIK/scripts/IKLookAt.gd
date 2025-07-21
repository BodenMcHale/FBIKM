@tool
extends Marker3D  # Updated from Position3D
class_name IKLookAt

## FBIKM - Look At for Godot 4.4.1
## by Nemo Czanderlitch/Nino Čandrlić
## @R3X-G1L       (godot assets store)
## R3X-G1L6AME5H  (github)
##
## Makes one of the specified bone's sides face this node. Useful for having the head look at something.
## This constraint rotates the bone (and its parent) to orient a specific side toward the target position.

## Node identifier for type checking
const FBIKM_NODE_ID: int = 3

## Enum for bone orientation sides
enum SIDE {
	UP,      ## Bone's up vector points toward target
	DOWN,    ## Bone's down vector points toward target  
	LEFT,    ## Bone's left vector points toward target
	RIGHT,   ## Bone's right vector points toward target
	FORWARD, ## Bone's forward vector points toward target
	BACK     ## Bone's back vector points toward target
}

## Configuration properties
var bone_id: String = "-1"  ## The bone that will look at this target
@export var look_from_side: SIDE = SIDE.UP  ## Which side of the bone should face the target

## Editor dropdown boilerplate
var _bone_names: String = "VOID:-1"

#region Property System for Editor Integration
## Custom property getter for editor dropdowns
func _get(property: StringName):
	match property:
		&"bone_id":
			return bone_id
		_:
			return null

## Custom property setter for editor dropdowns  
func _set(property: StringName, value) -> bool:
	match property:
		&"bone_id":
			bone_id = str(value)
			return true
		_:
			return false

## Define custom properties for the editor inspector
func _get_property_list() -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	
	# Bone selection dropdown
	result.push_back({
		"name": "bone_id",
		"type": TYPE_INT,
		"usage": PROPERTY_USAGE_DEFAULT,
		"hint": PROPERTY_HINT_ENUM,
		"hint_string": _bone_names
	})
	
	return result
#endregion

#region Initialization
func _ready() -> void:
	if Engine.is_editor_hint():  # Updated method name
		var parent_node: Node = get_parent()
		if parent_node != null and parent_node.get("FBIKM_NODE_ID") == 0:  # KinematicsManager's ID
			# Connect to parent's bone name updates for dropdown menus
			if parent_node.has_signal("bone_names_obtained"):
				if not parent_node.bone_names_obtained.is_connected(_update_parameters):
					parent_node.bone_names_obtained.connect(_update_parameters)
#endregion

#region Editor Integration
## Update the dropdown menu when bone structure changes
func _update_parameters(bone_names: String) -> void:
	_bone_names = bone_names
	notify_property_list_changed()  # Updated method name

## Return current transform for the IK solver
func get_target() -> Transform3D:  # Updated return type
	return transform
#endregion

#region Validation and Helper Methods
## Validate that the look-at configuration is correct
func is_valid() -> bool:
	if bone_id == "-1":
		return false
	
	var parent_node: Node = get_parent()
	if parent_node == null or parent_node.get("FBIKM_NODE_ID") != 0:
		return false
	
	# Check if bones exist in the skeleton
	if parent_node.virt_skel == null:
		return false
	
	if not parent_node.virt_skel.has_bone(bone_id):
		return false
	
	# Look-at requires the bone to have a parent for rotation
	var parent_bone_id: String = parent_node.virt_skel.get_bone_parent(bone_id)
	if not parent_node.virt_skel.has_bone(parent_bone_id):
		return false
	
	return true

## Get the direction vector for the current look_from_side
func get_look_direction() -> Vector3:
	match look_from_side:
		SIDE.UP:
			return Vector3.UP
		SIDE.DOWN:
			return Vector3.DOWN
		SIDE.LEFT:
			return Vector3.LEFT
		SIDE.RIGHT:
			return Vector3.RIGHT
		SIDE.FORWARD:
			return Vector3.FORWARD
		SIDE.BACK:
			return Vector3.BACK
		_:
			return Vector3.UP

## Calculate the target direction from bone to look-at target
func get_target_direction() -> Vector3:
	var parent_node: Node = get_parent()
	if parent_node == null or parent_node.virt_skel == null:
		return Vector3.ZERO
	
	if not is_valid():
		return Vector3.ZERO
	
	var bone_position: Vector3 = parent_node.virt_skel.get_bone_position(bone_id)
	var target_position: Vector3 = global_position
	
	return (target_position - bone_position).normalized()

## Get the angle between current bone direction and target
func get_look_angle() -> float:
	var parent_node: Node = get_parent()
	if parent_node == null or parent_node.virt_skel == null:
		return 0.0
	
	if not is_valid():
		return 0.0
	
	var bone_rotation: Quaternion = parent_node.virt_skel.get_bone_rotation(bone_id)
	var current_direction: Vector3 = bone_rotation * get_look_direction()
	var target_direction: Vector3 = get_target_direction()
	
	if target_direction.length_squared() < 0.001:
		return 0.0
	
	return current_direction.angle_to(target_direction)
#endregion

#region Debug and Visualization
## Get debug information about the look-at constraint
func get_debug_info() -> Dictionary:
	var info: Dictionary = {}
	info["bone_id"] = bone_id
	info["look_from_side"] = SIDE.keys()[look_from_side]
	info["is_valid"] = is_valid()
	info["target_position"] = global_position
	info["look_direction"] = get_look_direction()
	info["target_direction"] = get_target_direction()
	info["look_angle_degrees"] = rad_to_deg(get_look_angle())
	
	var parent_node: Node = get_parent()
	if parent_node != null and parent_node.virt_skel != null:
		if parent_node.virt_skel.has_bone(bone_id):
			info["bone_name"] = parent_node.skel.get_bone_name(int(bone_id)) if parent_node.skel != null else "Unknown"
			info["bone_position"] = parent_node.virt_skel.get_bone_position(bone_id)
			info["bone_rotation"] = parent_node.virt_skel.get_bone_rotation(bone_id)
	
	return info

## Print debug information to console
func print_debug_info() -> void:
	var info: Dictionary = get_debug_info()
	print("=== IK Look-At Debug Info ===")
	for key in info.keys():
		print("  ", key, ": ", info[key])
	print("=============================")

## Visualize the look-at constraint in the editor (called by engine)
func _draw_gizmo() -> void:
	if not Engine.is_editor_hint():
		return
	
	if not is_valid():
		return
	
	var parent_node: Node = get_parent()
	if parent_node == null or parent_node.virt_skel == null:
		return
	
	# This would be implemented with editor gizmos in a full implementation
	# For now, we can use debug drawing if available
	pass
#endregion

#region Utility Methods
## Set the bone to look at by name instead of ID
func set_bone_by_name(bone_name: String) -> bool:
	var parent_node: Node = get_parent()
	if parent_node == null or parent_node.skel == null:
		return false
	
	# Find bone ID by name
	for i in range(parent_node.skel.get_bone_count()):
		if parent_node.skel.get_bone_name(i) == bone_name:
			bone_id = str(i)
			notify_property_list_changed()
			return true
	
	return false

## Get the bone name if bone_id is valid
func get_bone_name() -> String:
	var parent_node: Node = get_parent()
	if parent_node == null or parent_node.skel == null:
		return ""
	
	if bone_id == "-1":
		return ""
	
	var bone_index: int = int(bone_id)
	if bone_index >= 0 and bone_index < parent_node.skel.get_bone_count():
		return parent_node.skel.get_bone_name(bone_index)
	
	return ""

## Smoothly interpolate the look-at over time
func set_smooth_look_target(target_pos: Vector3, interpolation_speed: float = 5.0) -> void:
	var tween: Tween = create_tween()
	tween.tween_property(self, "global_position", target_pos, 1.0 / interpolation_speed)

## Set look target to track a specific node
func track_node(target_node: Node3D) -> void:
	if target_node == null:
		return
	
	# This would be better implemented with a proper tracking system
	# For now, just set the position
	global_position = target_node.global_position
#endregion
