@tool
extends RefCounted

# A domain is the complete area where transforms can (and can't) be placed.
# A Scatter node has one single domain, a domain has one or more shape nodes.
#
# It's the combination of every shape defined under a Scatter node, grouped in
# a single class that exposes utility functions (check if a point is inside, or
# along the surface etc).
#
# An instance of this class is passed to the modifiers during a rebuild.


const ProtonScatter := preload("../scatter.gd")
const ProtonScatterShape := preload("../scatter_shape.gd")
const BaseShape := preload("../shapes/base_shape.gd")
const Bounds := preload("../common/bounds.gd")


class DomainShapeInfo:
	var node: Node3D
	var shape: BaseShape

	func is_point_inside(point: Vector3, local: bool) -> bool:
		var t: Transform3D
		if is_instance_valid(node):
			t = node.get_transform() if local else node.get_global_transform()
			return shape.is_point_inside(point, t)
		else:
			return false	
	
	func get_corners_global() -> Array:
		return shape.get_corners_global(node.get_global_transform())

# A polygon made of one outer boundary and one or multiple holes (inner polygons)
class ComplexPolygon:
	var inner: Array[PackedVector2Array] = []
	var outer: PackedVector2Array

	func add(polygon: PackedVector2Array) -> void:
		if polygon.is_empty(): return
		if Geometry2D.is_polygon_clockwise(polygon):
			inner.push_back(polygon)
		else:
			if not outer.is_empty():
				print_debug("ProtonScatter error: Replacing polygon's existing outer boundary. This should not happen, please report.")
			outer = polygon

	func add_array(array: Array, reverse := false) -> void:
		for p in array:
			if reverse:
				p.reverse()
			add(p)

	func get_all() -> Array[PackedVector2Array]:
		var res = inner.duplicate()
		res.push_back(outer)
		return res

	func _to_string() -> String:
		var res =  "o: " + var_to_str(outer.size()) + ", i: ["
		for i in inner:
			res += var_to_str(i.size()) + ", "
		res += "]"
		return res


var root: ProtonScatter
var positive_shapes: Array[DomainShapeInfo]
var negative_shapes: Array[DomainShapeInfo]
var bounds_global: Bounds = Bounds.new()
var bounds_local: Bounds = Bounds.new()
var edges: Array[Curve3D] = []


func is_empty() -> bool:
	return positive_shapes.is_empty()


# If a point is in an exclusion shape, returns false
# If a point is in an inclusion shape (but not in an exclusion one), returns true
# If a point is in neither, returns false
func is_point_inside(point: Vector3, local := true) -> bool:
	for s in negative_shapes:
		if s.is_point_inside(point, local):
			return false

	for s in positive_shapes:
		if s.is_point_inside(point, local):
			return true

	return false


# If a point is inside an exclusion shape, returns true
# Returns false in every other case
func is_point_excluded(point: Vector3, local := true) -> bool:
	for s in negative_shapes:
		if s.is_point_inside(point, local):
			return true

	return false


# Recursively find all ScatterShape nodes under the provided root. In case of
# nested Scatter nodes, shapes under these other Scatter nodes will be ignored
func discover_shapes(root_node: Node3D) -> void:
	root = root_node
	positive_shapes.clear()
	negative_shapes.clear()

	if not is_instance_valid(root):
		return

	for c in root.get_children():
		_discover_shapes_recursive(c)
	compute_bounds()
	compute_edges()


func compute_bounds() -> void:
	bounds_global.clear()
	bounds_local.clear()

	if not is_instance_valid(root):
		return

	var gt: Transform3D = root.get_global_transform().affine_inverse()

	for info in positive_shapes:
		for point in info.get_corners_global():
			bounds_global.feed(point)
			bounds_local.feed(gt * point)

	bounds_global.compute_bounds()
	bounds_local.compute_bounds()


