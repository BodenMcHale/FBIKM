@tool
extends Node
const FBIKM_NODE_ID = 0  # THIS NODE'S IDENTIFIER

"""
	FBIKM - Inverse Kinematics Manager
		by Nemo Czanderlitch/Nino Čandrlić
			@R3X-G1L       (godot assets store)
			R3X-G1L6AME5H  (github)
		
		Updated for Godot 4.4.1 - Fixed bone access to use integer indices
"""

## CONSTANTS ###############################################################################################
const VirtualSkeleton = preload("VirtualSkeleton.gd")

### ALL OTHER NODES' IDS
const FBIKM_CHAIN            = 1
const FBIKM_POLE             = 2
const FBIKM_LOOK_AT          = 3
const FBIKM_BIND             = 4
const FBIKM_FORK_BIND        = 5
const FBIKM_EXAGGERATOR      = 6
const FBIKM_SOLIDIFIER       = 7
const FBIKM_DAMPED_TRANSFORM = 8
const FBIKM_CAGE             = 9

const VOID_ID = "-1"

var _bone_names_4_children := "VOID:-1"
signal bone_names_obtained(bone_names: String)

## PARAMETERS ##############################################################################################
@export var enabled: bool = false : set = _tick_enabled
@export var skeleton: NodePath : set = _set_skeleton

## FABRIK CONSTRAINTS
@export var max_iterations: int = 5
@export var minimal_distance: float = 0.01

### Debug ###
var DEBUG_dump_bones = false
var DEBUG_bone_property = ""
var DEBUG_entry_count = -1

#### RUNTIME ENVIRONMENT - Fixed for Godot 4.4.1
func _set_skeleton(path_2_skel: NodePath) -> void:
	if Engine.is_editor_hint():
		# Set up in-editor environment
		var _temp = get_node_or_null(path_2_skel)
		if _temp is Skeleton3D:
			skeleton = path_2_skel
			
			# Validate skeleton has bones
			if _temp.get_bone_count() == 0:
				push_warning("Skeleton has no bones: " + str(path_2_skel))
				_bone_names_4_children = "VOID:-1"
				bone_names_obtained.emit(_bone_names_4_children)
				return

			## Build bone names list for dropdown menus - Fixed method
			_bone_names_4_children = "VOID:-1,"
			var bone_count: int = _temp.get_bone_count()
			
			for i in range(bone_count):
				var bone_name = _temp.get_bone_name(i)
				# Validate bone name
				if bone_name != "":
					_bone_names_4_children += bone_name + ":" + str(i) + ","
			
			# Remove trailing comma
			_bone_names_4_children = _bone_names_4_children.rstrip(",")
			
			print("Found ", bone_count, " bones in skeleton")
			print("Bone names string: ", _bone_names_4_children)
			
			# Emit signal to update children's dropdown menus
			bone_names_obtained.emit(_bone_names_4_children)

			# Build virtual skeleton
			if _build_virtual_skeleton(true) == OK:
				# Connect signals to existing children
				for c in get_children():
					connect_signals(c)
				bone_names_obtained.emit(_bone_names_4_children)

				_reevaluate_drivers()
			else:
				push_error("Failed to build virtual skeleton")

		else:
			## if no skeleton clear all the memory
			skeleton = NodePath()
			_wipe_drivers()
			virt_skel = null
			_bone_names_4_children = "VOID:-1"
			bone_names_obtained.emit(_bone_names_4_children)
	else:
		## no need to set up anything if the plugin is ran in-game
		skeleton = path_2_skel

func _tick_enabled(enable: bool) -> void:
	enabled = enable
	if enabled == false and virt_skel != null:
		if DEBUG_dump_bones: 
			virt_skel.cshow(DEBUG_bone_property, DEBUG_entry_count)
		virt_skel.revert()

func _wipe_drivers() -> void:
	_chains.clear()
	_poles.clear()
	_look_ats.clear()
	_binds.clear()
	_fork_binds.clear()
	_cage_binds.clear()
	if virt_skel:
		virt_skel.wipe_modifiers()

func _build_virtual_skeleton(in_editor: bool) -> int:
	skel = get_node_or_null(skeleton)
	if skel == null:
		push_error("Skeleton in " + self.name + " never assigned.")
		enabled = false
		return FAILED
	if skel.get_bone_count() == 0:
		push_error("Skeleton in " + self.name + " has no bones.")
		enabled = false
		return FAILED
		
	virt_skel = VirtualSkeleton.new(skel, in_editor)
	return OK

## GLOBAL VARIABLES ########################################################################################
var skel: Skeleton3D
var virt_skel: VirtualSkeleton

## all the possible drivers that need to be ran
var _chains: Array[Node] = []
var _poles: Array[Node] = []
var _look_ats: Array[Node] = []
var _binds: Array[Node] = []
var _fork_binds: Array[Node] = []
var _cage_binds: Array[Node] = []

## INIT ####################################################################################################
func _ready() -> void:
	if not Engine.is_editor_hint(): ## Execute in game
		if _build_virtual_skeleton(false) == OK:
			_evaluate_drivers()

			if DEBUG_dump_bones:
				virt_skel.cshow()

## LOAD AND ORGANIZE THE DRIVERS - Fixed validation
func _evaluate_drivers() -> void:
	if virt_skel == null:
		push_error("Tried to evaluate drivers but failed because there was no Skeleton Node assigned.")
		return

	## run the evaluation relevant to the node processed
	for node in self.get_children():
		if node.has_method("get") and node.get("FBIKM_NODE_ID") != null:
			match(node.FBIKM_NODE_ID):
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

