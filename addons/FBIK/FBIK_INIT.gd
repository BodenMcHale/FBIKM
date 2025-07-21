@tool
extends EditorPlugin

## FBIKM Plugin Initialization for Godot 4.4.1
## Registers all custom node types for the IK system

func _enter_tree() -> void:
	# Initialization of the plugin goes here.
	# Add the new type with a name, a parent type, a script and an icon.
	
	# Core IK Manager - uses Node as base for better control
	add_custom_type("KinematicsManager", "Node", preload("./scripts/IKManager.gd"), preload("icons/Manager.svg"))
	
	# IK Target nodes - using Marker3D instead of Position3D (Godot 4 best practice)
	add_custom_type("KinematicsChain", "Marker3D", preload("./scripts/IKChain.gd"), preload("icons/Chain.svg"))
	add_custom_type("KinematicsLookAt", "Marker3D", preload("./scripts/IKLookAt.gd"), preload("icons/LookAt.svg"))
	add_custom_type("KinematicsPole", "Marker3D", preload("./scripts/IKPole.gd"), preload("icons/Pole.svg"))
	
	# Bone modifier nodes
	add_custom_type("KinematicsExaggerator", "Node", preload("./scripts/IKExaggerator.gd"), preload("icons/Exaggerator.svg"))
	add_custom_type("KinematicsSpringyBones", "Node", preload("./scripts/IKDampedTransform.gd"), preload("icons/SpringyBones.svg"))
	# add_custom_type("KinematicsSolidifier", "Node", load("scripts/IKSolidifier.gd"), preload("icons/SpringyBones.svg"))
	
	# Constraint nodes
	add_custom_type("KinematicsBind", "Node", load("./scripts/IKBind.gd"), preload("icons/Bind.svg"))
	add_custom_type("KinematicsFork", "Node", preload("./scripts/IKForkBind.gd"), preload("icons/ForkBind.svg"))
	add_custom_type("KinematicsCage", "Node", preload("./scripts/IKCage.gd"), preload("icons/CageBind.svg"))
	
	# Spring helper - using Node3D instead of Position3D
	add_custom_type("Spring", "Node3D", preload("./scripts/Spring.gd"), preload("icons/Bind.svg"))

func _exit_tree() -> void:
	# Clean-up of the plugin goes here.
	# Always remember to remove it from the engine when deactivated.
	remove_custom_type("KinematicsManager")
	remove_custom_type("KinematicsChain")
	remove_custom_type("KinematicsLookAt")
	remove_custom_type("KinematicsPole")
	remove_custom_type("KinematicsExaggerator")
	remove_custom_type("KinematicsSpringyBones")
	remove_custom_type("KinematicsBind")
	remove_custom_type("KinematicsFork")
	remove_custom_type("KinematicsCage")
	remove_custom_type("Spring")
