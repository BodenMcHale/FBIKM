@tool
extends Node
class_name IKManager

## FBIKM - Inverse Kinematics Manager for Godot 4.4.1
## by Nemo Czanderlitch/Nino Čandrlić
## @R3X-G1L       (godot assets store)
## R3X-G1L6AME5H  (github)
##
## This is the core of the FABRIK IK system. It coordinates all IK solvers and applies
## the calculated transforms to the skeleton, creating procedural animations.

## Node identifier for type checking
const FBIKM_NODE_ID: int = 0

## Constants for child node identification
const FBIKM_CHAIN: int = 1
const FBIKM_POLE: int = 2
const FBIKM_LOOK_AT: int = 3
const FBIKM_BIND: int = 4
const FBIKM_FORK_BIND: int = 5
const FBIKM_EXAGGERATOR: int = 6
const FBIKM_SOLIDIFIER: int = 7
const FBIKM_DAMPED_TRANSFORM: int = 8
const FBIKM_CAGE: int = 9

const VOID_ID: String = "-1"

## Signals for editor integration
signal bone_names_obtained(bone_names: String)

## Exported properties for editor configuration
@export var enabled: bool = false : set = _tick_enabled
@export var skeleton: NodePath : set = _set_skeleton

## FABRIK solver constraints
@export var max_iterations: int = 5  ## Higher = more precise = less performant
@export var minimal_distance: float = 0.01  ## Smaller = more precise = less performant

## Debug options
var DEBUG_dump_bones: bool = false
var DEBUG_bone_property: String = ""
var DEBUG_entry_count: int = -1

## Internal state
var _bone_names_4_children: String = "VOID:-1"
var skel: Skeleton3D  # The target skeleton
var virt_skel: VirtualSkeleton  # Virtual skeleton for calculations

## Solver arrays - organized by type for efficient processing
var _chains: Array[Node] = []
var _poles: Array[Node] = []
var _look_ats: Array[Node] = []
var _binds: Array[Node] = []
var _fork_binds: Array[Node] = []
var _cage_binds: Array[Node] = []

#region Initialization and Setup
func _ready() -> void:
	if not Engine.is_editor_hint():  # Updated method name
		if _build_virtual_skeleton(false) == OK:
			_evaluate_drivers()
			
			if DEBUG_dump_bones:
				virt_skel.cshow(DEBUG_bone_property, DEBUG_entry_count)

## Set the target skeleton and update editor dropdowns
func _set_skeleton(path_2_skel: NodePath) -> void:
	if Engine.is_editor_hint():
		var _temp: Node = get_node_or_null(path_2_skel)
		if _temp is Skeleton3D:  # Updated type check
			skeleton = path_2_skel
			
			# Generate bone names for dropdown menus
			_bone_names_4_children = "VOID:-1,"
			var n: int = _temp.get_bone_count()
			for i in range(n):
				_bone_names_4_children += _temp.get_bone_name(i) + ":" + str(i) + ","
			
			_bone_names_4_children = _bone_names_4_children.rstrip(",")
			bone_names_obtained.emit(_bone_names_4_children)  # Updated signal syntax
			
			_build_virtual_skeleton(true)
			
			# Connect signals to all children
			for c in get_children():
				connect_signals(c)
			bone_names_obtained.emit(_bone_names_4_children)
			
			_reevaluate_drivers()
		else:
			# Clear everything if no valid skeleton
			skeleton = NodePath()
			_wipe_drivers()
			virt_skel = null
	else:
		skeleton = path_2_skel

## Enable/disable the IK system
func _tick_enabled(enable: bool) -> void:
	enabled = enable
	if not enabled and virt_skel != null:
		if DEBUG_dump_bones:
			virt_skel.cshow(DEBUG_bone_property, DEBUG_entry_count)
		virt_skel.revert()

## Build the virtual skeleton from the real skeleton
func _build_virtual_skeleton(in_editor: bool) -> int:
	skel = get_node_or_null(skeleton)
	if skel == null:
		push_error("Skeleton in " + name + " never assigned.")
		enabled = false
		return FAILED
	virt_skel = VirtualSkeleton.new(skel, in_editor)
	return OK

## Clear all driver arrays and modifiers
func _wipe_drivers() -> void:
	_chains.clear()
	_poles.clear()
	_look_ats.clear()
	_binds.clear()
	_fork_binds.clear()
	_cage_binds.clear()
	if virt_skel:
		virt_skel.wipe_modifiers()

## Re-evaluate all drivers (used when skeleton changes)
func _reevaluate_drivers() -> void:
	_wipe_drivers()
	_evaluate_drivers()
#endregion

#region Driver Evaluation
## Scan all children and register appropriate drivers
func _evaluate_drivers() -> void:
	if virt_skel == null:
		push_error("Tried to evaluate drivers but failed because there was no Skeleton Node assigned.")
		return
	
	# Process each child node based on its type
	for node in get_children():
		if node.get("FBIKM_NODE_ID") != null:
			match node.FBIKM_NODE_ID:
				FBIKM_CHAIN:
					_eval_chain_node(node)
				FBIKM_POLE:
					_eval_pole_node(node)
				FBIKM_BIND:
					_eval_bind_node(node)
				FBIKM_FORK_BIND:
					_eval_fork_bind_node(node)
				FBIKM_LOOK_AT:
					_eval_look_at_node(node)
				FBIKM_EXAGGERATOR:
					_eval_exaggerator_node(node)
				FBIKM_SOLIDIFIER:
					_eval_solidifier_node(node)
				FBIKM_DAMPED_TRANSFORM:
					_eval_damped_transform_node(node)
				FBIKM_CAGE:
					_eval_cage_bind_node(node)

