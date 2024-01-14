extends GutTest

var ScatterUtil = load('res://addons/proton_scatter/src/common/scatter_util.gd')
var ProtonScatterItem = load('res://addons/proton_scatter/src/scatter_item.gd')
var LargeRock = load('res://addons/proton_scatter/demos/assets/large_rock.tscn')

func test_0001_no_leaks():
	var starting_orphans = gut.get_orphan_counter().orphan_count()

	var item = ProtonScatterItem.new()
	add_child(item)

	var result = ScatterUtil.get_merged_meshes_from(item)
	assert_null(result)

	remove_child(item)
	item.free()

	await wait_seconds(.2)
	assert_eq(gut.get_orphan_counter().orphan_count(), starting_orphans, 'no new orphans during script')

func test_0002_no_leaks():
	var starting_orphans = gut.get_orphan_counter().orphan_count()

	var item = ProtonScatterItem.new()
	item.source = 1
	item.path = 'res://addons/proton_scatter/demos/assets/large_rock.tscn'
	add_child(item)

	var result = ScatterUtil.get_merged_meshes_from(item)
	assert_not_null(result)
	result.free()

	remove_child(item)
	item.free()

	await wait_seconds(.2)
	assert_eq(gut.get_orphan_counter().orphan_count(), starting_orphans, 'no new orphans during script')

func test_0003_no_leaks():
	var starting_orphans = gut.get_orphan_counter().orphan_count()

	var item = ProtonScatterItem.new()
	item.source = 0
	item.path = 'LargeRock'
	add_child(item)

	var large_rock = LargeRock.instantiate()
	large_rock.set_name('LargeRock')
	item.add_child(large_rock)

	var result = ScatterUtil.get_merged_meshes_from(item)
	assert_not_null(result)
	result.free()

	item.remove_child(large_rock)
	large_rock.free()

	remove_child(item)
	item.free()

	await wait_seconds(.2)
	assert_eq(gut.get_orphan_counter().orphan_count(), starting_orphans, 'no new orphans during script')
