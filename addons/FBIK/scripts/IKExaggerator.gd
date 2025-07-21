@tool
extends Node
class_name IKExaggerator

## FBIKM - Exaggerator for Godot 4.4.1
## by Nemo Czanderlitch/Nino Čandrlić
## @R3X-G1L       (godot assets store)
## R3X-G1L6AME5H  (github)
##
## Scales the specified bone length dynamically. Allows for more expressive and lively animations
## by exaggerating or diminishing bone lengths in real-time. Useful for cartoon-style animations,
## impact effects, breathing animations, or any scenario where you want to stretch or compress bones.
##
## Examples:
## - Stretch arm bones when reaching for something far away
## - Compress spine bones when character crouches
## - Exaggerate neck length for cartoon expressions
## - Breathing effect by scaling rib bones
## - Impact squash-and-stretch effects

## Node identifier for type checking
const FBIKM_NODE_ID: int = 6

## Configuration properties
var bone_id: String = "-1"  ## The bone whose length will be modified
@export var length_multiplier: float = 1.0 : set = _set_length  ## Length scaling factor (1.0 = normal, 2.0 = double, 0.5 = half)

## Animation and easing properties
@export var enable_smooth_transitions: bool = false  ## Enable smooth interpolation between length changes
@export_range(0.1, 5.0) var transition_speed: float = 2.0  ## Speed of smooth transitions (higher = faster)
@export var min_length_multiplier: float = 0.1  ## Minimum allowed length multiplier (prevents negative/zero lengths)
@export var max_length_multiplier: float = 5.0  ## Maximum allowed length multiplier (prevents extreme stretching)

## Signal emitted when bone length changes (used by IK Manager)
signal length_changed(bone_id: String, length_multiplier: float)

## Internal state for smooth transitions
var _target_length: float = 1.0
var _current_length: float = 1.0
var _transition_tween: Tween

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
	
	result.push_back({
		"name": "bone_id",
		"type": TYPE_INT,
		"usage": PROPERTY_USAGE_DEFAULT,
		"hint": PROPERTY_HINT_ENUM,
		"hint_string": _bone_names
	})
	
	return result
#endregion

#region Initialization and Lifecycle
func _ready() -> void:
	# Initialize transition system
	_target_length = length_multiplier
	_current_length = length_multiplier
	
	if Engine.is_editor_hint():  # Updated method name
		var parent_node: Node = get_parent()
		if parent_node != null and parent_node.get("FBIKM_NODE_ID") == 0:  # KinematicsManager's ID
			# Connect to parent's bone name updates for dropdown menus
			if parent_node.has_signal("bone_names_obtained"):
				if not parent_node.bone_names_obtained.is_connected(_update_parameters):
					parent_node.bone_names_obtained.connect(_update_parameters)

func _process(delta: float) -> void:
	# Handle smooth transitions if enabled
	if enable_smooth_transitions and abs(_current_length - _target_length) > 0.001:
		var lerp_speed: float = transition_speed * delta
		_current_length = lerp(_current_length, _target_length, lerp_speed)
		
		# Emit signal with current interpolated length
		_emit_length_change()
		
		# Stop when close enough to target
		if abs(_current_length - _target_length) < 0.001:
			_current_length = _target_length
#endregion

#region Property Management
## Set the length multiplier with validation and smooth transitions
func _set_length(value: float) -> void:
	# Clamp value to safe range
	value = clamp(value, min_length_multiplier, max_length_multiplier)
	length_multiplier = value
	_target_length = value
	
	if enable_smooth_transitions and is_inside_tree():
		# Smooth transition will be handled in _process
		pass
	else:
		# Immediate change
		_current_length = value
		_emit_length_change()

## Emit the length changed signal
func _emit_length_change() -> void:
	length_changed.emit(bone_id, _current_length)

## Update the dropdown menu when bone structure changes
func _update_parameters(bone_names: String) -> void:
	_bone_names = bone_names
	notify_property_list_changed()  # Updated method name
#endregion

#region Public API
## Set the bone length immediately (no smooth transition)
func set_length_immediate(multiplier: float) -> void:
	var old_smooth: bool = enable_smooth_transitions
	enable_smooth_transitions = false
	_set_length(multiplier)
	enable_smooth_transitions = old_smooth

## Animate to a target length over a specified duration
func animate_to_length(target_multiplier: float, duration: float = 1.0) -> void:
	target_multiplier = clamp(target_multiplier, min_length_multiplier, max_length_multiplier)
	
	# Kill existing tween
	if _transition_tween != null:
		_transition_tween.kill()
	
	# Create new tween
	_transition_tween = create_tween()
	_transition_tween.tween_method(_tween_length_update, _current_length, target_multiplier, duration)
	_transition_tween.tween_callback(_animation_complete.bind(target_multiplier))

## Internal method for tween updates
func _tween_length_update(value: float) -> void:
	_current_length = value
	length_multiplier = value
	_emit_length_change()

## Called when animation completes
func _animation_complete(final_value: float) -> void:
	_target_length = final_value
	_current_length = final_value
	length_multiplier = final_value

## Add to current length (relative change)
func add_to_length(delta_multiplier: float) -> void:
	_set_length(_target_length + delta_multiplier)

## Multiply current length (relative scaling)
func multiply_length(scale_factor: float) -> void:
	_set_length(_target_length * scale_factor)

## Reset length to default (1.0)
func reset_length() -> void:
	_set_length(1.0)

## Get current effective length (may differ from length_multiplier during transitions)
func get_current_length() -> float:
	return _current_length

## Check if currently transitioning between lengths
func is_transitioning() -> bool:
	return abs(_current_length - _target_length) > 0.001
