@tool
class_name Scatter extends Node3D


signal shape_changed
signal thread_completed
signal build_completed

#const ScatterUtil := preload('./common/scatter_util.gd')
#const ModifierStack := preload("./stack/modifier_stack.gd")
#const TransformList := preload("res://addons/proton_scatter/src/common/transform_list.gd")
#const ScatterItem := preload("./scatter_item.gd")
#const ScatterShape := preload("./scatter_shape.gd")
#const Domain := preload("./common/domain.gd")


@export_category("ProtonScatter")

@export_group("General")
@export var global_seed := 0:
	set(val):
		global_seed = val
		rebuild()
@export var show_output_in_tree := false:
	set(val):
		show_output_in_tree = val
		if output_root:
			ScatterUtil.enforce_output_root_owner(self)

@export_group("Performance")
@export var use_instancing := true:
	set(val):
		use_instancing = val
		full_rebuild(true)

@export_group("Dependency")
@export var scatter_parent: NodePath:
	set(val):
		if not is_inside_tree():
			scatter_parent = val
			return

		scatter_parent = NodePath()
		if is_instance_valid(_dependency_parent):
			_dependency_parent.build_completed.disconnect(rebuild)
			_dependency_parent = null

		var node = get_node_or_null(val)
		if not node:
			return

		var type = node.get_script()
		var scatter_type = get_script()
		if type != scatter_type:
			push_warning("ProtonScatter warning: Please select a ProtonScatter node as a parent dependency.")
			return

		# TODO: Check for cyclic dependency

		scatter_parent = val
		_dependency_parent = node
		_dependency_parent.build_completed.connect(rebuild_deferred)


@export_group("Debug", "dbg_")
@export var dbg_disable_thread := false

var undo_redo # : EditorUndoRedoManager # Can't type this
var modifier_stack: ModifierStack:
	set(val):
		if modifier_stack:
			if modifier_stack.value_changed.is_connected(rebuild):
				modifier_stack.value_changed.disconnect(rebuild)
			if modifier_stack.stack_changed.is_connected(rebuild):
				modifier_stack.stack_changed.disconnect(rebuild)

		modifier_stack = val.get_copy() # Enfore uniqueness
		modifier_stack.value_changed.connect(rebuild)
		modifier_stack.stack_changed.connect(rebuild)

var domain: Domain:
	set(val):
		domain = Domain.new() # Enforce uniqueness

var items: Array = []
var total_item_proportion: int
var output_root: Marker3D

var editor_plugin # Holds a reference to the EditorPlugin. Used by other parts.

var _thread := Thread.new()
var _rebuild_queued := false
var _dependency_parent


func _ready() -> void:
	_perform_sanity_check()
	set_notify_transform(true)
	child_exiting_tree.connect(_on_child_exiting_tree)

	if scatter_parent.is_empty():
		rebuild.call_deferred()

	# Check if the required nodes exists, if not, create them.
	_discover_items()
	domain.discover_shapes(self)

	if items.is_empty():
		var item = ScatterItem.new()
		add_child(item, true)
		item.set_name("ScatterItem")
		item.set_owner(get_tree().get_edited_scene_root())

	if domain.is_empty() and not modifier_stack.does_not_require_shapes():
		var shape = ScatterShape.new()
		add_child(shape, true)
		shape.set_owner(get_tree().get_edited_scene_root())
		shape.set_name("ScatterShape")


func _process(delta: float) -> void:
	if _thread and _thread.is_started() and not _thread.is_alive():
		thread_completed.emit()


func _get_property_list() -> Array:
	var list := []
	list.push_back({
		name = "modifier_stack",
		type = TYPE_OBJECT,
		hint_string = "ScatterModifierStack",
	})
	return list


func _get_configuration_warning() -> String:
	var warning = ""
	if items.is_empty():
		warning += "At least one ScatterItem node is required.\n"
	if domain.is_empty():
		warning += "At least one ScatterShape node in inclusive mode is required.\n"
	return warning


func _notification(what):
	match what:
		NOTIFICATION_TRANSFORM_CHANGED:
			domain.compute_bounds()
			rebuild()


func _set(property, _value):
	if not Engine.is_editor_hint():
		return false

	# Workaround to detect when the node was duplicated from the editor.
	if property == "transform":
		call_deferred("_on_node_duplicated")

	return false


# Only used for type checking.
# Useful to other scripts which can't preload this due to cyclic references.
# TODO: Old workaround from alpha 2, check if this is still needed
func is_scatter_node() -> bool:
	return true


func is_thread_running() -> bool:
	return _thread.is_alive()


# Deletes what the Scatter node generated.
func clear_output() -> void:
	if not output_root:
		output_root = get_node_or_null("ScatterOutput")

	if output_root:
		remove_child(output_root)
		output_root.queue_free()
		output_root = null

	ScatterUtil.ensure_output_root_exists(self)


func full_rebuild(delayed := false):
	if not is_inside_tree():
		return

	update_gizmos()

	if delayed:
		await get_tree().process_frame

	if is_thread_running():
		_thread.wait_to_finish()

	clear_output()
	_rebuild(true)


