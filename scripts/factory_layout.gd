extends RefCounted
## Fixed hull fittings for new expeditions; version 1 remains save-compatible.
const VERSION = 2
const AMMO_ANCHOR = Vector2i(9,3)
const AMMO_CELLS = [Vector2i(9,3),Vector2i(10,3),Vector2i(9,4),Vector2i(10,4)]
const FUEL_PORT = Vector2i(0,4)
const PORTS = {
	Vector2i(6,3):"source", Vector2i(7,4):"source", Vector2i(6,4):"coal_source",
	Vector2i(9,3):"gun", Vector2i(10,3):"gun", Vector2i(9,4):"gun", Vector2i(10,4):"gun", FUEL_PORT:"engine"
}
const DIRECTIONS = {Vector2i(6,3):3,Vector2i(7,4):1,Vector2i(6,4):2}
# Three openings: north for ammunition, south for the optional second line,
# and west for fuel. The right-hand wall separates raw stock from the magazine.
const WALLS = [Vector2i(5,2),Vector2i(7,2),Vector2i(8,2),Vector2i(5,3),Vector2i(8,3),Vector2i(8,4),Vector2i(5,5),Vector2i(6,5),Vector2i(8,5)]

static func rows(id: String = "standard") -> Array:
	var result = [
		[6,2,"belt",3],[6,1,"furnace",0],[7,1,"press",0],[8,1,"belt",0],[9,1,"belt",1],[9,2,"belt",1],
		[5,4,"belt",2],[4,4,"refinery",2],[3,4,"belt",2],[2,4,"belt",2],[1,4,"belt",2]
	]
	if id == "parallel":
		result.append_array([[7,5,"belt",1],[7,6,"furnace",0],[8,6,"press",0],[9,6,"belt",3],[9,5,"belt",3]])
	elif id == "buffered":
		result[3][2] = "depot"
		result[4][2] = "depot"
	return result
