@tool
extends Node

# Runs jobs during the physics step.
# Only supports raycast for now, but can easilly be adapted to handle
# the other types of queries.

signal job_completed


const MAX_PHYSICS_QUERIES_SETTING := "addons/proton_scatter/max_physics_queries_per_frame"


var _is_ready := false
var _job_in_progress := false
var _max_queries_per_frame := 400
var _main_thread_id: int
var _queries: Array
var _results: Array[Dictionary]
var _space_state: PhysicsDirectSpaceState3D


func _ready() -> void:
	set_physics_process(false)
	_main_thread_id = OS.get_thread_caller_id()
	_is_ready = true


func execute(queries: Array) -> Array[Dictionary]:
	if not _is_ready:
		printerr("ProtonScatter error: Calling execute on a PhysicsHelper before it's ready, this should not happen.")
		return []

	# Don't execute physics queries, if the node is not inside the tree.
	# This avoids infinite loops, because the _physics_process will never be executed.
	# This happens when the Scatter node is removed, while it perform a rebuild with a Thread.
	if not is_inside_tree():
		printerr("ProtonScatter error: Calling execute on a PhysicsHelper while the node is not inside the tree.")
		return []

	# Clear previous job if any
	_queries.clear()

	if _job_in_progress:
		await _until(get_tree().physics_frame, func(): return _job_in_progress)

	_results.clear()
	_queries = queries
	_max_queries_per_frame = ProjectSettings.get_setting(MAX_PHYSICS_QUERIES_SETTING, 500)
	_job_in_progress = true
	set_physics_process.bind(true).call_deferred()

	await _until(job_completed, func(): return _job_in_progress, true)

	return _results.duplicate()


func _physics_process(_delta: float) -> void:
	if _queries.is_empty():
		return

	if not _space_state:
		_space_state = get_tree().get_root().get_world_3d().get_direct_space_state()

	var steps = min(_max_queries_per_frame, _queries.size())
	for i in steps:
		var q = _queries.pop_back()
		var hit := _space_state.intersect_ray(q) # TODO: Add support for other operations
		_results.push_back(hit)

	if _queries.is_empty():
		set_physics_process(false)
		_results.reverse()
		_job_in_progress = false
		job_completed.emit()


func _in_main_thread() -> bool:
	return OS.get_thread_caller_id() == _main_thread_id


func _until(s: Signal, callable: Callable, physics := false) -> void:
	if _in_main_thread():
		await s
		return

	# Called from a sub thread
	var delay: int = 0
	if physics:
		delay = round(get_physics_process_delta_time() * 100.0)
	else:
		delay = round(get_process_delta_time() * 100.0)

	while callable.call():
		OS.delay_msec(delay)