## Validate and register a chain node
func _eval_chain_node(chain: Node) -> void:
	if not virt_skel.has_bone(chain.tip_bone_id):
		push_error("IK Chain [" + chain.name + "] ignored. Couldn't find the bone with id [" + chain.tip_bone_id + "].")
		return
	_chains.push_back(chain)

## Validate and register a pole node
func _eval_pole_node(pole: Node) -> void:
	if not virt_skel.has_bone(str(pole.tip_bone_id)):
		push_error("IK Pole [" + pole.name + "] ignored. Couldn't find the bone with id [" + str(pole.tip_bone_id) + "].")
		return
	
	# Check if chain is long enough for pole constraint
	var parent1: String = virt_skel.get_bone_parent(str(pole.tip_bone_id))
	var parent2: String = virt_skel.get_bone_parent(parent1) if parent1 != "-1" else "-1"
	
	if parent1 == "-1" or parent2 == "-1":
		push_error("IK Pole [" + pole.name + "] ignored. Chain too short.")
		return
	
	_poles.push_back(pole)

## Validate and register a look-at node
func _eval_look_at_node(look_at: Node) -> void:
	if not virt_skel.has_bone(look_at.bone_id):
		push_error("IK Look-At [" + look_at.name + "] ignored. Couldn't find the bone with id [" + str(look_at.bone_id) + "].")
		return
	if not virt_skel.has_bone(virt_skel.get_bone_parent(look_at.bone_id)):
		push_error("IK Look-At [" + look_at.name + "] ignored. Specified bone [" + str(look_at.bone_id) + "] doesn't have a parent.")
		return
	
	_look_ats.push_back(look_at)
	virt_skel.set_bone_modifier(look_at.bone_id, VirtualSkeleton.MODIFIER.LOOK_AT)

## Validate and register an exaggerator node
func _eval_exaggerator_node(exaggerator: Node) -> void:
	if not virt_skel.has_bone(exaggerator.bone_id):
		push_error("IK Exaggerator [" + exaggerator.name + "] ignored. Invalid Bone Id.")
		return
	if not exaggerator.is_connected("length_changed", _on_exaggerator_change):
		exaggerator.connect("length_changed", _on_exaggerator_change)

## Validate and register a solidifier node
func _eval_solidifier_node(solidifier: Node) -> void:
	if not virt_skel.has_bone(solidifier.bone_id):
		push_error("IK Solidifier [" + solidifier.name + "] ignored. Specified bone does not exist.")
		return
	if virt_skel.get_bone_children(solidifier.bone_id).size() == 0:
		push_error("IK Solidifier [" + solidifier.name + "] ignored. The bone specified is a tip.")
		return
	virt_skel.set_bone_modifier(solidifier.bone_id, VirtualSkeleton.MODIFIER.SOLID)

## Validate and register a damped transform node
func _eval_damped_transform_node(damped_transform: Node) -> void:
	if not virt_skel.has_bone(damped_transform.bone_id):
		push_error("IK Damped Transform [" + damped_transform.name + "] ignored. Specified bone does not exist.")
		return
	virt_skel.set_bone_modifier(damped_transform.bone_id, VirtualSkeleton.MODIFIER.DAMPED_TRANSFORM, damped_transform)

## Validate and register a bind node (triangular constraint)
func _eval_bind_node(bind: Node) -> void:
	# Validate all three bones exist
	if not virt_skel.has_bone(bind.bone_1):
		push_error("IK Bind [" + bind.name + "] ignored. Bone 1 ID [" + bind.bone_1 + "] is invalid.")
		return
	if not virt_skel.has_bone(bind.bone_2):
		push_error("IK Bind [" + bind.name + "] ignored. Bone 2 ID [" + bind.bone_2 + "] is invalid.")
		return
	if not virt_skel.has_bone(bind.bone_3):
		push_error("IK Bind [" + bind.name + "] ignored. Bone 3 ID [" + bind.bone_3 + "] is invalid.")
		return
	
	# Calculate triangle side lengths
	bind.length_12 = (virt_skel.get_bone_position(bind.bone_1) - virt_skel.get_bone_position(bind.bone_2)).length()
	bind.length_23 = (virt_skel.get_bone_position(bind.bone_2) - virt_skel.get_bone_position(bind.bone_3)).length()
	bind.length_31 = (virt_skel.get_bone_position(bind.bone_3) - virt_skel.get_bone_position(bind.bone_1)).length()
	
	# Auto-detect correction bones from existing binds
	for b in _binds:
		# Check for shared bones and set correction bones automatically
		if bind.bone_2 == b.bone_2:
			bind.bone_2_correction_bone = b.bone_3
			bind.lock_correction_bone_2 = true
			b.bone_2_correction_bone = bind.bone_3
			b.lock_correction_bone_2 = true
		elif bind.bone_2 == b.bone_3:
			bind.bone_2_correction_bone = b.bone_2
			bind.lock_correction_bone_2 = true
			b.bone_3_correction_bone = bind.bone_3
			b.lock_correction_bone_3 = true
		elif bind.bone_3 == b.bone_2:
			bind.bone_3_correction_bone = b.bone_3
			bind.lock_correction_bone_3 = true
			b.bone_2_correction_bone = bind.bone_2
			b.lock_correction_bone_2 = true
		elif bind.bone_3 == b.bone_3:
			bind.bone_3_correction_bone = b.bone_2
			bind.lock_correction_bone_3 = true
			b.bone_3_correction_bone = bind.bone_2
			b.lock_correction_bone_3 = true
	
	# Calculate correction bone lengths if they exist
	if virt_skel.has_bone(bind.bone_1_correction_bone):
		bind.correction_length_1 = (virt_skel.get_bone_position(bind.bone_1_correction_bone) - virt_skel.get_bone_position(bind.bone_1)).length()
	if virt_skel.has_bone(bind.bone_2_correction_bone):
		bind.correction_length_2 = (virt_skel.get_bone_position(bind.bone_2_correction_bone) - virt_skel.get_bone_position(bind.bone_2)).length()
	if virt_skel.has_bone(bind.bone_3_correction_bone):
		bind.correction_length_3 = (virt_skel.get_bone_position(bind.bone_3_correction_bone) - virt_skel.get_bone_position(bind.bone_3)).length()
	
	bind.bind_id = _binds.size()
	_binds.push_back(bind)
	virt_skel.set_bone_modifier(VOID_ID, VirtualSkeleton.MODIFIER.BIND, bind)