## WIPE, THEN LOAD THE DRIVERS
func _reevaluate_drivers() -> void:
	_wipe_drivers()
	_evaluate_drivers()

## VALIDATION HELPERS - Fixed to handle bone name -> index conversion
func _convert_bone_name_to_id(bone_name_or_id: String) -> String:
	"""Convert bone name to bone index string. If already an index, return as-is."""
	if bone_name_or_id == VOID_ID or bone_name_or_id == "-1":
		return "-1"
	
	# Check if it's already a numeric ID
	if bone_name_or_id.is_valid_int():
		var bone_idx = int(bone_name_or_id)
		if bone_idx >= 0 and bone_idx < skel.get_bone_count():
			return bone_name_or_id
		else:
			return "-1"
	
	# It's a bone name, convert to index
	var bone_idx = skel.find_bone(bone_name_or_id)
	if bone_idx >= 0:
		return str(bone_idx)
	else:
		print("Could not find bone: ", bone_name_or_id)
		return "-1"

func _is_valid_bone_id(bone_id: String) -> bool:
	var converted_id = _convert_bone_name_to_id(bone_id)
	if converted_id == "-1":
		return false
	if not virt_skel.has_bone(converted_id):
		return false
	return true

func _get_bone_name_from_id(bone_id: String) -> String:
	if not skel or bone_id == VOID_ID:
		return "UNKNOWN"
	
	var converted_id = _convert_bone_name_to_id(bone_id)
	if converted_id == "-1":
		return "INVALID_ID"
		
	var bone_idx = int(converted_id)
	if bone_idx >= 0 and bone_idx < skel.get_bone_count():
		return skel.get_bone_name(bone_idx)
	return "INVALID_ID"

## CHECKS, AND ASSIGNMENTS FOR DRIVERS - Fixed validation
func _eval_chain_node(chain: Node) -> void:
	# Convert bone names to indices if needed
	chain.tip_bone_id = _convert_bone_name_to_id(chain.tip_bone_id)
	chain.root_bone_id = _convert_bone_name_to_id(chain.root_bone_id)
	
	if not _is_valid_bone_id(chain.tip_bone_id):
		push_error("IK Chain [" + chain.name + "] ignored. Couldn't find the bone with id [" + chain.tip_bone_id + "] (" + _get_bone_name_from_id(chain.tip_bone_id) + ")")
		return
	if not _is_valid_bone_id(chain.root_bone_id):
		push_error("IK Chain [" + chain.name + "] ignored. Couldn't find the bone with id [" + chain.root_bone_id + "] (" + _get_bone_name_from_id(chain.root_bone_id) + ")")
		return
	self._chains.push_back(chain)
	print("Added IK Chain: tip=" + _get_bone_name_from_id(chain.tip_bone_id) + ", root=" + _get_bone_name_from_id(chain.root_bone_id))

func _eval_pole_node(pole: Node) -> void:
	# Convert bone names to indices if needed
	pole.tip_bone_id = _convert_bone_name_to_id(pole.tip_bone_id)
	pole.root_bone_id = _convert_bone_name_to_id(pole.root_bone_id)
	
	if not _is_valid_bone_id(pole.tip_bone_id):
		push_error("IK Pole [" + pole.name + "] ignored. Couldn't find the bone with id [" + pole.tip_bone_id + "] (" + _get_bone_name_from_id(pole.tip_bone_id) + ")")
		return
	if not _is_valid_bone_id(pole.root_bone_id):
		push_error("IK Pole [" + pole.name + "] ignored. Couldn't find the bone with id [" + pole.root_bone_id + "] (" + _get_bone_name_from_id(pole.root_bone_id) + ")")
		return
	
	if virt_skel.get_bone_parent(pole.tip_bone_id) == "-1" or virt_skel.get_bone_parent(virt_skel.get_bone_parent(pole.tip_bone_id)) == "-1":
		push_error("IK Pole [" + pole.name + "] ignored. Chain too short.")
		return
	
	self._poles.push_back(pole)
	print("Added IK Pole: tip=" + _get_bone_name_from_id(pole.tip_bone_id) + ", root=" + _get_bone_name_from_id(pole.root_bone_id))

func _eval_look_at_node(look_at: Node) -> void:
	# Convert bone names to indices if needed
	look_at.bone_id = _convert_bone_name_to_id(look_at.bone_id)
	
	if not _is_valid_bone_id(look_at.bone_id):
		push_error("IK Look-At [" + look_at.name + "] ignored. Couldn't find the bone with id [" + look_at.bone_id + "] (" + _get_bone_name_from_id(look_at.bone_id) + ")")
		return
	if not virt_skel.has_bone(virt_skel.get_bone_parent(look_at.bone_id)):
		push_error("IK Look-At [" + look_at.name + "] ignored. Specified bone [" + look_at.bone_id + "] doesn't have a parent. This Look-at cannot be solved.")
		return
	
	self._look_ats.push_back(look_at)
	virt_skel.set_bone_modifier(look_at.bone_id, VirtualSkeleton.MODIFIER.LOOK_AT)
	print("Added IK LookAt: bone=" + _get_bone_name_from_id(look_at.bone_id))

func _eval_exaggerator_node(exaggerator: Node) -> void:
	exaggerator.bone_id = _convert_bone_name_to_id(exaggerator.bone_id)
	if not _is_valid_bone_id(exaggerator.bone_id):
		push_error("IK Exaggerator [" + exaggerator.name + "] ignored. Invalid Bone Id.")
		return
	if not exaggerator.is_connected("length_changed", _on_exaggerator_change):
		exaggerator.connect("length_changed", _on_exaggerator_change)

