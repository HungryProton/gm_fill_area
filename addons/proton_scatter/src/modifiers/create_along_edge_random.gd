@tool
extends "base_modifier.gd"


const MAX_TRIES := 100

@export var instance_count := 10
@export var align_to_path := false
@export var align_up_axis := Vector3.UP

var _rng: RandomNumberGenerator


func _init() -> void:
	display_name = "Create Along Edge (Random)"
	category = "Create"
	warning_ignore_no_transforms = true
	warning_ignore_no_shape = false
	use_edge_data = true
	global_reference_frame_available = true
	local_reference_frame_available = true
	individual_instances_reference_frame_available = false


func _process_transforms(transforms, domain, random_seed) -> void:
	_rng = RandomNumberGenerator.new()
	_rng.set_seed(random_seed)

	var gt_inverse: Transform3D = domain.get_global_transform().affine_inverse()
	var new_transforms: Array[Transform3D] = []
	var curves: Array[Curve3D] = domain.get_edges()
	var total_curve_length := 0.0

	for curve in curves:
		var length: float = curve.get_baked_length()
		total_curve_length += length

	for curve in curves:
		var length: float = curve.get_baked_length()
		var local_instance_count: int = round((length / total_curve_length) * instance_count)

		for i in local_instance_count:
			var data = get_pos_and_normal(domain, curve, _rng.randf() * length)
			if data.is_empty():
				break
			var pos: Vector3 = data[0]
			var normal: Vector3 = data[1]
			var t := Transform3D()

			t.origin = pos
			if align_to_path:
				t = t.looking_at(normal + pos, align_up_axis)
			elif is_using_global_space():
				t.basis = gt_inverse.basis

			new_transforms.push_back(t)

	transforms.append(new_transforms)


func get_pos_and_normal(domain, curve: Curve3D, offset : float) -> Array:
	var i := 0
	while i < MAX_TRIES:
		i += 1
		var pos: Vector3 = curve.sample_baked(offset)
		if domain.is_point_excluded(pos):
			continue
		var normal := Vector3.ZERO

		var pos1
		if offset + curve.get_bake_interval() < curve.get_baked_length():
			pos1 = curve.sample_baked(offset + curve.get_bake_interval())
			normal = (pos1 - pos)
		else:
			pos1 = curve.sample_baked(offset - curve.get_bake_interval())
			normal = (pos - pos1)

		return [pos, normal]
	return []