#endregion

#region Validation and Helper Methods
## Validate that the exaggerator configuration is correct
func is_valid() -> bool:
	if bone_id == "-1":
		return false
	
	var parent_node: Node = get_parent()
	if parent_node == null or parent_node.get("FBIKM_NODE_ID") != 0:
		return false
	
	# Check if bone exists in the skeleton
	if parent_node.virt_skel == null:
		return false
	
	return parent_node.virt_skel.has_bone(bone_id)

## Get the original bone length before any modifications
func get_original_bone_length() -> float:
	if not is_valid():
		return 0.0
	
	var parent_node: Node = get_parent()
	# Get length with multiplier of 1.0 (original length)
	return parent_node.virt_skel.bones[bone_id].length

## Get the current modified bone length
func get_current_bone_length() -> float:
	return get_original_bone_length() * _current_length

## Calculate length difference from original
func get_length_delta() -> float:
	return get_current_bone_length() - get_original_bone_length()

## Set bone by name instead of ID
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
#endregion

#region Animation Presets and Effects
## Apply a breathing effect (rhythmic scaling)
func start_breathing_effect(amplitude: float = 0.1, frequency: float = 0.5) -> void:
	if _transition_tween != null:
		_transition_tween.kill()
	
	var base_length: float = 1.0
	var breathing_tween: Tween = create_tween()
	breathing_tween.set_loops()
	
	# Inhale
	breathing_tween.tween_method(
		_tween_length_update, 
		base_length, 
		base_length + amplitude, 
		1.0 / (frequency * 2.0)
	)
	
	# Exhale
	breathing_tween.tween_method(
		_tween_length_update, 
		base_length + amplitude, 
		base_length, 
		1.0 / (frequency * 2.0)
	)

## Apply a pulse effect (quick expansion and contraction)
func pulse_effect(intensity: float = 0.3, duration: float = 0.2) -> void:
	var original_length: float = _current_length
	
	if _transition_tween != null:
		_transition_tween.kill()
	
	_transition_tween = create_tween()
	
	# Expand
	_transition_tween.tween_method(
		_tween_length_update, 
		original_length, 
		original_length + intensity, 
		duration * 0.3
	)
	
	# Contract back
	_transition_tween.tween_method(
		_tween_length_update, 
		original_length + intensity, 
		original_length, 
		duration * 0.7
	)

## Apply a wobble effect (oscillating scaling)
func wobble_effect(amplitude: float = 0.2, frequency: float = 8.0, decay: float = 2.0) -> void:
	var original_length: float = _current_length
	var wobble_duration: float = 2.0
	
	if _transition_tween != null:
		_transition_tween.kill()
	
	_transition_tween = create_tween()
	
	var steps: int = int(wobble_duration * frequency)
	var step_duration: float = wobble_duration / float(steps)
	
	for i in range(steps):
		var progress: float = float(i) / float(steps)
		var current_amplitude: float = amplitude * exp(-decay * progress)
		var oscillation: float = sin(progress * PI * 2.0 * frequency) * current_amplitude
		
		_transition_tween.tween_method(
			_tween_length_update,
			original_length + oscillation,
			original_length + oscillation,
			step_duration
		)
	
	# Return to original
	_transition_tween.tween_method(_tween_length_update, _current_length, original_length, 0.1)

## Stop all animation effects
func stop_effects() -> void:
	if _transition_tween != null:
		_transition_tween.kill()
		_transition_tween = null
#endregion

#region Debug and Visualization
## Get debug information about the exaggerator
func get_debug_info() -> Dictionary:
	var info: Dictionary = {}
	info["bone_id"] = bone_id
	info["is_valid"] = is_valid()
	info["length_multiplier"] = length_multiplier
	info["current_length"] = _current_length
	info["target_length"] = _target_length
	info["is_transitioning"] = is_transitioning()
	info["original_bone_length"] = get_original_bone_length()
	info["current_bone_length"] = get_current_bone_length()
	info["length_delta"] = get_length_delta()
	
	# Settings
	info["enable_smooth_transitions"] = enable_smooth_transitions
	info["transition_speed"] = transition_speed
	info["min_length_multiplier"] = min_length_multiplier
	info["max_length_multiplier"] = max_length_multiplier
	
	# Bone name for reference
	info["bone_name"] = get_bone_name()
	
	return info

## Print debug information to console
func print_debug_info() -> void:
	var info: Dictionary = get_debug_info()
	print("=== IK Exaggerator Debug Info ===")
	for key in info.keys():
		print("  ", key, ": ", info[key])
	print("=================================")

## Get visualization data for editor gizmos
func get_visualization_data() -> Dictionary:
	var data: Dictionary = {}
	
	if not is_valid():
		return data
	
	var parent_node: Node = get_parent()
	
	# Get bone transform information
	data["bone_position"] = parent_node.virt_skel.get_bone_position(bone_id)
	data["bone_rotation"] = parent_node.virt_skel.get_bone_rotation(bone_id)
	data["original_length"] = get_original_bone_length()
	data["current_length"] = get_current_bone_length()
	data["length_ratio"] = _current_length
	
	# Get bone parent and children for context
	var parent_bone: String = parent_node.virt_skel.get_bone_parent(bone_id)
	if parent_bone != "-1":
		data["parent_position"] = parent_node.virt_skel.get_bone_position(parent_bone)
	
	var children: Array = parent_node.virt_skel.get_bone_children(bone_id)
	if not children.is_empty():
		data["child_positions"] = []
		for child in children:
			data["child_positions"].append(parent_node.virt_skel.get_bone_position(child))
	
	return data
#endregion