func _eval_solidifier_node(solidifier: Node) -> void:
	solidifier.bone_id = _convert_bone_name_to_id(solidifier.bone_id)
	if not _is_valid_bone_id(solidifier.bone_id):
		push_error("IK Solidifier [" + solidifier.name + "] ignored. Specified bone does not exist.")
		return
	if not virt_skel.get_bone_children(solidifier.bone_id).size():
		push_error("IK Solidifier [" + solidifier.name + "] ignored. The bone specified is a tip.")
		return
	virt_skel.set_bone_modifier(solidifier.bone_id, VirtualSkeleton.MODIFIER.SOLID)

func _eval_damped_transform_node(damped_transform: Node) -> void:
	damped_transform.bone_id = _convert_bone_name_to_id(damped_transform.bone_id)
	if not _is_valid_bone_id(damped_transform.bone_id):
		push_error("IK Damped Transform [" + damped_transform.name + "] ignored. Specified bone does not exist.")
		return
	virt_skel.set_bone_modifier(damped_transform.bone_id, VirtualSkeleton.MODIFIER.DAMPED_TRANSFORM, damped_transform)

func _eval_bind_node(bind: Node) -> void:
	bind.bone_1 = _convert_bone_name_to_id(bind.bone_1)
	bind.bone_2 = _convert_bone_name_to_id(bind.bone_2)
	bind.bone_3 = _convert_bone_name_to_id(bind.bone_3)
	
	if not _is_valid_bone_id(bind.bone_1):
		push_error("IK Bind [" + bind.name + "] ignored. Bone 1 ID [" + bind.bone_1 + "] is invalid.")
		return
	if not _is_valid_bone_id(bind.bone_2):
		push_error("IK Bind [" + bind.name + "] ignored. Bone 2 ID [" + bind.bone_2 + "] is invalid.")
		return
	if not _is_valid_bone_id(bind.bone_3):
		push_error("IK Bind [" + bind.name + "] ignored. Bone 3 ID [" + bind.bone_3 + "] is invalid.")
		return
	
	### Calculate lengths
	bind.length_12 = (virt_skel.get_bone_position(bind.bone_1) - virt_skel.get_bone_position(bind.bone_2)).length()
	bind.length_23 = (virt_skel.get_bone_position(bind.bone_2) - virt_skel.get_bone_position(bind.bone_3)).length()
	bind.length_31 = (virt_skel.get_bone_position(bind.bone_3) - virt_skel.get_bone_position(bind.bone_1)).length()
	
	### Calculate correction bone lengths
	for b in self._binds:
		### Correction bone 2
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
		### Correction bone 3
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
	
	if virt_skel.has_bone(bind.bone_1_correction_bone):
		bind.correction_length_1 = (virt_skel.get_bone_position(bind.bone_1_correction_bone) - virt_skel.get_bone_position(bind.bone_1)).length()
	if virt_skel.has_bone(bind.bone_2_correction_bone):
		bind.correction_length_2 = (virt_skel.get_bone_position(bind.bone_2_correction_bone) - virt_skel.get_bone_position(bind.bone_2)).length()
	if virt_skel.has_bone(bind.bone_3_correction_bone):
		bind.correction_length_3 = (virt_skel.get_bone_position(bind.bone_3_correction_bone) - virt_skel.get_bone_position(bind.bone_3)).length()
	
	bind.bind_id = self._binds.size()
	self._binds.push_back(bind)
	virt_skel.set_bone_modifier(VOID_ID, VirtualSkeleton.MODIFIER.BIND, bind)

func _eval_fork_bind_node(fork_bind: Node) -> void:
	fork_bind.bone_target = _convert_bone_name_to_id(fork_bind.bone_target)
	fork_bind.bone_1 = _convert_bone_name_to_id(fork_bind.bone_1)
	fork_bind.bone_2 = _convert_bone_name_to_id(fork_bind.bone_2)
	fork_bind.bone_3 = _convert_bone_name_to_id(fork_bind.bone_3)
	
	if not _is_valid_bone_id(fork_bind.bone_target):
		push_error("IK Fork Bind [" + fork_bind.name + "] ignored. Target Bone ID [" + fork_bind.bone_target + "] is invalid.")
		return
	if not _is_valid_bone_id(fork_bind.bone_1):
		push_error("IK Fork Bind [" + fork_bind.name + "] ignored. Bone 1 ID [" + fork_bind.bone_1 + "] is invalid.")
		return
	if not _is_valid_bone_id(fork_bind.bone_2):
		push_error("IK Fork Bind [" + fork_bind.name + "] ignored. Bone 2 ID [" + fork_bind.bone_2 + "] is invalid.")
		return
	if not _is_valid_bone_id(fork_bind.bone_3):
		push_error("IK Fork Bind [" + fork_bind.name + "] ignored. Bone 3 ID [" + fork_bind.bone_3 + "] is invalid.")
		return
	
	fork_bind.length_1 = (virt_skel.get_bone_position(fork_bind.bone_1) - virt_skel.get_bone_position(fork_bind.bone_target)).length()
	fork_bind.length_2 = (virt_skel.get_bone_position(fork_bind.bone_2) - virt_skel.get_bone_position(fork_bind.bone_target)).length()
	fork_bind.length_3 = (virt_skel.get_bone_position(fork_bind.bone_3) - virt_skel.get_bone_position(fork_bind.bone_target)).length()
	
	fork_bind.bind_id = self._fork_binds.size()
	self._fork_binds.push_back(fork_bind)
	virt_skel.set_bone_modifier(VOID_ID, VirtualSkeleton.MODIFIER.FORK_BIND, fork_bind)