## Validate and register a fork bind node
func _eval_fork_bind_node(fork_bind: Node) -> void:
	# Validate all bones exist
	if not virt_skel.has_bone(fork_bind.bone_target):
		push_error("IK Fork Bind [" + fork_bind.name + "] ignored. Target Bone ID [" + fork_bind.bone_target + "] is invalid.")
		return
	if not virt_skel.has_bone(fork_bind.bone_1):
		push_error("IK Fork Bind [" + fork_bind.name + "] ignored. Bone 1 ID [" + fork_bind.bone_1 + "] is invalid.")
		return
	if not virt_skel.has_bone(fork_bind.bone_2):
		push_error("IK Fork Bind [" + fork_bind.name + "] ignored. Bone 2 ID [" + fork_bind.bone_2 + "] is invalid.")
		return
	if not virt_skel.has_bone(fork_bind.bone_3):
		push_error("IK Fork Bind [" + fork_bind.name + "] ignored. Bone 3 ID [" + fork_bind.bone_3 + "] is invalid.")
		return
	
	# Calculate distances from each bone to target
	fork_bind.length_1 = (virt_skel.get_bone_position(fork_bind.bone_1) - virt_skel.get_bone_position(fork_bind.bone_target)).length()
	fork_bind.length_2 = (virt_skel.get_bone_position(fork_bind.bone_2) - virt_skel.get_bone_position(fork_bind.bone_target)).length()
	fork_bind.length_3 = (virt_skel.get_bone_position(fork_bind.bone_3) - virt_skel.get_bone_position(fork_bind.bone_target)).length()
	
	fork_bind.bind_id = _fork_binds.size()
	_fork_binds.push_back(fork_bind)
	virt_skel.set_bone_modifier(VOID_ID, VirtualSkeleton.MODIFIER.FORK_BIND, fork_bind)

## Validate and register a cage bind node (complex constraint)
func _eval_cage_bind_node(cage: Node) -> void:
	# Validate all bones exist
	if not virt_skel.has_bone(cage.backbone_1):
		push_error("IK Cage Bind [" + cage.name + "] ignored. Backbone 1 ID [" + cage.backbone_1 + "] is invalid.")
		return
	if not virt_skel.has_bone(cage.backbone_2):
		push_error("IK Cage Bind [" + cage.name + "] ignored. Backbone 2 ID [" + cage.backbone_2 + "] is invalid.")
		return
	if not virt_skel.has_bone(cage.target_bone_1):
		push_error("IK Cage Bind [" + cage.name + "] ignored. Target Bone 1 ID [" + cage.target_bone_1 + "] is invalid.")
		return
	if not virt_skel.has_bone(cage.target_bone_2):
		push_error("IK Cage Bind [" + cage.name + "] ignored. Target Bone 2 ID [" + cage.target_bone_2 + "] is invalid.")
		return
	
	# Calculate all distance constraints for the cage
	cage.b1b2_length = (virt_skel.get_bone_position(cage.backbone_1) - virt_skel.get_bone_position(cage.backbone_2)).length()
	cage.b1t1_length = (virt_skel.get_bone_position(cage.backbone_1) - virt_skel.get_bone_position(cage.target_bone_1)).length()
	cage.b1t2_length = (virt_skel.get_bone_position(cage.backbone_1) - virt_skel.get_bone_position(cage.target_bone_2)).length()
	cage.b2t1_length = (virt_skel.get_bone_position(cage.backbone_2) - virt_skel.get_bone_position(cage.target_bone_1)).length()
	cage.b2t2_length = (virt_skel.get_bone_position(cage.backbone_2) - virt_skel.get_bone_position(cage.target_bone_2)).length()
	cage.t1t2_length = (virt_skel.get_bone_position(cage.target_bone_1) - virt_skel.get_bone_position(cage.target_bone_2)).length()
	
	# Calculate correction bone lengths
	if virt_skel.has_bone(cage.backbone_2_correction):
		cage.b2_correction_length = (virt_skel.get_bone_position(cage.backbone_2) - virt_skel.get_bone_position(cage.backbone_2_correction)).length()
	if virt_skel.has_bone(cage.target_bone_1_correction):
		cage.t1_correction_length = (virt_skel.get_bone_position(cage.target_bone_1) - virt_skel.get_bone_position(cage.target_bone_1_correction)).length()
	if virt_skel.has_bone(cage.target_bone_2_correction):
		cage.t2_correction_length = (virt_skel.get_bone_position(cage.target_bone_2) - virt_skel.get_bone_position(cage.target_bone_2_correction)).length()
	
	cage.bind_id = _cage_binds.size()
	_cage_binds.push_back(cage)
	virt_skel.set_bone_modifier(VOID_ID, VirtualSkeleton.MODIFIER.CAGE_BIND, cage)
