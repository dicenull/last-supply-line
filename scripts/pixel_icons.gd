extends RefCounted
## Original 32x32 pixel sprites, drawn on an integer grid with a shared palette.
## No font glyphs, antialiasing or external assets.
const P = {
	"ink":"1c2522", "deep":"303c35", "shade":"4a5847", "olive":"778365", "light":"b2b793", "white":"e9dfb6",
	"bronze":"77532e", "gold":"c69648", "gold_hi":"f1cb78", "cream":"ffe3a5",
	"rust":"905238", "rust_hi":"cb8651", "red":"a94735", "fire":"f39d3c", "yellow":"ffe88a",
	"steel":"7f9e9f", "steel_hi":"c3dcce", "steel_dark":"466469", "inlet":"70d4cc", "wood":"80613e", "wood_hi":"b38d55"
}
const KINDS = ["scrap","steel","shell","belt","furnace","press","splitter","depot","source","gun","play","pause","erase","rotate","reset","undo","save","load","example","clock","roof","roof_open","camera","battle","shield","victory","defeat","coal","fuel","refinery","engine","coal_source","move","retreat","exit"]
var cache: Dictionary = {}
var canvas: Image

func px(x: int, y: int, c: String):
	if x >= 0 and x < 32 and y >= 0 and y < 32: canvas.set_pixel(x,y,Color(P[c]))

func rect(x: int, y: int, w: int, h: int, c: String):
	for yy in range(y,y+h):
		for xx in range(x,x+w): px(xx,yy,c)

func line(a: Vector2i, b: Vector2i, c: String, thickness: int = 1):
	var steps = maxi(absi(b.x-a.x),absi(b.y-a.y))
	for i in range(steps+1):
		var pos = Vector2(a).lerp(Vector2(b),float(i)/maxi(steps,1)).round()
		rect(int(pos.x),int(pos.y),thickness,thickness,c)

func poly(points: Array, c: String):
	var shape = PackedVector2Array()
	for point in points: shape.append(Vector2(point[0],point[1]))
	for y in range(32):
		for x in range(32):
			if Geometry2D.is_point_in_polygon(Vector2(x+0.5,y+0.5),shape): px(x,y,c)

func disk(cx: int, cy: int, radius: int, c: String):
	for y in range(cy-radius,cy+radius+1):
		for x in range(cx-radius,cx+radius+1):
			if (x-cx)*(x-cx)+(y-cy)*(y-cy) <= radius*radius: px(x,y,c)

func plate(x: int, y: int, w: int, h: int, color: String = "olive"):
	rect(x,y,w,h,"deep")
	rect(x+1,y+1,w-2,h-2,color)
	rect(x+1,y+1,w-2,1,"light")
	rect(x+1,y+2,1,h-4,"light")
	rect(x+2,y+h-2,w-3,1,"shade")

func rivet(x: int, y: int):
	px(x,y,"white")
	px(x+1,y+1,"shade")

func bullet(x: int, y: int, vertical: bool = false):
	if vertical:
		poly([[x,y+4],[x+3,y],[x+6,y+4],[x+6,y+13],[x,y+13]],"gold")
		line(Vector2i(x+1,y+4),Vector2i(x+1,y+11),"gold_hi")
		rect(x-1,y+12,8,2,"bronze")
	else:
		rect(x,y+2,12,8,"gold")
		rect(x+1,y+3,10,2,"cream")
		rect(x+1,y+8,10,2,"bronze")
		poly([[x+12,y+2],[x+18,y+6],[x+12,y+10]],"gold_hi")
		rect(x-2,y+1,3,10,"bronze")
		px(x-1,y+2,"gold_hi")

