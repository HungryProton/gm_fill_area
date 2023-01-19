@tool
extends "base_modifier.gd"


signal projection_completed


@export var ray_direction := Vector3.DOWN
@export var ray_length := 10.0
@export var ray_offset := 1.0
@export var remove_points_on_miss := true
@export var align_with_collision_normal := false
@export_range(0.0, 90.0) var max_slope = 90.0
@export_flags_3d_physics var collision_mask = 1

var _last_hit: Dictionary


func _init() -> void:
	display_name = "Project On Colliders"
	category = "Edit"
	can_restrict_height = false
	global_reference_frame_available = true
	local_reference_frame_available = true
	individual_instances_reference_frame_available = true
	use_global_space_by_default()

	documentation.add_paragraph(
		"Moves each transforms along the ray direction until they hit a collider.
		This is useful to avoid floating objects on uneven terrain for example.")

	documentation.add_warning(
		"This modifier only works when physics bodies are around. It will ignore
		simple MeshInstances nodes.")

	var p := documentation.add_parameter("Ray direction")
	p.set_type("Vector3")
	p.set_description(
		"In which direction we look for a collider. This default to the DOWN
		direction by default (look at the ground).")
	p.add_warning(
		"This is relative to the transform is local space is enabled, or aligned
		with the global axis if local space is disabled.")

	p = documentation.add_parameter("Ray length")
	p.set_type("float")
	p.set_description("How far we look for other physics objects.")
	p.set_cost(2)

	p = documentation.add_parameter("Ray offset")
	p.set_type("Vector3")
	p.set_description(
		"Moves back the raycast origin point along the ray direction. This is
		useful if the initial transform is slightly below the ground, which would
		make the raycast miss the collider (since it would start inside).")

	p = documentation.add_parameter("Remove points on miss")
	p.set_type("bool")
	p.set_description(
		"When enabled, if the raycast didn't collide with anything, or collided
		with a surface above the max slope setting, the transform is removed
		from the list.
		This is useful to avoid floating objects that are too far from the rest
		of the scene's geometry.")

	p = documentation.add_parameter("Align with collision normal")
	p.set_type("bool")
	p.set_description(
		"Rotate the transform to align it with the collision normal in case
		the ray cast hit a collider.")

	p = documentation.add_parameter("Max slope")
	p.set_type("float")
	p.set_description(
		"Angle (in degrees) after which the hit is considered invalid.
		When a ray cast hit, the normal of the ray is compared against the
		normal of the hit. If you set the slope to 0°, the ray and the hit
		normal would have to be perfectly aligned to be valid. On the other
		hand, setting the maximum slope to 90° treats every collisions as
		valid regardless of their normals.")

	p = documentation.add_parameter("Mask")
	p.set_description(
		"Only collide with colliders on these layers. Disabled layers will
		be ignored. It's useful to ignore players or npcs that might be on the
		scene when you're editing it.")


func _process_transforms(transforms, domain:Domain, _seed) -> void:
	if transforms.is_empty():
		return
#	This modifier depends on physics, as such we need to execute this in the
#	physics process and retrieve the direct space state using the rid stored in the domain
	await domain.root.get_tree().physics_frame # Ensure we are in physics
	var space_state: PhysicsDirectSpaceState3D = PhysicsServer3D.space_get_direct_state(domain.space_state_rid)
	var hit
	var d: float
	var t: Transform3D
	var i := 0
	var remapped_max_slope = remap(max_slope, 0.0, 90.0, 0.0, 1.0)
	var is_point_valid := false

#	domain.space_state= domain.root.get_world_3d().get_direct_space_state()
	while i < transforms.size():
		t = transforms.list[i]
		is_point_valid = true

		# TODO: Weird behavior in some cases, investigate
		_project_on_floor.bind(t, domain.root, space_state).call_deferred()
		await projection_completed

		hit = _last_hit

		if hit.is_empty():
			is_point_valid = false
		else:
			d = abs(Vector3.UP.dot(hit.normal))
			is_point_valid = d >= (1.0 - remapped_max_slope)

		if is_point_valid:
			if align_with_collision_normal:
				t = _align_with(t, hit.normal)

			t.origin = hit.position
			transforms.list[i] = t

		elif remove_points_on_miss:
			transforms.list.remove_at(i)
			continue

		i += 1

	if transforms.is_empty():
		warning += """Every points have been removed. Possible reasons include: \n
		+ No collider is close enough to the domain.
		+ Ray length is too short.
		+ Ray direction is incorrect.
		+ Collision mask is not set properly.
		+ Max slope is too low.
		"""


func _project_on_floor(t: Transform3D, root: Node3D, physics_state: PhysicsDirectSpaceState3D) -> void:
	var start = t.origin
	var end = t.origin
	var dir = ray_direction.normalized()

	if is_using_individual_instances_space():
		dir = t.basis * dir

	elif is_using_local_space():
		dir = root.get_global_transform().basis * dir

	start -= ray_offset * dir
	end += ray_length * dir

	var ray_query := PhysicsRayQueryParameters3D.new()
	ray_query.from = start
	ray_query.to = end
	ray_query.collision_mask = collision_mask
	_last_hit = physics_state.intersect_ray(ray_query)
	projection_completed.emit()


func _align_with(t: Transform3D, normal: Vector3) -> Transform3D:
	var n1 = t.basis.y.normalized()
	var n2 = normal.normalized()

	var cosa = n1.dot(n2)
	var alpha = acos(cosa)
	var axis = n1.cross(n2)

	if axis == Vector3.ZERO:
		return t

	return t.rotated(axis.normalized(), alpha)