#endregion

#region Main Solver Loop
## Main physics process - runs the IK solver each frame
func _physics_process(_delta: float) -> void:
	if enabled and skel != null and virt_skel != null:
		var inverse_transform: Transform3D = skel.get_global_transform().affine_inverse()
		
		# Solve in order: chains -> poles -> look-ats -> forward pass
		solve_chains(inverse_transform)
		solve_poles(inverse_transform)
		solve_look_ats(inverse_transform)
		total_pass()
		
		# Apply results to real skeleton
		virt_skel.bake()

## Solve all chain constraints using FABRIK algorithm
func solve_chains(inverse_transform: Transform3D) -> void:
	var diff: float = 0.0
	
	# Calculate total distance error
	for chain in _chains:
		diff += virt_skel.get_bone_position(chain.tip_bone_id).distance_squared_to(inverse_transform * chain.get_target().origin)
	
	var iterations_remaining: int = max_iterations
	var min_dist_sq: float = minimal_distance * minimal_distance * _chains.size()
	
	# Iterate until convergence or max iterations
	while iterations_remaining > 0 and diff > min_dist_sq:
		# Backward pass - pull toward targets
		for chain in _chains:
			solve_backwards(
				chain.root_bone_id,
				chain.tip_bone_id,
				inverse_transform * chain.get_target(),
				chain.pull_strength
			)
		
		# Forward pass - maintain bone lengths
		total_pass()
		
		# Recalculate error
		diff = 0.0
		for chain in _chains:
			diff += virt_skel.get_bone_position(chain.tip_bone_id).distance_squared_to(inverse_transform * chain.get_target().origin)
		
		iterations_remaining -= 1

## Solve all pole constraints
func solve_poles(inverse_transform: Transform3D) -> void:
	for pole in _poles:
		solve_pole(
			str(pole.root_bone_id),
			str(pole.tip_bone_id),
			inverse_transform * pole.get_target().origin,
			pole.turn_to
		)

## Solve all look-at constraints
func solve_look_ats(inverse_transform: Transform3D) -> void:
	for look_at in _look_ats:
		solve_look_at(
			look_at.bone_id,
			inverse_transform * look_at.get_target().origin,
			look_at.look_from_side,
			look_at.get("up_down_spin_override_angle")
		)

## Forward pass to maintain bone lengths and apply constraints
func total_pass() -> void:
	# Apply chain pull forces
	for chain in _chains:
		solve_backwards(
			chain.root_bone_id,
			chain.tip_bone_id,
			Transform3D(virt_skel.get_bone_rotation(chain.tip_bone_id), virt_skel.get_bone_position(chain.tip_bone_id)),
			chain.pull_strength
		)
	
	# Forward pass from each root
	for root in virt_skel.roots:
		if virt_skel.bones.has(root):
			solve_forwards(root, virt_skel.bones[root].initial_position)
#endregion

