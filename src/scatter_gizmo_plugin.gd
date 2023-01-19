@tool
class_name ScatterGizmoPlugin extends EditorNode3DGizmoPlugin


#

const Scatter := preload("./scatter.gd")

var _panel
var _loading_mesh: Mesh


func _init():
	# TODO: Replace hardcoded colors by a setting fetch
	create_custom_material("line", Color(0.2, 0.4, 0.8))
	add_material("loading", preload("../icons/loading/m_loading.tres"))

	_loading_mesh = QuadMesh.new()
	_loading_mesh.set_size(Vector2.ONE * 0.15)


func _get_gizmo_name() -> String:
	return "ProtonScatter"


func _has_gizmo(node) -> bool:
	return node is Scatter


func _redraw(gizmo: EditorNode3DGizmo):
	gizmo.clear()
	var node = gizmo.get_node_3d()

	if not node.modifier_stack:
		return

	if node.is_thread_running():
		gizmo.add_mesh(_loading_mesh, get_material("loading"))

	if node.modifier_stack.is_using_edge_data():
		var curves: Array[Curve3D] = node.domain.get_edges()
		var inverse_transform := node.get_global_transform().affine_inverse()

		for curve in curves:
			var lines := PackedVector3Array()
			var points: PackedVector3Array = curve.tessellate(4, 8)
			var lines_count := points.size() - 1

			for i in lines_count:
				lines.append(inverse_transform * points[i])
				lines.append(inverse_transform * points[i + 1])

			gizmo.add_lines(lines, get_material("line"))


func set_path_gizmo_panel(panel: Control) -> void:
	_panel = panel


func set_editor_plugin(plugin: EditorPlugin) -> void:
	pass


# Creates a standard material displayed on top of everything.
# Only exists because 'create_material() on_top' parameter doesn't seem to work.
func create_custom_material(name, color := Color.WHITE):
	var material := StandardMaterial3D.new()
	material.set_blend_mode(StandardMaterial3D.BLEND_MODE_ADD)
	material.set_shading_mode(StandardMaterial3D.SHADING_MODE_UNSHADED)
	material.set_flag(StandardMaterial3D.FLAG_DISABLE_DEPTH_TEST, true)
	material.set_albedo(color)
	material.render_priority = 100

	add_material(name, material)