func _eval_cage_bind_node(cage: Node) -> void:
	cage.backbone_1 = _convert_bone_name_to_id(cage.backbone_1)
	cage.backbone_2 = _convert_bone_name_to_id(cage.backbone_2)
	cage.target_bone_1 = _convert_bone_name_to_id(cage.target_bone_1)
	cage.target_bone_2 = _convert_bone_name_to_id(cage.target_bone_2)
	
	if not _is_valid_bone_id(cage.backbone_1):
		push_error("IK Cage Bind [" + cage.name + "] ignored. Target Bone ID [" + cage.backbone_1 + "] is invalid.")
		return
	if not _is_valid_bone_id(cage.backbone_2):
		push_error("IK Cage Bind [" + cage.name + "] ignored. Bone 1 ID [" + cage.backbone_2 + "] is invalid.")
		return
	if not _is_valid_bone_id(cage.target_bone_1):
		push_error("IK Cage Bind [" + cage.name + "] ignored. Bone 2 ID [" + cage.target_bone_1 + "] is invalid.")
		return
	if not _is_valid_bone_id(cage.target_bone_2):
		push_error("IK Cage Bind [" + cage.name + "] ignored. Bone 3 ID [" + cage.target_bone_2 + "] is invalid.")
		return
	
	cage.b1b2_length = (virt_skel.get_bone_position(cage.backbone_1) - virt_skel.get_bone_position(cage.backbone_2)).length()
	cage.b1t1_length = (virt_skel.get_bone_position(cage.backbone_1) - virt_skel.get_bone_position(cage.target_bone_1)).length()
	cage.b1t2_length = (virt_skel.get_bone_position(cage.backbone_1) - virt_skel.get_bone_position(cage.target_bone_2)).length()
	cage.b2t1_length = (virt_skel.get_bone_position(cage.backbone_2) - virt_skel.get_bone_position(cage.target_bone_1)).length()
	cage.b2t2_length = (virt_skel.get_bone_position(cage.backbone_2) - virt_skel.get_bone_position(cage.target_bone_2)).length()
	cage.t1t2_length = (virt_skel.get_bone_position(cage.target_bone_1) - virt_skel.get_bone_position(cage.target_bone_2)).length()
	
	cage.b2_correction_length = (virt_skel.get_bone_position(cage.backbone_2) - virt_skel.get_bone_position(cage.backbone_2_correction)).length()
	cage.t1_correction_length = (virt_skel.get_bone_position(cage.target_bone_1) - virt_skel.get_bone_position(cage.target_bone_1_correction)).length()
	cage.t2_correction_length = (virt_skel.get_bone_position(cage.target_bone_2) - virt_skel.get_bone_position(cage.target_bone_2_correction)).length()
	
	cage.bind_id = self._cage_binds.size()
	self._cage_binds.push_back(cage)
	virt_skel.set_bone_modifier(VOID_ID, VirtualSkeleton.MODIFIER.CAGE_BIND, cage)

## RUNTIME #################################################################################################
func _physics_process(_delta: float) -> void:
	if enabled and skel != null and virt_skel != null:
		var inverse_transform = skel.get_global_transform().affine_inverse()
		solve_chains(inverse_transform)
		solve_poles(inverse_transform)
		solve_look_ats(inverse_transform)
		total_pass()
		virt_skel.bake()

func solve_chains(inverse_transform: Transform3D) -> void:
	var diff: float = 0
	## No need to solve if distance is closed
	for d in _chains:
		diff += virt_skel.get_bone_position(d.tip_bone_id).distance_squared_to(inverse_transform * d.get_target().origin)
			
	var can_solve: int = self.max_iterations
	while can_solve > 0 and diff > self.minimal_distance * self.minimal_distance * self._chains.size():
		## Solve Backwards
		for d in _chains:
			solve_backwards(d.root_bone_id,
				d.tip_bone_id,
				inverse_transform * d.get_target(),
				d.pull_strength)
		
		## Solve Forwards
		total_pass()
		
		## Measure Distance
		diff = 0
		for d in _chains:
			diff += virt_skel.get_bone_position(d.tip_bone_id).distance_squared_to(inverse_transform * d.get_target().origin)
		can_solve -= 1

func solve_poles(inverse_transform: Transform3D) -> void:
	for p in _poles:
		solve_pole(str(p.root_bone_id),
			str(p.tip_bone_id),
			inverse_transform * p.get_target().origin,
			p.turn_to)

func solve_look_ats(inverse_transform: Transform3D) -> void:
	for l in _look_ats:
		solve_look_at(l.bone_id,
					   inverse_transform * l.get_target().origin,
					   l.look_from_side,
					   0.0)