#region Constraint Solvers
## Solve bind constraints for a bone
func solve_binds(bone_id: String) -> void:
	var modifier_flags: int = virt_skel.get_bone_modifiers(bone_id)
	
	# Phase 1: Solve reverse forks first
	if modifier_flags & VirtualSkeleton.MODIFIER.FORK_BIND:
		for i in virt_skel.get_bone_fork_bind_ids(bone_id):
			if _fork_binds[i].reverse_fork:
				solve_fork(
					_fork_binds[i].bone_1, _fork_binds[i].bone_2, _fork_binds[i].bone_3, _fork_binds[i].bone_target,
					_fork_binds[i].length_1, _fork_binds[i].length_2, _fork_binds[i].length_3, true
				)
	
	# Phase 2: Solve cage constraints (complex loop solver)
	if modifier_flags & VirtualSkeleton.MODIFIER.CAGE_BIND:
		var c: Node = _cage_binds[virt_skel.get_bone_cage_bind_id(bone_id)]
		
		# Multiple loop solving passes for cage constraint
		solve_loop(c.target_bone_2, c.backbone_2, c.target_bone_1,
			c.target_bone_2_correction, c.backbone_2_correction, c.target_bone_1_correction,
			c.t1t2_length, c.b2t1_length, c.b1t1_length,
			c.t2_correction_length, c.b2_correction_length, c.t1_correction_length)
		
		solve_loop(c.backbone_1, c.backbone_2, c.target_bone_1,
			VOID_ID, c.backbone_2_correction, c.target_bone_1_correction,
			c.b1b2_length, c.b2t1_length, c.b1t1_length,
			0.0, c.b2_correction_length, c.t1_correction_length)
		
		solve_loop(c.backbone_1, c.target_bone_1, c.target_bone_2,
			VOID_ID, c.target_bone_1_correction, c.target_bone_2_correction,
			c.b1b2_length, c.b1t1_length, c.t1t2_length,
			0.0, c.t1_correction_length, c.t2_correction_length)
		
		solve_loop(c.backbone_1, c.target_bone_2, c.backbone_2,
			VOID_ID, c.target_bone_2_correction, c.backbone_2_correction,
			c.b1b2_length, c.t1t2_length, c.b2t1_length,
			0.0, c.t2_correction_length, c.b2_correction_length)
		
		solve_loop(c.target_bone_2, c.backbone_2, c.target_bone_1,
			VOID_ID, VOID_ID, VOID_ID,
			c.t1t2_length, c.b2t1_length, c.b1t1_length,
			0.0, 0.0, 0.0)
	
	# Phase 3: Solve triangular bind constraints
	if modifier_flags & VirtualSkeleton.MODIFIER.BIND:
		for i in virt_skel.get_bone_bind_ids(bone_id):
			var bind: Node = _binds[i]
			solve_loop(
				bind.bone_1, bind.bone_2, bind.bone_3,
				bind.bone_1_correction_bone, bind.bone_2_correction_bone, bind.bone_3_correction_bone,
				bind.length_12, bind.length_23, bind.length_31,
				bind.correction_length_1, bind.correction_length_2, bind.correction_length_3
			)
	
	# Phase 4: Solve normal fork constraints
	if modifier_flags & VirtualSkeleton.MODIFIER.FORK_BIND:
		for i in virt_skel.get_bone_fork_bind_ids(bone_id):
			var fork: Node = _fork_binds[i]
			solve_fork(
				fork.bone_1, fork.bone_2, fork.bone_3, fork.bone_target,
				fork.length_1, fork.length_2, fork.length_3, false
			)
#endregion

#region Core FABRIK Algorithms
## FABRIK backward pass - pull bones toward target
func solve_backwards(root_id: String, tip_id: String, target: Transform3D, weight: float) -> void:
	if not virt_skel.has_bone(tip_id):
		return
	
	# Set tip rotation if it's a leaf bone
	if virt_skel.get_bone_children_count(tip_id) == 0:
		virt_skel.set_bone_rotation(tip_id, target.basis.get_rotation_quaternion())
	
	var current_bone: String = tip_id
	var current_target: Vector3 = target.origin
	var stop_bone: String = virt_skel.get_bone_parent(root_id)
	
	# Walk up the chain, pulling each bone toward the target
	while current_bone != stop_bone and virt_skel.get_bone_parent(current_bone) != VOID_ID:
		virt_skel.set_biassed_bone_position(current_bone, current_target, weight)
		
		# Calculate next target position maintaining bone length
		var parent_id: String = virt_skel.get_bone_parent(current_bone)
		current_target = calc_next(
			virt_skel.get_bone_position(current_bone),
			virt_skel.get_bone_position(parent_id),
			virt_skel.get_bone_length(current_bone)
		)
		current_bone = parent_id

