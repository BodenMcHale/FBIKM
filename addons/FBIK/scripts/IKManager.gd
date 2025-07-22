@tool
extends Node
const FBIKM_NODE_ID = 0  # THIS NODE'S IDENTIFIER

"""
	FBIKM - Inverse Kinematics Manager
		by Nemo Czanderlitch/Nino Čandrlić
			@R3X-G1L       (godot assets store)
			R3X-G1L6AME5H  (github)
	This is the core of the active ragdolls. This joint attempts to match its own rotation with that of
	the animation skeleton, creating the active radolls we al know and love.
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
@export var enabled: bool = false : set = _set_enabled
@export var skeleton: Skeleton3D : set = _set_skeleton

## FABRIK CONSTRAINTS
@export var max_iterations: int = 5     ## bigger  = more precise = less performant
@export var minimal_distance: float = 0.01  ## smaller = more precise = less performant

### Debug ###
var DEBUG_dump_bones: bool = false   # Turn on
var DEBUG_bone_property: String = ""   # name bone property(position, rotation, etc.); list all by default
var DEBUG_entry_count: int = -1     # Show N bones; list all by default

### Wireframe Debug ###
@export_group("Debug Wireframe")
@export var debug_wireframe: bool = false : set = _set_debug_wireframe
@export var wireframe_color: Color = Color.CYAN
@export var wireframe_bone_size: float = 0.05
@export var wireframe_line_width: float = 2.0

var debug_mesh_instance: MeshInstance3D
var debug_material: StandardMaterial3D
var debug_mesh: ArrayMesh

## GLOBAL VARIABLES ########################################################################################
var skel: Skeleton3D               # skeleton to which the changes are applied
var virt_skel: VirtualSkeleton   # an extended skeleton used to calculate the changes

## all the possible drivers that need to be ran
var _chains: Array[Node] = []
var _poles: Array[Node] = []
var _look_ats: Array[Node] = []
var _binds: Array[Node] = []
var _fork_binds: Array[Node] = []
var _cage_binds: Array[Node] = []

#### RUNTIME ENVIRONMENT ##################################################################################

func _set_skeleton(value: Skeleton3D) -> void:
	if Engine.is_editor_hint():
		# Set up in-editor environment
		if value != null and is_instance_valid(value):
			skeleton = value

			## get all bone's names for the children's dropdown menus
			_bone_names_4_children = "VOID:-1,"
			var n: int = value.get_bone_count()
			for i in range(n):
				_bone_names_4_children += value.get_bone_name(i) + ":" + str(i) + ","

			_bone_names_4_children = _bone_names_4_children.rstrip(",")
			bone_names_obtained.emit(_bone_names_4_children)

			_build_virtual_skeleton(true)
			
			for c in get_children():
				_connect_signals(c)
			bone_names_obtained.emit(_bone_names_4_children)

			_reevaluate_drivers()
		else:
			## if no skeleton clear all the memory
			skeleton = null
			_wipe_drivers()
			virt_skel = null
	else:
		## no need to set up anything if the plugin is ran in-game
		skeleton = value

func _set_debug_wireframe(value: bool) -> void:
	debug_wireframe = value
	if debug_wireframe:
		_create_debug_visualization()
	else:
		_destroy_debug_visualization()

func _set_enabled(value: bool) -> void:
	enabled = value
	if not enabled and virt_skel != null:
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

func _build_virtual_skeleton(in_editor: bool) -> Error:
	if skeleton == null:
		push_error("Skeleton in " + name + " never assigned.")
		enabled = false
		return FAILED
	virt_skel = VirtualSkeleton.new(skeleton, in_editor)
	return OK

## DEBUG WIREFRAME FUNCTIONS ##############################################################################

func _create_debug_visualization() -> void:
	if debug_mesh_instance != null:
		return
	
	# Create mesh instance for debug visualization
	debug_mesh_instance = MeshInstance3D.new()
	debug_mesh_instance.name = "DebugWireframe"
	add_child(debug_mesh_instance)
	
	# Create material
	debug_material = StandardMaterial3D.new()
	debug_material.flags_unshaded = true
	debug_material.flags_vertex_lighting = false
	debug_material.flags_transparent = true
	debug_material.albedo_color = wireframe_color
	debug_material.no_depth_test = true
	debug_material.flags_do_not_receive_shadows = true
	debug_material.flags_disable_ambient_light = true
	
	# Create mesh
	debug_mesh = ArrayMesh.new()
	debug_mesh_instance.mesh = debug_mesh
	debug_mesh_instance.material_override = debug_material

func _destroy_debug_visualization() -> void:
	if debug_mesh_instance != null:
		debug_mesh_instance.queue_free()
		debug_mesh_instance = null
	debug_material = null
	debug_mesh = null

func _update_debug_wireframe() -> void:
	if not debug_wireframe or virt_skel == null or debug_mesh_instance == null:
		return
	
	var vertices := PackedVector3Array()
	var indices := PackedInt32Array()
	var vertex_count: int = 0
	
	# Get skeleton global transform for proper positioning
	var skel_transform := Transform3D.IDENTITY
	if skeleton != null:
		skel_transform = skeleton.global_transform
	
	# Draw bones as lines connecting parent to child
	for bone_id in virt_skel.bones.keys():
		var bone_data = virt_skel.bones[bone_id]
		var bone_pos: Vector3 = skel_transform * bone_data.position
		
		# Draw bone as a small sphere
		_add_sphere_to_debug_mesh(vertices, indices, bone_pos, wireframe_bone_size, vertex_count)
		vertex_count += 6  # octahedron has 6 vertices
		
		# Draw connection to parent
		var parent_id: String = bone_data.parent
		if parent_id != VOID_ID and virt_skel.bones.has(parent_id):
			var parent_pos: Vector3 = skel_transform * virt_skel.bones[parent_id].position
			
			# Add line vertices
			vertices.append(parent_pos)
			vertices.append(bone_pos)
			
			# Add line indices
			indices.append(vertex_count)
			indices.append(vertex_count + 1)
			vertex_count += 2
	
	# Update the mesh
	debug_mesh.clear_surfaces()
	
	if vertices.size() > 0:
		var arrays := []
		arrays.resize(Mesh.ARRAY_MAX)
		arrays[Mesh.ARRAY_VERTEX] = vertices
		arrays[Mesh.ARRAY_INDEX] = indices
		
		debug_mesh.add_surface_from_arrays(Mesh.PRIMITIVE_LINES, arrays)

func _add_sphere_to_debug_mesh(vertices: PackedVector3Array, indices: PackedInt32Array, center: Vector3, radius: float, start_index: int) -> void:
	# Simple octahedron as sphere approximation for performance
	var up := center + Vector3.UP * radius
	var down := center + Vector3.DOWN * radius
	var front := center + Vector3.FORWARD * radius
	var back := center + Vector3.BACK * radius
	var left := center + Vector3.LEFT * radius
	var right := center + Vector3.RIGHT * radius
	
	# Add vertices
	vertices.append(up)      # 0
	vertices.append(down)    # 1
	vertices.append(front)   # 2
	vertices.append(back)    # 3
	vertices.append(left)    # 4
	vertices.append(right)   # 5
	
	# Add octahedron edges
	var edges := [
		[0, 2], [0, 3], [0, 4], [0, 5],  # top connections
		[1, 2], [1, 3], [1, 4], [1, 5],  # bottom connections
		[2, 4], [4, 3], [3, 5], [5, 2]   # middle ring
	]
	
	for edge in edges:
		indices.append(start_index + edge[0])
		indices.append(start_index + edge[1])

## INIT ####################################################################################################

func _ready() -> void:
	if not Engine.is_editor_hint():
		if _build_virtual_skeleton(false) == OK:
			_evaluate_drivers()
			
			if debug_wireframe:
				_create_debug_visualization()

			if DEBUG_dump_bones:
				virt_skel.cshow()

## LOAD AND ORGANIZE THE DRIVERS ###########################################################################

func _evaluate_drivers() -> void:
	if virt_skel == null:
		push_error("Tried to evaluate drivers but failed because there was no Skeleton Node assigned.")
		return

	for node in get_children():
		if node == debug_mesh_instance:
			continue  # Skip our debug visualization node
			
		if node.has_method("get") and node.get("FBIKM_NODE_ID") != null:
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

func _reevaluate_drivers() -> void:
	_wipe_drivers()
	_evaluate_drivers()

## DRIVER EVALUATION FUNCTIONS #############################################################################

func _eval_chain_node(chain: Node) -> void:
	if not virt_skel.has_bone(chain.tip_bone_id):
		push_error("IK Chain [" + chain.name + "] ignored. Couldn't find the bone with id [" + chain.tip_bone_id + "].")
		return
	_chains.push_back(chain)

func _eval_pole_node(pole: Node) -> void:
	if not virt_skel.has_bone(str(pole.tip_bone_id)):
		push_error("IK Pole [" + pole.name + "] ignored. Couldn't find the bone with id [" + str(pole.tip_bone_id) + "].")
		return
	
	if virt_skel.get_bone_parent(str(pole.tip_bone_id)) == "-1" or virt_skel.get_bone_parent(virt_skel.get_bone_parent(str(pole.tip_bone_id))) == "-1":
		push_error("IK Pole [" + pole.name + "] ignored. Chain too short.")
		return
	
	_poles.push_back(pole)

func _eval_look_at_node(look_at: Node) -> void:
	if not virt_skel.has_bone(look_at.bone_id):
		push_error("IK Look-At [" + look_at.name + "] ignored. Couldn't find the bone with id [" + str(look_at.bone_id) + "].")
		return
	if not virt_skel.has_bone(virt_skel.get_bone_parent(look_at.bone_id)):
		push_error("IK Look-At [" + look_at.name + "] ignored. Specified bone [" + str(look_at.bone_id) + "] doesn't have a parent. This Look-at cannot be solved.")
		return
	
	_look_ats.push_back(look_at)
	virt_skel.set_bone_modifier(look_at.bone_id, VirtualSkeleton.MODIFIER.LOOK_AT)

func _eval_exaggerator_node(exaggerator: Node) -> void:
	if not virt_skel.has_bone(exaggerator.bone_id):
		push_error("IK Exaggerator [" + exaggerator.name + "] ignored. Invalid Bone Id.")
		return
	if not exaggerator.is_connected("multiplier_changed", _on_exaggerator_change):
		exaggerator.connect("multiplier_changed", _on_exaggerator_change)

func _eval_solidifier_node(solidifier: Node) -> void:
	if not virt_skel.has_bone(solidifier.bone_id):
		push_error("IK Solidifier [" + solidifier.name + "] ignored. Specified bone does not exist.")
		return
	if virt_skel.get_bone_children(solidifier.bone_id).size() == 0:
		push_error("IK Solidifier [" + solidifier.name + "] ignored. The bone specified is a tip.")
		return
	virt_skel.set_bone_modifier(solidifier.bone_id, VirtualSkeleton.MODIFIER.SOLID)

func _eval_damped_transform_node(damped_transform: Node) -> void:
	if not virt_skel.has_bone(damped_transform.bone_id):
		push_error("IK Damped Transform [" + damped_transform.name + "] ignored. Specified bone does not exist.")
		return
	virt_skel.set_bone_modifier(damped_transform.bone_id, VirtualSkeleton.MODIFIER.DAMPED_TRANSFORM, damped_transform)

func _eval_bind_node(bind: Node) -> void:
	if not virt_skel.has_bone(bind.bone_1):
		push_error("IK Bind [" + bind.name + "] ignored. Bone 1 ID [" + bind.bone_1 + "] is invalid.")
		return
	if not virt_skel.has_bone(bind.bone_2):
		push_error("IK Bind [" + bind.name + "] ignored. Bone 2 ID [" + bind.bone_2 + "] is invalid.")
		return
	if not virt_skel.has_bone(bind.bone_3):
		push_error("IK Bind [" + bind.name + "] ignored. Bone 3 ID [" + bind.bone_3 + "] is invalid.")
		return
	
	# Calculate lengths
	bind.length_12 = (virt_skel.get_bone_position(bind.bone_1) - virt_skel.get_bone_position(bind.bone_2)).length()
	bind.length_23 = (virt_skel.get_bone_position(bind.bone_2) - virt_skel.get_bone_position(bind.bone_3)).length()
	bind.length_31 = (virt_skel.get_bone_position(bind.bone_3) - virt_skel.get_bone_position(bind.bone_1)).length()
	
	# Calculate correction bone lengths and cross-references
	for b in _binds:
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
	
	if virt_skel.has_bone(bind.bone_1_correction_bone):
		bind.correction_length_1 = (virt_skel.get_bone_position(bind.bone_1_correction_bone) - virt_skel.get_bone_position(bind.bone_1)).length()
	if virt_skel.has_bone(bind.bone_2_correction_bone):
		bind.correction_length_2 = (virt_skel.get_bone_position(bind.bone_2_correction_bone) - virt_skel.get_bone_position(bind.bone_2)).length()
	if virt_skel.has_bone(bind.bone_3_correction_bone):
		bind.correction_length_3 = (virt_skel.get_bone_position(bind.bone_3_correction_bone) - virt_skel.get_bone_position(bind.bone_3)).length()
	
	bind.bind_id = _binds.size()
	_binds.push_back(bind)
	virt_skel.set_bone_modifier(VOID_ID, VirtualSkeleton.MODIFIER.BIND, bind)

func _eval_fork_bind_node(fork_bind: Node) -> void:
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
	
	fork_bind.length_1 = (virt_skel.get_bone_position(fork_bind.bone_1) - virt_skel.get_bone_position(fork_bind.bone_target)).length()
	fork_bind.length_2 = (virt_skel.get_bone_position(fork_bind.bone_2) - virt_skel.get_bone_position(fork_bind.bone_target)).length()
	fork_bind.length_3 = (virt_skel.get_bone_position(fork_bind.bone_3) - virt_skel.get_bone_position(fork_bind.bone_target)).length()
	
	fork_bind.bind_id = _fork_binds.size()
	_fork_binds.push_back(fork_bind)
	virt_skel.set_bone_modifier(VOID_ID, VirtualSkeleton.MODIFIER.FORK_BIND, fork_bind)

func _eval_cage_bind_node(cage: Node) -> void:
	if not virt_skel.has_bone(cage.backbone_1):
		push_error("IK Cage Bind [" + cage.name + "] ignored. Target Bone ID [" + cage.backbone_1 + "] is invalid.")
		return
	if not virt_skel.has_bone(cage.backbone_2):
		push_error("IK Cage Bind [" + cage.name + "] ignored. Bone 1 ID [" + cage.backbone_2 + "] is invalid.")
		return
	if not virt_skel.has_bone(cage.target_bone_1):
		push_error("IK Cage Bind [" + cage.name + "] ignored. Bone 2 ID [" + cage.target_bone_1 + "] is invalid.")
		return
	if not virt_skel.has_bone(cage.target_bone_2):
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
	
	cage.bind_id = _cage_binds.size()
	_cage_binds.push_back(cage)
	virt_skel.set_bone_modifier(VOID_ID, VirtualSkeleton.MODIFIER.CAGE_BIND, cage)

## RUNTIME #################################################################################################

func _physics_process(_delta: float) -> void:
	if enabled and skeleton != null and virt_skel != null:
		var inverse_transform := skeleton.global_transform.affine_inverse()
		solve_chains(inverse_transform)
		solve_poles(inverse_transform)
		solve_look_ats(inverse_transform)
		total_pass()
		virt_skel.bake()
		
		# Update debug wireframe
		if debug_wireframe:
			_update_debug_wireframe()

## SOLVING FUNCTIONS ######################################################################################

func solve_chains(inverse_transform: Transform3D) -> void:
	var diff: float = 0.0
	for d in _chains:
		diff += virt_skel.get_bone_position(d.tip_bone_id).distance_squared_to(inverse_transform * d.get_target().origin)
	
	var can_solve: int = max_iterations
	while can_solve > 0 and diff > minimal_distance * minimal_distance * _chains.size():
		for d in _chains:
			solve_backwards(d.root_bone_id, d.tip_bone_id, inverse_transform * d.get_target(), d.pull_strength)
		
		total_pass()
		
		diff = 0.0
		for d in _chains:
			diff += virt_skel.get_bone_position(d.tip_bone_id).distance_squared_to(inverse_transform * d.get_target().origin)
		can_solve -= 1

func solve_poles(inverse_transform: Transform3D) -> void:
	for p in _poles:
		solve_pole(str(p.root_bone_id), str(p.tip_bone_id), inverse_transform * p.get_target().origin, p.turn_to)

func solve_look_ats(inverse_transform: Transform3D) -> void:
	for l in _look_ats:
		var spin_override: float = 0.0
		if l.has_method("get"):
			spin_override = l.get("up-down_spin_override_angle") if l.get("up-down_spin_override_angle") != null else 0.0
		solve_look_at(l.bone_id, inverse_transform * l.get_target().origin, l.look_from_side, spin_override)

func total_pass() -> void:
	for chain in _chains:
		solve_backwards(chain.root_bone_id, chain.tip_bone_id, 
			Transform3D(Basis(virt_skel.get_bone_rotation(chain.tip_bone_id)), virt_skel.get_bone_position(chain.tip_bone_id)),
			chain.pull_strength)
	for root in virt_skel.roots:
		solve_forwards(root, virt_skel.bones[root].initial_position)

# Placeholder solving functions - implement based on your original VirtualSkeleton system
func solve_backwards(root_id: String, tip_id: String, target: Transform3D, weight: float) -> void:
	# Implementation would match your existing solve_backwards logic
	pass

func solve_forwards(root_id: String, origin: Vector3) -> void:
	# Implementation would match your existing solve_forwards logic
	pass

func solve_pole(root_id: String, tip_id: String, target: Vector3, side: int) -> void:
	# Implementation would match your existing solve_pole logic
	pass

func solve_look_at(bone_id: String, target: Vector3, side: int, spin_override: float) -> void:
	# Implementation would match your existing solve_look_at logic
	pass

## SIGNALS ################################################################################################

func _on_exaggerator_change(bone_id: String, length_multiplier: float) -> void:
	if virt_skel:
		virt_skel.set_bone_length_multiplier(bone_id, length_multiplier)

func add_child(node: Node, force_readable_name: bool = false, internal: InternalMode = INTERNAL_MODE_DISABLED) -> void:
	super.add_child(node, force_readable_name, internal)
	_connect_signals(node)

func _connect_signals(node: Node) -> void:
	if node.has_method("_update_parameters"):
		if not bone_names_obtained.is_connected(node._update_parameters):
			bone_names_obtained.connect(node._update_parameters)
		bone_names_obtained.emit(_bone_names_4_children)
