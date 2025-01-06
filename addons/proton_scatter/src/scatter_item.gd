@tool
extends Node3D


const ScatterUtil := preload('./common/scatter_util.gd')


@export_category("ScatterItem")

## Defines the relative frequency of this item in the scatter distribution.
## For example, if item A has proportion 100 and item B has proportion 50,
## item A will appear twice as often as item B in the final scattered result.
## Higher values mean more instances of this item relative to other items.
@export var proportion := 100:
	set(val):
		proportion = val
		ScatterUtil.request_parent_to_rebuild(self)


## Controls where the item to be scattered comes from. 
## From current scene (0): Uses a node from the current scene as the source
## From disk (1): Loads the source item from a saved scene file
## This affects how the 'path' property is interpreted - either as a NodePath
## or as a filesystem path to a scene file.
@export_enum("From current scene:0", "From disk:1") var source = 1:
	set(val):
		source = val
		property_list_changed.emit()


@export_group("Source options", "source_")

## Global scale multiplier applied to the source item before scattering.
## A value of 1.0 keeps the original scale, 2.0 doubles the size, and 0.5 halves it.
## This affects all instances of this scattered item uniformly, unlike random scale
## modifiers which vary per instance.
@export var source_scale_multiplier := 1.0:
	set(val):
		source_scale_multiplier = val
		ScatterUtil.request_parent_to_rebuild(self)


## If enabled, ignores the original position of the source item when scattering.
## When true, each scattered instance uses only the position determined by the scatter
## modifiers. When false, adds the source item's original position as an offset to
## each scattered instance.
@export var source_ignore_position := true:
	set(val):
		source_ignore_position = val
		ScatterUtil.request_parent_to_rebuild(self)


## If enabled, ignores the original rotation of the source item when scattering.
## When true, each scattered instance uses only the rotation determined by the scatter
## modifiers. When false, adds the source item's original rotation to each scattered
## instance's rotation.
@export var source_ignore_rotation := true:
	set(val):
		source_ignore_rotation = val
		ScatterUtil.request_parent_to_rebuild(self)


## If enabled, ignores the original scale of the source item when scattering.
## When true, each scattered instance uses only the scale determined by the scatter
## modifiers and scale_multiplier. When false, multiplies the source item's original
## scale with the other scale modifications.
@export var source_ignore_scale := true:
	set(val):
		source_ignore_scale = val
		ScatterUtil.request_parent_to_rebuild(self)


@export_group("Override options", "override_")

## Override the source item's original material.
## When assigned, all scattered instances will use this material instead
## of the source item's materials.
@export var override_material: Material:
	set(val):
		override_material = val
		ScatterUtil.request_parent_to_rebuild(self)


## Only used when the ProtonScatter's render mode is set to "Use Particles".
## When assigned, overrides the default static particle process material.
@export var override_process_material: Material:
	set(val):
		override_process_material = val
		ScatterUtil.request_parent_to_rebuild(self) # TODO - No need for a full rebuild here


## Controls the shadow casting behavior of all scattered instances.
## Overrides the original shadow casting settings from the source item.
## Uses standard Godot shadow casting options
@export var override_cast_shadow: GeometryInstance3D.ShadowCastingSetting = GeometryInstance3D.SHADOW_CASTING_SETTING_ON:
	set(val):
		override_cast_shadow = val
		ScatterUtil.request_parent_to_rebuild(self) # TODO - Only change the multimesh flag instead

@export_group("Visibility", "visibility")

## Specifies which 3D render layers the scattered instances will be visible on.
## Uses the standard Godot layer system where each bit represents a layer.
## Useful for controlling which instances are visible to different cameras.
@export_flags_3d_render var visibility_layers: int = 1

@export var visibility_range_begin : float = 0
@export var visibility_range_begin_margin : float = 0
@export var visibility_range_end : float = 0
@export var visibility_range_end_margin : float = 0
#TODO what is a nicer way to expose this?
@export_enum("Disabled:0", "Self:1") var visibility_range_fade_mode = 0

@export_group("Level Of Detail", "lod_")

## Controls whether Level of Detail (LOD) variants are generated for scattered meshes.
## When enabled, creates simplified versions of the source mesh for better performance
## at a distance. LOD generation takes more processing time during scatter operations
## but can significantly improve runtime performance with complex meshes.
@export var lod_generate := true:
	set(val):
		lod_generate = val
		ScatterUtil.request_parent_to_rebuild(self)
		

## Determines the angle threshold at which the mesh for a single ProtonScatterItem 
## will be merged with other instances to create a lower polygon count version of the mesh.
## Setting a lower lod_merge_angle value will result in more aggressive merging, reducing 
## the overall number of mesh instances
@export_range(0.0, 180.0) var lod_merge_angle := 25.0:
	set(val):
		lod_merge_angle = val
		ScatterUtil.request_parent_to_rebuild(self)


## determines the angle threshold at which the mesh for a single ProtonScatterItem 
## will be split into a higher polygon count version of the mesh.
## generally more useful for higher polygon count models.
@export_range(0.0, 180.0) var lod_split_angle := 60.0:
	set(val):
		lod_split_angle = val
		ScatterUtil.request_parent_to_rebuild(self)

var path: String:
	set(val):
		path = val
		source_data_ready = false
		_target_scene = load(path) if source != 0 else null
		ScatterUtil.request_parent_to_rebuild(self)

var source_position: Vector3
var source_rotation: Vector3
var source_scale: Vector3
var source_data_ready := false

var _target_scene: PackedScene


func _get_property_list() -> Array:
	var list := []

	if source == 0:
		list.push_back({
			name = "path",
			type = TYPE_NODE_PATH,
		})
	else:
		list.push_back({
			name = "path",
			type = TYPE_STRING,
			hint = PROPERTY_HINT_FILE,
		})

	return list


func get_item() -> Node3D:
	if path.is_empty():
		return null

	var node: Node3D

	if source == 0 and has_node(path):
		node = get_node(path).duplicate() # Never expose the original node
	elif source == 1:
		node = _target_scene.instantiate()

	if node:
		_save_source_data(node)
		return node

	return null


# Takes a transform in input, scale it based on the local scale multiplier
# If the source transform is not ignored, also copy the source position, rotation and scale.
# Returns the processed transform
func process_transform(t: Transform3D) -> Transform3D:
	if not source_data_ready:
		_update_source_data()

	var origin = t.origin
	t.origin = Vector3.ZERO

	t = t.scaled(Vector3.ONE * source_scale_multiplier)

	if not source_ignore_scale:
		t = t.scaled(source_scale)

	if not source_ignore_rotation:
		t = t.rotated(t.basis.x.normalized(), source_rotation.x)
		t = t.rotated(t.basis.y.normalized(), source_rotation.y)
		t = t.rotated(t.basis.z.normalized(), source_rotation.z)

	t.origin = origin

	if not source_ignore_position:
		t.origin += source_position

	return t


func _save_source_data(node: Node3D) -> void:
	if not node:
		return

	source_position = node.position
	source_rotation = node.rotation
	source_scale = node.scale
	source_data_ready = true


func _update_source_data() -> void:
	var node = get_item()
	if node:
		node.queue_free()