## FABRIK forward pass - maintain hierarchy and bone lengths
func solve_forwards(root_id: String, origin: Vector3) -> void:
	if not virt_skel.has_bone(root_id) or root_id == VOID_ID:
		return
	
	var subbase_queue: PackedStringArray = PackedStringArray(virt_skel.get_bone_children(root_id))
	virt_skel.set_bone_position(root_id, origin)
	
	# Handle root constraints
	if virt_skel.get_bone_modifiers(root_id) & (VirtualSkeleton.MODIFIER.BIND | VirtualSkeleton.MODIFIER.FORK_BIND | VirtualSkeleton.MODIFIER.CAGE_BIND):
		solve_binds(root_id)
	
	if subbase_queue.is_empty():
		return
	
	var previous_bone: String = root_id
	var current_bone: String = subbase_queue[0]
	subbase_queue.remove_at(0)
	
	# Process bones in breadth-first order
	while current_bone != "-1":
		var modifier_flags: int = virt_skel.get_bone_modifiers(current_bone)
		
		# Apply position based on modifier type
		if modifier_flags == VirtualSkeleton.MODIFIER.NONE:
			# Standard bone positioning
			virt_skel.set_bone_position(current_bone, calc_next(
				virt_skel.get_bone_position(previous_bone),
				virt_skel.get_bone_position(current_bone),
				virt_skel.get_bone_length(current_bone)
			))
		elif modifier_flags & (VirtualSkeleton.MODIFIER.BIND | VirtualSkeleton.MODIFIER.FORK_BIND | VirtualSkeleton.MODIFIER.CAGE_BIND):
			# Constraint bone positioning
			virt_skel.set_bone_position(current_bone, calc_next(
				virt_skel.get_bone_position(previous_bone),
				virt_skel.get_bone_position(current_bone),
				virt_skel.get_bone_length(current_bone)
			))
			solve_binds(current_bone)
		elif modifier_flags & VirtualSkeleton.MODIFIER.SOLID:
			# Solid bone positioning (maintains original direction)
			var master_bone: String = virt_skel.get_bone_modifier_master(current_bone)
			var master_parent: String = virt_skel.get_bone_parent(master_bone)
			virt_skel.set_bone_position(current_bone,
				virt_skel.get_bone_position(previous_bone) +
				(virt_skel.get_bone_rotation(master_parent) * virt_skel.get_bone_start_direction(current_bone)) *
				virt_skel.get_bone_length(current_bone)
			)
		elif modifier_flags & VirtualSkeleton.MODIFIER.DAMPED_TRANSFORM:
			# Physics-based bone positioning
			if virt_skel.get_bone_modifier_master(current_bone) != current_bone:
				var data: Array = virt_skel.get_bone_damped_transform(current_bone)
				var master_bone: String = virt_skel.get_bone_modifier_master(current_bone)
				var master_parent: String = virt_skel.get_bone_parent(master_bone)
				
				var target_pos: Vector3 = virt_skel.get_bone_position(previous_bone) + (virt_skel.get_bone_rotation(master_parent) * virt_skel.get_bone_start_direction(current_bone).normalized()) * virt_skel.get_bone_length(current_bone)
				
				# Apply spring physics
				var force: Vector3 = (target_pos - virt_skel.get_bone_position(current_bone)) * data[0]  # stiffness
				force.y -= data[3]  # gravity
				var acceleration: Vector3 = force / data[1]  # mass
				var velocity: Vector3 = virt_skel.add_velocity_to_bone(current_bone, acceleration * (1.0 - data[2]))  # damping
				
				virt_skel.set_bone_position(current_bone, calc_next(
					virt_skel.get_bone_position(previous_bone),
					virt_skel.get_bone_position(current_bone) + velocity + force,
					virt_skel.get_bone_length(current_bone)
				))
		
		# Calculate bone rotation (if not look-at controlled)
		if previous_bone != VOID_ID and not (modifier_flags & VirtualSkeleton.MODIFIER.LOOK_AT):
			var rotation: Quaternion
			
			if virt_skel.get_bone_children_count(previous_bone) > 1:
				# Multi-child bone - weighted average rotation
				var wsum: float = 0.0
				rotation = Quaternion.IDENTITY
				
				for child in virt_skel.get_bone_children(previous_bone):
					var weight: float = virt_skel.get_bone_weight(child)
					if weight == 0.0:
						weight = 1.0
					wsum += weight
					rotation += from_to_rotation(
						virt_skel.get_bone_start_direction(previous_bone),
						(virt_skel.get_bone_position(child) - virt_skel.get_bone_position(previous_bone)).normalized()
					) * weight
				
				if wsum > 0.0:
					rotation /= wsum
			else:
				# Single child bone - direct rotation
				rotation = from_to_rotation(
					virt_skel.get_bone_start_direction(current_bone),
					(virt_skel.get_bone_position(current_bone) - virt_skel.get_bone_position(previous_bone)).normalized()
				)
			
			virt_skel.set_bone_rotation(previous_bone, rotation * virt_skel.get_bone_start_rotation(previous_bone))
		
		# Add children to queue
		subbase_queue.append_array(PackedStringArray(virt_skel.get_bone_children(current_bone)))
		
		# Move to next bone
		if not subbase_queue.is_empty():
			current_bone = subbase_queue[0]
			previous_bone = virt_skel.get_bone_parent(current_bone)
			subbase_queue.remove_at(0)
		else:
			current_bone = "-1"
			virt_skel.wipe_weights()  # Clear weights for next iteration
#endregion

#region Specialized Solvers
## Solve look-at constraint to make bone face target
func solve_look_at(bone_id: String, target: Vector3, side: int, spin_override: float) -> void:
	var parent_id: String = virt_skel.get_bone_parent(bone_id)
	var pivot: Vector3 = virt_skel.get_bone_position(parent_id)
	var start_dir: Vector3 = virt_skel.get_bone_start_direction(bone_id)
	var target_dir: Vector3 = target - pivot
	var rotation: Quaternion
	var spin_angle: float
	
	match side:
		0: # UP
			rotation = from_to_rotation(start_dir, target_dir.normalized()) * virt_skel.get_bone_start_rotation(parent_id)
			spin_angle = deg_to_rad(spin_override)
		1: # DOWN
			rotation = from_to_rotation(start_dir, -target_dir.normalized()) * virt_skel.get_bone_start_rotation(parent_id)
			spin_angle = deg_to_rad(spin_override)
		_: # DIRECTIONAL (LEFT, RIGHT, FORWARD, BACK)
			var rot_axis: Vector3 = start_dir.cross(target_dir).normalized()
			var a: float = virt_skel.get_bone_length(bone_id) / 2.0
			var b: float = target_dir.length()
			var rot_angle: float = -acos(clamp(a / b, -1.0, 1.0))
			
			rotation = from_to_rotation(start_dir, Quaternion(rot_axis, rot_angle) * target_dir) * virt_skel.get_bone_start_rotation(parent_id)
			
			var sp := Plane(rotation * Vector3.UP, 0.0)
			match side:
				4: # FORWARD
					spin_angle = signed_angle(rotation * Vector3.FORWARD, sp.project(target_dir.normalized()), sp.normal)
				2: # LEFT
					spin_angle = signed_angle(rotation * Vector3.LEFT, sp.project(target_dir), sp.normal)
				5: # BACK
					spin_angle = signed_angle(rotation * Vector3.BACK, sp.project(target_dir), sp.normal)
				_: # RIGHT
					spin_angle = signed_angle(rotation * Vector3.RIGHT, sp.project(target_dir), sp.normal)
	
	virt_skel.set_bone_rotation(parent_id, Quaternion(rotation * Vector3.UP, spin_angle) * rotation)
	virt_skel.set_bone_position(bone_id,
		pivot + (rotation * virt_skel.get_bone_start_direction(bone_id).normalized()) * virt_skel.get_bone_length(bone_id))

