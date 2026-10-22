extends RefCounted
## Optional starting layouts, all constructible with the same initial equipment.
const Factory = preload("res://scripts/factory.gd")
const IDS = ["standard","parallel","buffered"]
const REQUIREMENTS = {"standard":0,"parallel":1,"buffered":3}

static func layout(id: String) -> Array:
	if id not in IDS: return []
	var factory = Factory.new()
	factory.example(false)
	if id == "parallel":
		for x in [1,3,5,6,7]: factory.cells[Vector2i(x,5)] = factory.make_cell("belt",0)
		factory.cells[Vector2i(2,5)] = factory.make_cell("furnace",0)
		factory.cells[Vector2i(4,5)] = factory.make_cell("press",0)
		factory.cells[Vector2i(8,5)] = factory.make_cell("belt",3)
		factory.cells[Vector2i(8,4)] = factory.make_cell("belt",0)
	elif id == "buffered":
		factory.cells[Vector2i(7,2)] = factory.make_cell("depot",0)
		factory.cells[Vector2i(8,2)] = factory.make_cell("depot",0)
	return factory.layout()

static func matches(rows: Array, id: String) -> bool:
	var target = layout(id)
	if rows.size() != target.size(): return false
	for row in target:
		if not rows.has(row): return false
	return true