func compute_edges() -> void:
	edges.clear()

	if not is_instance_valid(root):
		return

	var source_polygons: Array[ComplexPolygon] = []

	## Retrieve all polygons
	for info in positive_shapes:
		# Store all closed polygons in a specific array
		var polygon := ComplexPolygon.new()
		polygon.add_array(info.shape.get_closed_edges(info.node.transform))

		# Polygons with holes must be merged together first
		if not polygon.inner.is_empty():
			source_polygons.push_back(polygon)
		else:
			source_polygons.push_front(polygon)

		# Store open edges directly since they are already Curve3D and we
		# don't apply boolean operations to them.
		var open_edges = info.shape.get_open_edges(info.node.transform)
		edges.append_array(open_edges)

	if source_polygons.is_empty():
		return

	## Merge all closed polygons together
	var merged_polygons: Array[ComplexPolygon] = []

	while not source_polygons.is_empty():
		var merged := false
		var p1: ComplexPolygon = source_polygons.pop_back()
		var max_steps: int = source_polygons.size()
		var i = 0

		# Test p1 against every other polygon from source_polygon until a
		# successful merge. If no merge happened, put it in the final array.
		while i < max_steps and not merged:
			i += 1

			# Get the next polygon in the list
			var p2: ComplexPolygon = source_polygons.pop_back()

			# If the outer boundary of any of the two polygons is completely
			# enclosed in one of the other polygon's hole, we don't try to
			# merge them and go the next iteration.
			var full_overlap = false
			for ip1 in p1.inner:
				var res = Geometry2D.clip_polygons(p2.outer, ip1)
				if res.is_empty():
					full_overlap = true
					break

			for ip2 in p2.inner:
				var res = Geometry2D.clip_polygons(p1.outer, ip2)
				if res.is_empty():
					full_overlap = true
					break

			if full_overlap:
				source_polygons.push_front(p2)
				continue

			# Try to merge the two polygons p1 and p2
			var res = Geometry2D.merge_polygons(p1.outer, p2.outer)
			var outer_polygons := 0
			for p in res:
				if not Geometry2D.is_polygon_clockwise(p):
					outer_polygons += 1

			# If the merge generated a new polygon, process the holes data from
			# the two original polygons and store in the new_polygon
			# P1 and P2 are then discarded and replaced by the new polygon.
			if outer_polygons == 1:
				var new_polygon = ComplexPolygon.new()
				new_polygon.add_array(res)

				# Process the holes data from p1 and p2
				for ip1 in p1.inner:
					for ip2 in p2.inner:
						new_polygon.add_array(Geometry2D.intersect_polygons(ip1, ip2), true)
						new_polygon.add_array(Geometry2D.clip_polygons(ip2, p1.outer), true)

					new_polygon.add_array(Geometry2D.clip_polygons(ip1, p2.outer), true)

				source_polygons.push_back(new_polygon)
				merged = true

			# If the polygons don't overlap, return it to the pool to be tested
			# against other polygons
			else:
				source_polygons.push_front(p2)

		# If p1 is not overlapping any other polygon, add it to the final list
		if not merged:
			merged_polygons.push_back(p1)

	## For each polygons from the previous step, create a corresponding Curve3D
	for cp in merged_polygons:
		for polygon in cp.get_all():
			if polygon.size() < 2: # Ignore polygons too small to form a loop
				continue

			var curve := Curve3D.new()
			for point in polygon:
				curve.add_point(Vector3(point.x, 0.0, point.y))

			# Close the look if the last vertex is missing (Randomly happens)
			var first_point := polygon[0]
			var last_point := polygon[-1]
			if first_point != last_point:
				curve.add_point(Vector3(first_point.x, 0.0, first_point.y))

			edges.push_back(curve)


func get_root() -> ProtonScatter:
	return root


func get_global_transform() -> Transform3D:
	return root.get_global_transform()


func get_local_transform() -> Transform3D:
	return root.get_transform()


func get_edges() -> Array[Curve3D]:
	if edges.is_empty():
		compute_edges()
	return edges


func get_copy():
	var copy = get_script().new()

	copy.root = root
	copy.bounds_global = bounds_global
	copy.bounds_local = bounds_local

	for s in positive_shapes:
		var s_copy = DomainShapeInfo.new()
		s_copy.node = s.node
		s_copy.shape = s.shape.get_copy()
		copy.positive_shapes.push_back(s_copy)

	for s in negative_shapes:
		var s_copy = DomainShapeInfo.new()
		s_copy.node = s.node
		s_copy.shape = s.shape.get_copy()
		copy.negative_shapes.push_back(s_copy)

	return copy


func _discover_shapes_recursive(node: Node) -> void:
	if node is ProtonScatter: # Ignore shapes under nested Scatter nodes
		return

	if node is ProtonScatterShape and node.shape != null:
		var info := DomainShapeInfo.new()
		info.node = node
		info.shape = node.shape

		if node.negative:
			negative_shapes.push_back(info)
		else:
			positive_shapes.push_back(info)

	for c in node.get_children():
		_discover_shapes_recursive(c)