## Solve triangular loop constraint (bind constraint)
func solve_loop(
	b1_id: String, b2_id: String, b3_id: String,
	b1_correction: String, b2_correction: String, b3_correction: String,
	b1_b2_length: float, b2_b3_length: float, b3_b1_length: float,
	b1_correction_length: float, b2_correction_length: float, b3_correction_length: float
) -> void:
	# Phase 1: Initial constraint satisfaction
	virt_skel.set_bone_position(b2_id, calc_next(virt_skel.get_bone_position(b1_id), virt_skel.get_bone_position(b2_id), b1_b2_length))
	virt_skel.set_bone_position(b3_id, calc_next(virt_skel.get_bone_position(b2_id), virt_skel.get_bone_position(b3_id), b2_b3_length))
	
	if b1_correction != VOID_ID:
		virt_skel.set_bone_position(b1_id, calc_next(virt_skel.get_bone_position(b3_id), virt_skel.get_bone_position(b1_id), b3_b1_length))
		virt_skel.set_bone_position(b2_id, calc_next(virt_skel.get_bone_position(b1_id), virt_skel.get_bone_position(b2_id), b1_b2_length))
	
	# Phase 2: Reverse constraint satisfaction
	virt_skel.set_bone_position(b3_id, calc_next(virt_skel.get_bone_position(b1_id), virt_skel.get_bone_position(b3_id), b3_b1_length))
	virt_skel.set_bone_position(b2_id, calc_next(virt_skel.get_bone_position(b3_id), virt_skel.get_bone_position(b2_id), b2_b3_length))
	
	# Phase 3: Correction bone constraints
	if b1_correction != VOID_ID:
		virt_skel.set_bone_position(b1_id, calc_next(virt_skel.get_bone_position(b1_correction), virt_skel.get_bone_position(b1_id), b1_correction_length))
	
	if b2_correction != VOID_ID:
		virt_skel.set_bone_position(b2_id, calc_next(virt_skel.get_bone_position(b1_id), virt_skel.get_bone_position(b2_id), b1_b2_length))
		virt_skel.set_bone_position(b2_id, calc_next(virt_skel.get_bone_position(b2_correction), virt_skel.get_bone_position(b2_id), b2_correction_length))
	
	if b3_correction != VOID_ID:
		virt_skel.set_bone_position(b3_id, calc_next(virt_skel.get_bone_position(b1_id), virt_skel.get_bone_position(b3_id), b3_b1_length))
		virt_skel.set_bone_position(b3_id, calc_next(virt_skel.get_bone_position(b3_correction), virt_skel.get_bone_position(b3_id), b3_correction_length))
	
	# Phase 4: Final stabilization passes
	virt_skel.set_bone_position(b2_id, calc_next(virt_skel.get_bone_position(b1_id), virt_skel.get_bone_position(b2_id), b1_b2_length))
	virt_skel.set_bone_position(b3_id, calc_next(virt_skel.get_bone_position(b2_id), virt_skel.get_bone_position(b3_id), b2_b3_length))
	virt_skel.set_bone_position(b3_id, calc_next(virt_skel.get_bone_position(b1_id), virt_skel.get_bone_position(b3_id), b3_b1_length))
	virt_skel.set_bone_position(b2_id, calc_next(virt_skel.get_bone_position(b3_id), virt_skel.get_bone_position(b2_id), b2_b3_length))
	virt_skel.set_bone_position(b2_id, calc_next(virt_skel.get_bone_position(b1_id), virt_skel.get_bone_position(b2_id), b1_b2_length))

## Solve fork constraint
func solve_fork(
	bone_1_id: String, bone_2_id: String, bone_3_id: String, bone_target_id: String,
	length_1: float, length_2: float, length_3: float, reverse_fork: bool
) -> void:
	# Correct target position to maintain distance from bone_1
	virt_skel.set_bone_position(bone_target_id, calc_next(
		virt_skel.get_bone_position(bone_1_id),
		virt_skel.get_bone_position(bone_target_id),
		length_1
	))
	
	if reverse_fork:
		# Pull bones toward target
		virt_skel.set_bone_position(bone_2_id, calc_next(
			virt_skel.get_bone_position(bone_target_id),
			virt_skel.get_bone_position(bone_2_id),
			length_2
		))
		virt_skel.set_bone_position(bone_3_id, calc_next(
			virt_skel.get_bone_position(bone_target_id),
			virt_skel.get_bone_position(bone_3_id),
			length_3
		))
	else:
		# Pull target toward bones
		virt_skel.set_bone_position(bone_target_id, calc_next(
			virt_skel.get_bone_position(bone_2_id),
			virt_skel.get_bone_position(bone_target_id),
			length_2
		))
		virt_skel.set_bone_position(bone_target_id, calc_next(
			virt_skel.get_bone_position(bone_3_id),
			virt_skel.get_bone_position(bone_target_id),
			length_3
		))