func solve_binds(bone_id: String) -> void:
	var modifier_flags = virt_skel.get_bone_modifiers(bone_id)
	
	## First - only solve Reverse forks
	if modifier_flags & virt_skel.MODIFIER.FORK_BIND:
		for i in virt_skel.get_bone_fork_bind_ids(bone_id):
			if _fork_binds[i].reverse_fork:
				solve_fork(_fork_binds[i].bone_1, _fork_binds[i].bone_2, _fork_binds[i].bone_3, _fork_binds[i].bone_target, _fork_binds[i].length_1, _fork_binds[i].length_2, _fork_binds[i].length_3, true)
	
	## Cage binds
	if modifier_flags & virt_skel.MODIFIER.CAGE_BIND:
		var c = _cage_binds[virt_skel.get_bone_cage_bind_id(bone_id)]
		solve_loop(c.target_bone_2, c.backbone_2, c.target_bone_1,
					c.target_bone_2_correction, c.backbone_2_correction, c.target_bone_1_correction,
					c.t1t2_length, c.b2t1_length, c.b1t1_length,
					c.t2_correction_length, c.b2_correction_length, c.t1_correction_length)
		
		solve_loop(c.backbone_1, c.backbone_2, c.target_bone_1,
					VOID_ID, c.backbone_2_correction, c.target_bone_1_correction,
					c.b1b2_length, c.b2t1_length, c.b1t1_length,
					0, c.b2_correction_length, c.t1_correction_length)
		
		solve_loop(c.backbone_1, c.target_bone_1, c.target_bone_2,
					VOID_ID, c.target_bone_1_correction, c.target_bone_2_correction,
					c.b1b2_length, c.b1t1_length, c.t1t2_length,
					0, c.t1_correction_length, c.t2_correction_length)
		
		solve_loop(c.backbone_1, c.target_bone_2, c.backbone_2,
					VOID_ID, c.target_bone_2_correction, c.backbone_2_correction,
					c.b1b2_length, c.t1t2_length, c.b2t1_length,
					0, c.t2_correction_length, c.b2_correction_length)
		
		solve_loop(c.target_bone_2, c.backbone_2, c.target_bone_1,
					VOID_ID, VOID_ID, VOID_ID,
					c.t1t2_length, c.b2t1_length, c.b1t1_length,
					c.t2_correction_length, c.b2_correction_length, c.t1_correction_length)
	
	## Second - solve binds
	if modifier_flags & virt_skel.MODIFIER.BIND:
		for i in virt_skel.get_bone_bind_ids(bone_id):
			solve_loop(_binds[i].bone_1, _binds[i].bone_2, _binds[i].bone_3,
				_binds[i].bone_1_correction_bone, _binds[i].bone_2_correction_bone, _binds[i].bone_3_correction_bone,
				_binds[i].length_12, _binds[i].length_23, _binds[i].length_31,
				_binds[i].correction_length_1, _binds[i].correction_length_2, _binds[i].correction_length_3)
			
	## Third - solve all forks as normal forks
	if modifier_flags & virt_skel.MODIFIER.FORK_BIND:
		for i in virt_skel.get_bone_fork_bind_ids(bone_id):
			solve_fork(_fork_binds[i].bone_1, _fork_binds[i].bone_2, _fork_binds[i].bone_3, _fork_binds[i].bone_target, _fork_binds[i].length_1, _fork_binds[i].length_2, _fork_binds[i].length_3, false)

func total_pass() -> void:
	for chain in _chains:
		solve_backwards(chain.root_bone_id,
						 chain.tip_bone_id, 
						 Transform3D(Basis(virt_skel.get_bone_rotation(chain.tip_bone_id)), virt_skel.get_bone_position(chain.tip_bone_id)),
						 chain.pull_strength)
	for root in virt_skel.roots:
		solve_forwards(root, virt_skel.bones[root].initial_position)

## RESOLVING TOOLS ########################################################################################
func solve_look_at(bone_id: String, target: Vector3, side: int, spin_override: float) -> void:
	var pivot: Vector3 = virt_skel.get_bone_position(virt_skel.get_bone_parent(bone_id))
	var start_dir: Vector3 = virt_skel.get_bone_start_direction(bone_id)
	var target_dir: Vector3 = (target - pivot)
	var rotation: Quaternion
	var spin_angle: float
	
	if side == 0: # UP
		rotation = from_to_rotation(start_dir, target_dir.normalized()) * virt_skel.get_bone_start_rotation(virt_skel.get_bone_parent(bone_id))
		spin_angle = deg_to_rad(spin_override)
	elif side == 1: # DOWN
		rotation = from_to_rotation(start_dir, -target_dir.normalized()) * virt_skel.get_bone_start_rotation(virt_skel.get_bone_parent(bone_id))
		spin_angle = deg_to_rad(spin_override)
	else:
		var rot_axis: Vector3 = start_dir.cross(target_dir).normalized()
		var a: float = virt_skel.get_bone_length(bone_id) / 2.0
		var b: float = target_dir.length()
		var rot_angle = -acos(clampf(a / b, -1.0, 1.0))
		
		rotation = from_to_rotation(start_dir, Quaternion(rot_axis, rot_angle) * target_dir) * virt_skel.get_bone_start_rotation(virt_skel.get_bone_parent(bone_id))
	
		var sp := Plane(rotation * Vector3.UP, 0.0)
		if side == 4: # FRONT
			spin_angle = signed_angle(rotation * Vector3.FORWARD, sp.project(target_dir.normalized()), sp.normal)
		elif side == 2: # LEFT
			spin_angle = signed_angle(rotation * Vector3.LEFT, sp.project(target_dir), sp.normal)
		elif side == 5: # BACK
			spin_angle = signed_angle(rotation * Vector3.BACK, sp.project(target_dir), sp.normal)
		else:
			spin_angle = signed_angle(rotation * Vector3.RIGHT, sp.project(target_dir), sp.normal)
	
	virt_skel.set_bone_rotation(virt_skel.get_bone_parent(bone_id),
		Quaternion(rotation * Vector3.UP, spin_angle) * rotation)
	
	virt_skel.set_bone_position(bone_id,
								 pivot + (rotation * virt_skel.get_bone_start_direction(bone_id).normalized()) * virt_skel.get_bone_length(bone_id))