func rebuild_deferred(force_discover := false):
	_rebuild.bind(force_discover).call_deferred()


# A wrapper around the _rebuild function. Ensure it's not called more than once
# per frame. (Happens when the Scatter node is moved, which triggers the
# TRANSFORM_CHANGED notification in every children, which in turn notify the
# parent Scatter node back about the changes.
func rebuild(force_discover := false) -> void:
	update_gizmos()

	if not is_inside_tree():
		return

	if _thread.is_started(): # still running in the background
		_rebuild_queued = true
		return

	force_discover = true # TMP while we fix the other issues
	_rebuild(force_discover)


# Re compute the desired output.
# This is the main function, scattering the objects in the scene.
# Scattered objects are stored under a Marker3D node called "ScatterOutput"
# DON'T call this function directly outside of the 'rebuild()' function above.
func _rebuild(force_discover) -> void:
	if force_discover:
		_discover_items()
		domain.discover_shapes(self)

	if items.is_empty() or domain.is_empty():
		clear_output()
		print("Scatter warning: No items or domain, abort")
		return

	var transforms: TransformList

	if not use_instancing:
		clear_output() # TMP, prevents raycasts in modifier to self intersect with previous output

	if dbg_disable_thread:
		transforms = modifier_stack.update(self, domain)
	else:
		var update_function := modifier_stack.update.bind(self, domain.get_copy())
		var err = _thread.start(update_function, Thread.PRIORITY_NORMAL)
		await thread_completed
		transforms = _thread.wait_to_finish()

	if _rebuild_queued:
		_rebuild_queued = false
		rebuild(true)
		return

	if not transforms or transforms.size() == 0:
		clear_output()
		update_gizmos()
		return

	if use_instancing:
		_update_multimeshes(transforms)
	else:
		_update_duplicates(transforms)

	update_gizmos()

	if not _rebuild_queued:
		await get_tree().process_frame
		build_completed.emit()


func _discover_items() -> void:
	items.clear()
	total_item_proportion = 0

	for c in get_children():
		if c is ScatterItem:
			items.push_back(c)
			total_item_proportion += c.proportion

	if is_inside_tree():
		get_tree().node_configuration_warning_changed.emit(self)


# Creates one MultimeshInstance3D for each ScatterItem node.
func _update_multimeshes(transforms: TransformList) -> void:
	var offset := 0
	var transforms_count: int = transforms.size()
	var inverse_transform := global_transform.affine_inverse()

	for item in items:
		var item_root = ScatterUtil.get_or_create_item_root(item)
		var count = int(round(float(item.proportion) / total_item_proportion * transforms_count))
		var mmi = ScatterUtil.get_or_create_multimesh(item, count)
		if not mmi:
			return

		var t: Transform3D
		for i in count:
			# Extra check because of how 'count' is calculated
			if (offset + i) >= transforms_count:
				mmi.multimesh.instance_count = i - 1
				return

			t = item.process_transform(transforms.list[offset + i])
			mmi.multimesh.set_instance_transform(i, inverse_transform * t)

		offset += count


func _update_duplicates(transforms: TransformList) -> void:
	var offset := 0
	var transforms_count: int = transforms.size()
	var inverse_transform := global_transform.affine_inverse()

	for item in items:
		var count = int(round(float(item.proportion) / total_item_proportion * transforms_count))
		var root = ScatterUtil.get_or_create_item_root(item)
		var child_count = root.get_child_count()

		for i in count:
			if (offset + i) >= transforms_count:
				return

			var instance
			if i < child_count: # Grab an instance from the pool if there's one available
				instance = root.get_child(i)
			else:
				instance = _create_instance(item, root)

			if not instance:
				break

			var t: Transform3D = item.process_transform(transforms.list[offset + i])
			instance.transform = inverse_transform * t

		# Delete the unused instances left in the pool if any
		if count < child_count:
			for i in (child_count - count):
				root.get_child(-1).queue_free()

		offset += count


func _create_instance(item: ScatterItem, root: Node3D):
	if not item or not item.get_item():
		return null

	var instance = item.get_item().duplicate()
	instance.visible = true
	root.add_child.bind(instance, true).call_deferred()
	instance.set_owner.bind(get_tree().get_edited_scene_root()).call_deferred()
	var defer_ownership := func(inst,ownership):
		ScatterUtil.set_owner_recursive(instance, ownership)
	defer_ownership.bind(instance,get_tree().get_edited_scene_root()).call_deferred()



#	ScatterUtil.set_owner_recursive(instance, get_tree().get_edited_scene_root())

	return instance


# Enforce the Scatter node has its required variables set.
func _perform_sanity_check() -> void:
	if not modifier_stack:
		modifier_stack = ModifierStack.new()

	if not domain:
		domain = Domain.new()

	scatter_parent = scatter_parent


func _on_node_duplicated() -> void:
	clear_output() # Otherwise we get linked multimeshes or other unwanted side effects
	_perform_sanity_check()


func _on_child_exiting_tree(node: Node) -> void:
	if node is ScatterShape or node is ScatterItem:
		rebuild.call_deferred(true)