## Solve pole constraint to control joint bending direction
func solve_pole(root_id: String, tip_id: String, target: Vector3, side: int) -> void:
	if not virt_skel.has_bone(root_id) and root_id != VOID_ID:
		return
	
	var stop_bone: String = virt_skel.get_bone_parent(root_id)
	var previous_bone: String = tip_id
	var current_bone: String = virt_skel.get_bone_parent(previous_bone)
	var next_bone: String = virt_skel.get_bone_parent(current_bone)
	
	# Walk up the chain, rotating joints toward the pole
	while next_bone != stop_bone and current_bone != root_id:
		# Create plane perpendicular to bone chain
		var norm: Vector3 = (virt_skel.get_bone_position(previous_bone) - virt_skel.get_bone_position(next_bone)).normalized()
		var plane := Plane(norm, 0.0)
		plane.d = plane.distance_to(virt_skel.get_bone_position(previous_bone))
		
		# Project target and current position onto plane
		var proj_target: Vector3 = plane.project(target)
		var proj_current: Vector3 = plane.project(virt_skel.get_bone_position(current_bone))
		
		# Calculate rotation angle to align with pole
		var angle: float = signed_angle(
			proj_current - virt_skel.get_bone_position(previous_bone),
			proj_target - virt_skel.get_bone_position(previous_bone),
			norm
		)
		
		# Apply rotation
		virt_skel.set_bone_position(current_bone,
			Quaternion(norm, angle) * (virt_skel.get_bone_position(current_bone) - virt_skel.get_bone_position(previous_bone)) +
			virt_skel.get_bone_position(previous_bone)
		)
		
		# Calculate and apply bone rotation
		var start_dir: Vector3 = virt_skel.get_bone_start_direction(current_bone)
		var target_dir: Vector3 = (virt_skel.get_bone_position(next_bone) - virt_skel.get_bone_position(current_bone)).normalized()
		var rot_quat: Quaternion = from_to_rotation(start_dir, target_dir)
		
		virt_skel.set_bone_rotation(current_bone, rotate_along_axis(rot_quat, virt_skel.get_bone_position(current_bone), target, side))
		
		# Move to next bone in chain
		previous_bone = current_bone
		current_bone = next_bone
		next_bone = virt_skel.get_bone_parent(next_bone)
#endregion

#region Mathematical Utilities
## Calculate signed angle between two vectors around an axis
static func signed_angle(from: Vector3, to: Vector3, axis: Vector3) -> float:
	var plane := Plane(axis.cross(from), 0.0)
	if plane.is_point_over(to):
		return from.angle_to(to)
	else:
		return -from.angle_to(to)

## Calculate next position maintaining distance constraint
static func calc_next(from: Vector3, to: Vector3, length: float) -> Vector3:
	return from + (to - from).normalized() * length

## Create rotation quaternion from one direction to another
static func from_to_rotation(from: Vector3, to: Vector3) -> Quaternion:
	var k_cos_theta: float = from.dot(to)
	var k: float = sqrt(from.length_squared() * to.length_squared())
	
	if k_cos_theta / k == -1.0:
		# 180 degree rotation - find perpendicular axis
		var orthogonal: Vector3 = Vector3.UP
		if abs(from.dot(Vector3.UP)) > 0.9:
			orthogonal = Vector3.RIGHT
		return Quaternion(from.cross(orthogonal).normalized(), PI)
	elif k_cos_theta / k == 1.0:
		return Quaternion.IDENTITY
	
	var axis: Vector3 = from.cross(to)
	return Quaternion(axis.x, axis.y, axis.z, k_cos_theta + k).normalized()

## Rotate quaternion around an axis to face target
static func rotate_along_axis(rotation: Quaternion, pivot: Vector3, target: Vector3, side: int) -> Quaternion:
	var plane := Plane(rotation * Vector3.UP, 0.0)
	plane.d = plane.distance_to(pivot)
	var proj_target: Vector3 = plane.project(target)
	var proj_vector: Vector3
	
	match side:
		0: # FORWARD
			proj_vector = plane.project(rotation * Vector3.FORWARD + pivot)
		1: # BACKWARD
			proj_vector = plane.project(rotation * Vector3.BACK + pivot)
		2: # RIGHT
			proj_vector = plane.project(rotation * Vector3.RIGHT + pivot)
		_: # LEFT
			proj_vector = plane.project(rotation * Vector3.LEFT + pivot)
	
	var angle: float = signed_angle(
		proj_vector - pivot,
		proj_target - pivot,
		plane.normal
	)
	
	return Quaternion(plane.normal, angle) * rotation
#endregion

#region Signal Handlers and Editor Integration
## Handle exaggerator length changes
func _on_exaggerator_change(bone_id: String, length_multiplier: float) -> void:
	if virt_skel != null:
		virt_skel.set_bone_length_multiplier(bone_id, length_multiplier)

## Override add_child to automatically connect signals
func add_child(node: Node, force_readable_name: bool = false, internal: int = 0) -> void:  # Updated signature
	super.add_child(node, force_readable_name, internal)
	connect_signals(node)

## Connect bone name update signals to child nodes
func connect_signals(node: Node) -> void:
	if node.has_method("_update_parameters"):
		if not bone_names_obtained.is_connected(node._update_parameters):
			bone_names_obtained.connect(node._update_parameters)
		bone_names_obtained.emit(_bone_names_4_children)
#endregion