func solve_loop(b1_id: String, b2_id: String, b3_id: String, 
				 b1_correction: String, b2_correction: String, b3_correction: String, 
				 b1_b2_length: float, b2_b3_length: float, b3_b1_length: float,
				 b1_correction_length: float, b2_correction_length: float, b3_correction_length: float) -> void:
	### PHASE 1
	## Step 1
	virt_skel.set_bone_position(b2_id, 
		calc_next(virt_skel.get_bone_position(b1_id), virt_skel.get_bone_position(b2_id), b1_b2_length))
	## Step 2
	virt_skel.set_bone_position(b3_id, 
		calc_next(virt_skel.get_bone_position(b2_id), virt_skel.get_bone_position(b3_id), b2_b3_length))
	## Step 3
	if b1_correction != VOID_ID:
		virt_skel.set_bone_position(b1_id, 
			calc_next(virt_skel.get_bone_position(b3_id), virt_skel.get_bone_position(b1_id), b3_b1_length))
		## Step 4 (same as 1)
		virt_skel.set_bone_position(b2_id, 
			calc_next(virt_skel.get_bone_position(b1_id), virt_skel.get_bone_position(b2_id), b1_b2_length))
	
	### PHASE 2
	## Step 5
	virt_skel.set_bone_position(b3_id, 
		calc_next(virt_skel.get_bone_position(b1_id), virt_skel.get_bone_position(b3_id), b3_b1_length))
	## Step 6
	virt_skel.set_bone_position(b2_id, 
		calc_next(virt_skel.get_bone_position(b3_id), virt_skel.get_bone_position(b2_id), b2_b3_length))
		
	### PHASE 3
	## b1 correction
	if b1_correction != VOID_ID:
		virt_skel.set_bone_position(b1_id, 
									 calc_next(virt_skel.get_bone_position(b1_correction), virt_skel.get_bone_position(b1_id), b1_correction_length))
	
	if b2_correction != VOID_ID:
		## Step 7 (same as 1)
		virt_skel.set_bone_position(b2_id, 
									 calc_next(virt_skel.get_bone_position(b1_id), virt_skel.get_bone_position(b2_id), b1_b2_length))
		## Step 8
		virt_skel.set_bone_position(b2_id, 
									 calc_next(virt_skel.get_bone_position(b2_correction), virt_skel.get_bone_position(b2_id), b2_correction_length))
	
	if b3_correction != VOID_ID:
		## Step 9 (same 5)
		virt_skel.set_bone_position(b3_id, 
									 calc_next(virt_skel.get_bone_position(b1_id), virt_skel.get_bone_position(b3_id), b3_b1_length))
		## Step 10
		virt_skel.set_bone_position(b3_id, 
									 calc_next(virt_skel.get_bone_position(b3_correction), virt_skel.get_bone_position(b3_id), b3_correction_length))
	
	### PHASE 4 (CUSTOM)
	## SOLVE CLOCKWISE
	virt_skel.set_bone_position(b2_id, 
								 calc_next(virt_skel.get_bone_position(b1_id), virt_skel.get_bone_position(b2_id), b1_b2_length))
	virt_skel.set_bone_position(b3_id, 
								 calc_next(virt_skel.get_bone_position(b2_id), virt_skel.get_bone_position(b3_id), b2_b3_length))
	
	## SOLVE COUNTER CLOCKWISE
	virt_skel.set_bone_position(b3_id, 
								 calc_next(virt_skel.get_bone_position(b1_id), virt_skel.get_bone_position(b3_id), b3_b1_length))
	virt_skel.set_bone_position(b2_id, 
								 calc_next(virt_skel.get_bone_position(b3_id), virt_skel.get_bone_position(b2_id), b2_b3_length))
	
	virt_skel.set_bone_position(b2_id, 
								 calc_next(virt_skel.get_bone_position(b1_id), virt_skel.get_bone_position(b2_id), b1_b2_length))

func solve_fork(bone_1_id: String, bone_2_id: String, bone_3_id: String, bone_target_id: String, length_1: float, length_2: float, length_3: float, reverse_fork: bool) -> void:
	## Correct target // bone 1's position isn't altered
	virt_skel.set_bone_position(bone_target_id, 
								 calc_next(virt_skel.get_bone_position(bone_1_id), virt_skel.get_bone_position(bone_target_id), length_1))
	
	if reverse_fork:
		virt_skel.set_bone_position(bone_2_id, 
									 calc_next(virt_skel.get_bone_position(bone_target_id), virt_skel.get_bone_position(bone_2_id), length_2))
		virt_skel.set_bone_position(bone_3_id, 
									 calc_next(virt_skel.get_bone_position(bone_target_id), virt_skel.get_bone_position(bone_3_id), length_3))
	else:
		virt_skel.set_bone_position(bone_target_id, 
									 calc_next(virt_skel.get_bone_position(bone_2_id), virt_skel.get_bone_position(bone_target_id), length_2))
		virt_skel.set_bone_position(bone_target_id, 
									 calc_next(virt_skel.get_bone_position(bone_3_id), virt_skel.get_bone_position(bone_target_id), length_3))