func texture(kind: String) -> ImageTexture:
	if cache.has(kind): return cache[kind]
	canvas = Image.create(32,32,false,Image.FORMAT_RGBA8)
	match kind:
		"scrap":
			poly([[4,11],[11,5],[17,9],[24,4],[28,14],[24,26],[15,24],[7,28],[3,19]],"rust")
			poly([[4,11],[11,5],[17,9],[13,14],[6,16]],"rust_hi")
			poly([[15,17],[21,11],[26,15],[22,25],[16,24]],"bronze")
			line(Vector2i(8,13),Vector2i(18,21),"deep",3)
			line(Vector2i(7,12),Vector2i(17,20),"light")
			disk(23,10,2,"ink")
			px(24,8,"gold_hi")
			for pos in [[8,22],[14,9],[19,23],[25,17]]: px(pos[0],pos[1],"rust_hi")
		"steel":
			poly([[3,12],[9,5],[28,8],[24,15]],"steel_hi")
			poly([[3,12],[24,15],[24,27],[3,23]],"steel")
			poly([[24,15],[28,8],[28,20],[24,27]],"steel_dark")
			line(Vector2i(5,14),Vector2i(21,17),"white")
			line(Vector2i(5,21),Vector2i(21,24),"steel_dark")
			rect(8,17,7,2,"steel_hi")
			px(10,8,"white")
		"shell": bullet(7,10)
		"belt":
			plate(3,7,26,20,"shade")
			for x in [5,11,17,23]:
				rect(x,11,4,12,"deep")
				rect(x,11,1,10,"steel")
			rect(4,8,24,2,"steel_hi")
			rect(4,24,24,2,"bronze")
			poly([[13,12],[20,17],[13,22],[13,19],[8,19],[8,15],[13,15]],"gold_hi")
			for x in [5,25]: rivet(x,9)
		"furnace":
			plate(7,4,6,8,"steel_dark")
			rect(6,3,8,2,"steel_hi")
			plate(4,10,24,18,"rust")
			for y in [13,18,23]: line(Vector2i(6,y),Vector2i(25,y),"bronze")
			plate(9,14,14,12,"ink")
			poly([[11,24],[11,20],[15,15],[16,21],[20,17],[22,24]],"fire")
			poly([[14,24],[16,20],[19,24]],"yellow")
			rect(3,27,26,2,"deep")
			rivet(6,12)
			rivet(25,12)
		"press":
			plate(4,26,25,4,"steel_dark")
			plate(6,4,5,23,"steel")
			plate(23,4,5,23,"steel")
			plate(4,3,25,6,"steel")
			rect(14,9,5,8,"bronze")
			rect(15,9,2,8,"gold_hi")
			plate(11,16,12,5,"steel")
			bullet(12,20)
			rivet(6,5)
			rivet(25,5)
		"splitter":
			plate(2,10,28,12,"shade")
			plate(12,13,10,16,"shade")
			line(Vector2i(5,15),Vector2i(24,15),"gold_hi",3)
			poly([[24,11],[29,16],[24,21]],"cream")
			line(Vector2i(16,17),Vector2i(16,24),"gold",3)
			poly([[12,24],[21,24],[17,29]],"gold_hi")
			rivet(4,11)
		"depot":
			plate(2,5,28,25,"wood")
			for x in [5,14,23]: bullet(x,8,true)
			rect(3,22,26,3,"wood_hi")
			rect(3,26,26,2,"bronze")
			for x in [4,27]: rivet(x,6)
		"source":
			poly([[3,7],[29,7],[25,20],[20,23],[20,29],[12,29],[12,23],[7,20]],"steel_dark")
			poly([[5,8],[27,8],[23,19],[10,19]],"olive")
			line(Vector2i(4,7),Vector2i(28,7),"steel_hi",2)
			poly([[9,10],[14,8],[18,13],[22,10],[23,16],[11,17]],"rust_hi")
			rect(14,23,4,5,"gold")
		"gun":
			plate(3,24,25,5,"shade")
			poly([[5,23],[7,12],[12,8],[23,10],[27,19],[24,24]],"olive")
			line(Vector2i(9,12),Vector2i(23,12),"light",2)
			plate(17,14,13,5,"steel_dark")
			rect(19,14,10,1,"steel_hi")
			plate(10,6,9,3,"light")
			rivet(10,21)
		"play":
			poly([[8,4],[28,16],[8,29]],"bronze")
			poly([[9,5],[26,16],[9,26]],"gold")
			line(Vector2i(10,7),Vector2i(22,15),"cream",2)
			line(Vector2i(10,25),Vector2i(24,17),"gold_hi")
		"pause":
			for x in [6,20]:
				plate(x,5,7,23,"gold")
				rect(x+1,6,2,20,"cream")
		"erase":
			plate(7,10,19,19,"steel_dark")
			for x in [11,16,21]:
				rect(x,14,2,11,"deep")
				px(x+1,14,"steel_hi")
			plate(5,6,23,4,"steel")
			plate(12,3,9,3,"steel_dark")
		"rotate", "reset", "undo":
			# Stepped ring with a chunky arrowhead and shaded lower edge.
			for y in range(4,29):
				for x in range(4,29):
					var d = Vector2(x-16,y-16).length()
					if d >= 8 and d <= 12 and not (x < 12 and y < 15): px(x,y,"gold" if y < 20 else "bronze")
			line(Vector2i(14,5),Vector2i(20,5),"cream")
			poly([[3,12],[12,3],[12,20]],"gold_hi")
			if kind == "reset": line(Vector2i(12,12),Vector2i(20,20),"white",2)
			if kind == "undo":
				rect(12,14,11,4,"light")
				poly([[9,16],[15,11],[15,21]],"white")
		"save":
			plate(4,3,25,27,"steel_dark")
			plate(8,4,15,9,"steel")
			rect(17,5,4,7,"deep")
			plate(8,17,17,12,"light")
			for y in [20,23,26]: rect(11,y,10,1,"shade")
			rivet(6,5)
		"load":
			poly([[3,9],[3,5],[13,5],[17,9],[28,9],[28,28],[3,28]],"bronze")
			plate(3,11,26,17,"gold")
			rect(5,12,22,2,"gold_hi")
			rect(14,7,5,13,"steel_hi")
			poly([[9,18],[24,18],[17,25]],"white")
		"example":
			plate(4,3,24,27,"steel_dark")
			for y in [7,13,19,25]: rect(6,y,19,1,"steel")
			for x in [9,16,23]: rect(x,5,1,22,"steel")
			line(Vector2i(10,10),Vector2i(22,10),"gold_hi",2)
			line(Vector2i(22,10),Vector2i(22,22),"gold_hi",2)
			for point in [[8,8],[20,8],[20,20]]: plate(point[0],point[1],5,5,"gold")
		"clock":
			disk(16,17,13,"bronze")
			disk(16,16,12,"gold_hi")
			disk(16,16,10,"white")
			for point in [[16,7],[25,16],[16,25],[7,16]]: rect(point[0],point[1],1,2,"deep")
			line(Vector2i(16,9),Vector2i(16,16),"deep",2)
			line(Vector2i(16,16),Vector2i(22,20),"rust",2)
			disk(16,16,2,"bronze")
		"roof", "roof_open":
			poly([[3,24],[7,16],[25,16],[29,24],[29,28],[3,28]],"olive")
			line(Vector2i(7,17),Vector2i(25,17),"light")
			var yy = 9 if kind == "roof_open" else 14
			plate(7,yy,19,5,"light")
			if kind == "roof_open":
				rect(15,3,3,5,"gold_hi")
				poly([[11,5],[20,5],[16,1]],"cream")
		"coal", "coal_source":
			poly([[3,20],[7,9],[16,4],[24,10],[29,22],[19,28],[7,27]],"ink")
			poly([[7,9],[16,4],[18,15],[10,20]],"shade")
			poly([[18,15],[24,10],[29,22],[21,21]],"deep")
			line(Vector2i(9,10),Vector2i(14,7),"steel")
		"fuel":
			plate(7,5,19,24,"steel_dark")
			rect(8,7,16,3,"steel_hi")
			rect(8,23,16,3,"gold")
			poly([[16,11],[11,19],[13,22],[19,22],[22,19]],"gold_hi")
		"refinery":
			plate(3,7,12,22,"steel_dark")
			plate(5,3,8,5,"steel")
			plate(21,13,8,16,"gold")
			line(Vector2i(11,6),Vector2i(25,12),"steel_hi",3)
			rect(6,22,6,5,"fire")
			rect(5,10,3,9,"steel_hi")
		"engine":
			plate(3,12,25,16,"steel_dark")
			for x in [6,13,20]: plate(x,7,5,9,"steel")
			plate(24,3,4,11,"deep")
			disk(10,23,5,"bronze")
			disk(10,23,3,"gold_hi")
		"move":
			disk(16,16,12,"steel_dark")
			poly([[16,4],[25,24],[16,20],[7,24]],"gold_hi")
		"exit":
			plate(5,3,18,27,"bronze")
			plate(8,6,12,22,"deep")
			rect(15,15,12,4,"gold_hi")
			poly([[24,10],[31,17],[24,24]],"cream")
		"retreat":
			plate(6,3,3,27,"steel")
			poly([[9,4],[28,4],[24,10],[28,17],[9,17]],"white")
			rect(10,5,14,2,"steel_hi")
		"battle":
			line(Vector2i(5,5),Vector2i(25,25),"steel_hi",3)
			line(Vector2i(25,5),Vector2i(5,25),"gold_hi",3)
			line(Vector2i(3,19),Vector2i(12,28),"bronze",3)
			line(Vector2i(20,28),Vector2i(28,20),"bronze",3)
		"shield":
			poly([[5,4],[27,4],[27,19],[16,29],[5,19]],"steel_dark")
			poly([[8,7],[24,7],[24,18],[16,25],[8,18]],"steel_hi")
			rect(15,8,3,15,"steel")
		"victory":
			plate(13,19,6,8,"gold")
			plate(7,27,19,3,"bronze")
			poly([[5,4],[27,4],[24,16],[16,22],[8,16]],"gold_hi")
			rect(10,6,3,10,"cream")
		"defeat":
			poly([[5,4],[27,4],[27,19],[16,29],[5,19]],"rust")
			line(Vector2i(10,8),Vector2i(23,21),"ink",3)
			line(Vector2i(22,8),Vector2i(9,21),"ink",3)
		"camera":
			plate(3,9,27,19,"olive")
			plate(7,5,11,5,"shade")
			disk(17,18,8,"deep")
			disk(17,18,6,"steel_dark")
			disk(17,18,4,"steel")
			rect(15,15,3,2,"white")
			rect(25,12,3,3,"gold_hi")
		_:
			plate(5,5,22,22)
	var result = Image.create(32,32,false,Image.FORMAT_RGBA8)
	# One-pixel silhouette outline and an offset shadow preserve readability.
	for y in range(30):
		for x in range(31):
			if canvas.get_pixel(x,y).a > 0: result.set_pixel(x+1,y+2,Color(P.ink))
	for y in range(32):
		for x in range(32):
			if canvas.get_pixel(x,y).a == 0: continue
			for offset in [Vector2i.LEFT,Vector2i.RIGHT,Vector2i.UP,Vector2i.DOWN]:
				var q = Vector2i(x,y)+offset
				if q.x >= 0 and q.x < 32 and q.y >= 0 and q.y < 32: result.set_pixel(q.x,q.y,Color(P.ink))
	for y in range(32):
		for x in range(32):
			if canvas.get_pixel(x,y).a > 0: result.set_pixel(x,y,canvas.get_pixel(x,y))
	var tex = ImageTexture.create_from_image(result)
	cache[kind] = tex
	return tex
