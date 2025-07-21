@tool
extends Node3D

"""
	FBIKM - Pole
		by Nemo Czanderlitch/Nino Čandrlić
			@R3X-G1L       (godot assets store)
			R3X-G1L6AME5H  (github)
	
	Updated for Godot 4.4.1 - Fixed property system and signal connections
"""

const FBIKM_NODE_ID = 2  # THIS NODE'S IDENTIFIER

## Select which side of the bone (X, Z -X, -Z) gets rotated to face this node
enum SIDE {FORWARD, BACKWARD, LEFT, RIGHT}

var tip_bone_id: String = "-1"
var root_bone_id: String = "-1"
@export var turn_to: SIDE = SIDE.FORWARD
var _bone_names = "VOID:-1"

## BOILERPLATE FOR DROPDOWN MENU
func _get(property: StringName):
	match property:
		"tip_bone_id":
			return tip_bone_id
		"root_bone_id":
			return root_bone_id 
		_:
			return null

func _set(property: StringName, value) -> bool:
	match property:
		"tip_bone_id":
			tip_bone_id = str(value)
			return true
		"root_bone_id":
			root_bone_id = str(value)
			return true
		_:
			return false

func _get_property_list() -> Array:
	var result = []
	result.push_back({
			"name": "tip_bone_id",
			"type": TYPE_INT,
			"usage": PROPERTY_USAGE_DEFAULT,
			"hint": PROPERTY_HINT_ENUM,
			"hint_string": _bone_names
	})
	result.push_back({
			"name": "root_bone_id",
			"type": TYPE_INT,
			"usage": PROPERTY_USAGE_DEFAULT,
			"hint": PROPERTY_HINT_ENUM,
			"hint_string": _bone_names
	})
	return result

###############################################################################
func _ready() -> void:
	if Engine.is_editor_hint():
		_connect_to_parent()

func _connect_to_parent() -> void:
	var parent = get_parent()
	if parent and parent.has_method("get") and parent.get("FBIKM_NODE_ID") == 0:
		print("IKPole connecting to parent manager")
		if not parent.bone_names_obtained.is_connected(_update_parameters):
			parent.bone_names_obtained.connect(_update_parameters)
			print("IKPole connected successfully")
		else:
			print("IKPole already connected")
	else:
		print("IKPole: Parent is not a KinematicsManager")
		# Try again in a frame
		call_deferred("_connect_to_parent")

## Update the dropdown menu
func _update_parameters(bone_names: String) -> void:
	print("IKPole received bone names: ", bone_names)
	_bone_names = bone_names
	# Force inspector update
	notify_property_list_changed()
	# Also force a scene tree update
	if Engine.is_editor_hint():
		call_deferred("_force_inspector_refresh")

func _force_inspector_refresh() -> void:
	# Force the editor to refresh by touching the scene
	if Engine.is_editor_hint():
		set_notify_transform(true)
		set_notify_transform(false)
		set_notify_transform(true)

## Return current position (used by the solver)
func get_target() -> Transform3D:
	return self.transform

# Override to ensure connection when parent changes
func _notification(what: int) -> void:
	if what == NOTIFICATION_PARENTED and Engine.is_editor_hint():
		call_deferred("_connect_to_parent")