func solve_pole(root_id: String, tip_id: String, target: Vector3, side: int) -> void:
	if not virt_skel.has_bone(root_id) and root_id != VOID_ID:
		return
	
	var stop_bone = virt_skel.get_bone_parent(root_id)
	
	var previous_bone = tip_id
	var current_bone = virt_skel.get_bone_parent(previous_bone)
	var next_bone = virt_skel.get_bone_parent(current_bone)
	var rot_quat: Quaternion
	var start_dir: Vector3
	var target_dir: Vector3
	
	while next_bone != stop_bone and current_bone != root_id:
		var norm: Vector3 = (virt_skel.get_bone_position(previous_bone) - virt_skel.get_bone_position(next_bone)).normalized()
		var p := Plane(norm, 0)
		p.d = p.distance_to(virt_skel.get_bone_position(previous_bone))
		var projP = p.project(target)
		var projV = p.project(virt_skel.get_bone_position(current_bone))
		var angle = signed_angle(projV - virt_skel.get_bone_position(previous_bone), 
								 projP - virt_skel.get_bone_position(previous_bone),
								 norm)
		virt_skel.set_bone_position(current_bone, Quaternion(norm, angle) * (virt_skel.get_bone_position(current_bone) - virt_skel.get_bone_position(previous_bone)) + virt_skel.get_bone_position(previous_bone))
		
		## Calc bone rotation
		# Point vector Y at the next bone
		start_dir = virt_skel.get_bone_start_direction(current_bone)
		target_dir = (virt_skel.get_bone_position(next_bone) - virt_skel.get_bone_position(current_bone)).normalized()
		rot_quat = from_to_rotation(start_dir, target_dir)
		
		# Point side vector towards the target
		virt_skel.set_bone_rotation(current_bone, rotate_along_axis(rot_quat, virt_skel.get_bone_position(current_bone), target, side))
		
		previous_bone = current_bone
		current_bone = next_bone
		next_bone = virt_skel.get_bone_parent(next_bone)

func solve_forwards(root_id: String, origin: Vector3) -> void:
	if not virt_skel.has_bone(root_id) and root_id != VOID_ID:
		return
	
	var subbase_queue: PackedStringArray = virt_skel.get_bone_children(root_id)
	var modifier_flags: int
	virt_skel.set_bone_position(root_id, origin)
	var previous_bone := root_id
	var current_bone := subbase_queue[0] if subbase_queue.size() > 0 else "-1"
	if subbase_queue.size() > 0:
		subbase_queue = subbase_queue.slice(1)
	
	## UNHANDLED INSTANCE
	if virt_skel.get_bone_modifiers(previous_bone) & (VirtualSkeleton.MODIFIER.BIND | VirtualSkeleton.MODIFIER.FORK_BIND | VirtualSkeleton.MODIFIER.CAGE_BIND):
		solve_binds(previous_bone)
	
	while true:
		## if no more children are queued, exit
		if current_bone == "-1":
			return
		else:
			## CALC CURRENT'S POSITION
			modifier_flags = virt_skel.get_bone_modifiers(current_bone)
			if modifier_flags == VirtualSkeleton.MODIFIER.NONE:
				virt_skel.set_bone_position(current_bone, calc_next(virt_skel.get_bone_position(previous_bone), virt_skel.get_bone_position(current_bone), virt_skel.get_bone_length(current_bone)))
			
			elif modifier_flags & (VirtualSkeleton.MODIFIER.BIND | VirtualSkeleton.MODIFIER.FORK_BIND | VirtualSkeleton.MODIFIER.CAGE_BIND):
				virt_skel.set_bone_position(current_bone, calc_next(virt_skel.get_bone_position(previous_bone), virt_skel.get_bone_position(current_bone), virt_skel.get_bone_length(current_bone)))
				solve_binds(current_bone)
			
			if modifier_flags & VirtualSkeleton.MODIFIER.SOLID:
				virt_skel.set_bone_position(current_bone, virt_skel.get_bone_position(previous_bone) + \
														((virt_skel.get_bone_rotation(virt_skel.get_bone_parent(virt_skel.get_bone_modifier_master(current_bone))) * virt_skel.get_bone_start_direction(current_bone)) \
														* \
														virt_skel.get_bone_length(current_bone)))
			
			elif modifier_flags & VirtualSkeleton.MODIFIER.DAMPED_TRANSFORM:
				if virt_skel.get_bone_modifier_master(current_bone) != current_bone:
					var data = virt_skel.get_bone_damped_transform(current_bone)
					var target: Vector3 = virt_skel.get_bone_position(previous_bone) + \
											((virt_skel.get_bone_rotation(virt_skel.get_bone_parent(virt_skel.get_bone_modifier_master(current_bone))) * virt_skel.get_bone_start_direction(current_bone).normalized()) * \
											virt_skel.get_bone_length(current_bone))
					var force: Vector3 = (target - virt_skel.get_bone_position(current_bone)) * data[0] ## Stiffness
					force.y -= data[3] ## Gravity
					var acceleration: Vector3 = force / data[1] ## mass
					var velocity := virt_skel.add_velocity_to_bone(current_bone, acceleration * (1.0 - data[2])) ## Damping
					virt_skel.set_bone_position(current_bone, calc_next(virt_skel.get_bone_position(previous_bone), 
																		virt_skel.get_bone_position(current_bone) + velocity + force, 
																		virt_skel.get_bone_length(current_bone)))
			
			## CALC OWN ROTATION
			if previous_bone != VOID_ID and not modifier_flags & VirtualSkeleton.MODIFIER.LOOK_AT:
				var rotation := Quaternion()
				if virt_skel.get_bone_children_count(previous_bone) > 1:
					var wsum := 0.0
					var weight: float
					for c in virt_skel.get_bone_children(previous_bone):
						weight = float(virt_skel.get_bone_weight(c))
						if weight == 0:
							weight = 1
						wsum += weight
						rotation += from_to_rotation(virt_skel.get_bone_start_direction(previous_bone),
													 (virt_skel.get_bone_position(c) - virt_skel.get_bone_position(previous_bone)).normalized()) * weight
					rotation /= wsum
				else:
					rotation = from_to_rotation(virt_skel.get_bone_start_direction(current_bone),
												(virt_skel.get_bone_position(current_bone) - virt_skel.get_bone_position(previous_bone)).normalized())
				virt_skel.set_bone_rotation(previous_bone, rotation * virt_skel.get_bone_start_rotation(previous_bone))
			
			## QUEUE UP THE CURRENTS' CHILDREN
			var children = virt_skel.get_bone_children(current_bone)
			for child in children:
				subbase_queue.append(child)
			
		if subbase_queue.size() > 0:
			## Pop the first item in queue
			current_bone = subbase_queue[0]
			previous_bone = virt_skel.get_bone_parent(current_bone)
			subbase_queue = subbase_queue.slice(1)
		else:
			current_bone = "-1"
			## Remove weights so that they do not obstruct future backwards solve
			virt_skel.wipe_weights()

