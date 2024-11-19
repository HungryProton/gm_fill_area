@tool
extends Node

# ProtonScatterCacheNode
#
# Saves the transforms created by ProtonScatter nodes in an external resource
# and restore them when loading the scene.
#
# Use this node when you don't want to wait for scatter nodes to fully rebuild
# at start.
# You can also enable "Show output in tree" to get the same effect, but the
# cache makes it much more VCS friendly, and doesn't clutter your scene tree.

const DEFAULT_CACHE_FOLDER := "res://addons/proton_scatter/cache/"

const ProtonScatter := preload("res://addons/proton_scatter/src/scatter.gd")
const ProtonScatterTransformList := preload("../common/transform_list.gd")


signal cache_restored


@export_file("*.res", "*.tres") var cache_file := "":
	set(val):
		cache_file = val
		update_configuration_warnings()
@export var auto_rebuild_cache_when_saving := true

@export_group("Debug", "dbg_")
@export var dbg_disable_thread := false

# The resource where transforms are actually stored
var _local_cache: ProtonScatterCacheResource
var _scene_root: Node
var _scatter_nodes: Dictionary #Key: ProtonScatter, Value: cached version
var _local_cache_changed := false


func _ready() -> void:
	if not is_inside_tree():
		return

	_scene_root = _get_local_scene_root(self)

	# Check if cache_file is empty, indicating the default case
	if cache_file.is_empty():
		if Engine.is_editor_hint():
			# Ensure the cache folder exists
			_ensure_cache_folder_exists()
		else:
			printerr("ProtonScatter error: You load a ScatterCache node with an empty cache file attribute. Outside of the editor, the addon can't set a default value. Please open the scene in the editor and set a default value.")
			return

		# Retrieve the scene name to create a unique recognizable name
		var scene_path: String = _scene_root.get_scene_file_path()
		var scene_name: String

		# If the scene path is not available, set a random name
		if scene_path.is_empty():
			scene_name = str(randi())
		else:
			# Use the base name of the scene file and append a hash to avoid collisions
			scene_name = scene_path.get_file().get_basename()
			scene_name += "_" + str(scene_path.hash())

		# Set the cache path to the cache folder, incorporating the scene name
		cache_file = DEFAULT_CACHE_FOLDER.get_basename().path_join(scene_name + "_scatter_cache.res")
		return

	restore_cache.call_deferred()


func _get_configuration_warnings() -> PackedStringArray:
	var warnings = PackedStringArray()
	if cache_file.is_empty():
		warnings.push_back("No path set for the cache file. Select where to store the cache in the inspector.")

	return warnings


func _notification(what):
	if what == NOTIFICATION_EDITOR_PRE_SAVE and auto_rebuild_cache_when_saving:
		update_cache()


func clear_cache() -> void:
	_scatter_nodes.clear()
	_local_cache = null
	for s in _scatter_nodes:
		_scatter_nodes[s] -= 1


func update_cache() -> void:
	if cache_file.is_empty():
		printerr("Cache file path is empty.")
		return

	_purge_outdated_nodes()
	_discover_scatter_nodes(_scene_root)

	if not _local_cache:
		_local_cache = ProtonScatterCacheResource.new()

	for s in _scatter_nodes:
		# Ignore this node if its cache is already up to date
		var cached_version: int = _scatter_nodes[s]
		if s.build_version == cached_version:
			continue

		# If transforms are not available, try to rebuild once.
		if not s.transforms:
			s.rebuild.call_deferred()
			await s.build_completed

		if not s.transforms:
			continue # Move on to the next if still no results.

		# Store the transforms in the cache.
		_local_cache.store(_scene_root.get_path_to(s), s.transforms.list)
		_scatter_nodes[s] = s.build_version
		_local_cache_changed = true

	# Only save the cache on disk if there's something new to save
	if not _local_cache_changed:
		return

	# TODO: Save large files on a thread
	var err = ResourceSaver.save(_local_cache, cache_file)
	_local_cache_changed = false

	if err != OK:
		printerr("ProtonScatter error: Failed to save the cache file. Code: ", err)


func restore_cache() -> void:
	# Load the cache file if it exists
	if not ResourceLoader.exists(cache_file):
		printerr("Could not find cache file ", cache_file)
		return

	if is_inside_tree():
		_load_cache_threaded(cache_file)
	else:
		_local_cache = load(cache_file)
	if not _local_cache:
		printerr("Could not load cache: ", cache_file)
		return

	_scatter_nodes.clear()
	_discover_scatter_nodes(_scene_root)

	for s in _scatter_nodes:
		if s.force_rebuild_on_load:
			continue # Ignore the cache if the scatter node is about to rebuild anyway.

		# Send the cached transforms to the scatter node.
		var transforms = ProtonScatterTransformList.new()
		transforms.list = _local_cache.get_transforms(_scene_root.get_path_to(s))
		s._perform_sanity_check()
		s._on_transforms_ready(transforms)
		s.build_version = 0
		_scatter_nodes[s] = 0

	cache_restored.emit()


func enable_for_all_nodes() -> void:
	_purge_outdated_nodes()
	_discover_scatter_nodes(_scene_root)
	for s in _scatter_nodes:
		s.force_rebuild_on_load = false


# If the node comes from an instantiated scene, returns the root of that
# instance. Returns the tree root node otherwise.
func _get_local_scene_root(node: Node) -> Node:
	if not node.scene_file_path.is_empty():
		return node

	var parent: Node = node.get_parent()
	if not parent:
		return node

	return _get_local_scene_root(parent)


func _discover_scatter_nodes(node: Node) -> void:
	if node is ProtonScatter and not _scatter_nodes.has(node):
		_scatter_nodes[node] = -1

	for c in node.get_children():
		_discover_scatter_nodes(c)


func _purge_outdated_nodes() -> void:
	var nodes_to_remove: Array[ProtonScatter] = []
	for node in _scatter_nodes:
		if not is_instance_valid(node):
			nodes_to_remove.push_back(node)
			_local_cache.erase(_scene_root.get_path_to(node))
			_local_cache_changed = true

	for node in nodes_to_remove:
		_scatter_nodes.erase(node)


func _ensure_cache_folder_exists() -> void:
	if not DirAccess.dir_exists_absolute(DEFAULT_CACHE_FOLDER):
		DirAccess.make_dir_recursive_absolute(DEFAULT_CACHE_FOLDER)


func _load_cache_threaded(cache_file_path: String) -> void:
	# Cache files are large, load on a separate thread when possible
	ResourceLoader.load_threaded_request(cache_file)
	while true:
		match ResourceLoader.load_threaded_get_status(cache_file):
			ResourceLoader.ThreadLoadStatus.THREAD_LOAD_INVALID_RESOURCE:
				return
			ResourceLoader.ThreadLoadStatus.THREAD_LOAD_IN_PROGRESS:
				await get_tree().process_frame
			ResourceLoader.ThreadLoadStatus.THREAD_LOAD_FAILED:
				return
			ResourceLoader.ThreadLoadStatus.THREAD_LOAD_LOADED:
				break

	_local_cache = ResourceLoader.load_threaded_get(cache_file)