func solve_backwards(root_id: String, tip_id: String, target: Transform3D, weight: float) -> void:
	if not virt_skel.has_bone(tip_id):
		return
	
	if virt_skel.get_bone_children_count(tip_id) == 0:
		virt_skel.set_bone_rotation(tip_id, target.basis.get_rotation_quaternion())
	
	var current_bone := tip_id
	var current_target := target.origin
	var stop_bone = virt_skel.get_bone_parent(root_id)
	while current_bone != stop_bone and virt_skel.get_bone_parent(current_bone) != VOID_ID:
		virt_skel.set_biassed_bone_position(current_bone, current_target, weight)
		current_target = calc_next(virt_skel.get_bone_position(current_bone), virt_skel.get_bone_position(virt_skel.get_bone_parent(current_bone)), virt_skel.get_bone_length(current_bone))
		current_bone = virt_skel.get_bone_parent(current_bone)

func solve_solidifier(bone_id: String) -> void:
	var rotation := virt_skel.get_bone_rotation(virt_skel.get_bone_parent(bone_id))
	
	## Iterating through the chain stuff
	var bone_queue: PackedStringArray = []
	var current_bone = bone_id
	while true:
		if virt_skel.get_bone_children_count(current_bone) == 0 and bone_queue.is_empty():
			return
		else:
			for child in virt_skel.get_bone_children(current_bone):
				bone_queue.push_back(child)
		
		current_bone = bone_queue[0]
		bone_queue = bone_queue.slice(1)
		
		virt_skel.set_bone_rotation(current_bone, rotation * virt_skel.get_bone_start_rotation(current_bone))

## CALCULATORS ############################################################################################
static func signed_angle(from: Vector3, to: Vector3, axis: Vector3) -> float:
	var plane = Plane(axis.cross(from), 0)
	if plane.is_point_over(to):
		return from.angle_to(to)
	else:
		return -from.angle_to(to)

static func calc_next(from: Vector3, to: Vector3, length: float) -> Vector3:
	return from + ((to - from).normalized() * length)

static func from_to_rotation(from: Vector3, to: Vector3) -> Quaternion:
	var k_cos_theta: float = from.dot(to)
	var k: float = sqrt(pow(from.length(), 2.0) * pow(to.length(), 2.0))
	var axis: Vector3 = from.cross(to)
	
	if k_cos_theta == -1:
		# 180 degree rotation around any orthogonal vector
		return Quaternion(1, 0, 0, 0)
	elif k_cos_theta == 1:
		return Quaternion(0, 0, 0, 1)
	
	return Quaternion(axis.x, axis.y, axis.z, k_cos_theta + k).normalized()

static func rotate_along_axis(rotation: Quaternion, pivot: Vector3, target: Vector3, side: int) -> Quaternion:
	var p = Plane(rotation * Vector3.UP, 0.0)
	p.d = p.distance_to(pivot)
	var projP = p.project(target)
	var projV: Vector3
	
	if side == 0: ## FRONT
		projV = p.project(rotation * Vector3.FORWARD + pivot)
	elif side == 1: ## BACK
		projV = p.project(rotation * Vector3.BACK + pivot)
	elif side == 2: ## RIGHT
		projV = p.project(rotation * Vector3.RIGHT + pivot)
	else:
		projV = p.project(rotation * Vector3.LEFT + pivot)
	
	var angle = signed_angle(projV - pivot,
							  projP - pivot,
							  p.normal)
	return Quaternion(p.normal, angle) * rotation

## SIGNALS ################################################################################################
func _on_exaggerator_change(bone_id: String, length_multiplier: float) -> void:
	if virt_skel:
		virt_skel.set_bone_length_multiplier(bone_id, length_multiplier)

func add_child(node: Node, force_readable_name: bool = false, internal: int = 0) -> void:
	super.add_child(node, force_readable_name, internal)
	connect_signals(node)

func connect_signals(node: Node) -> void:
	if node.has_method("_update_parameters"):
		if not bone_names_obtained.is_connected(node._update_parameters):
			bone_names_obtained.connect(node._update_parameters)
		bone_names_obtained.emit(_bone_names_4_children)
