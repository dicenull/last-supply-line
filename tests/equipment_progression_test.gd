extends SceneTree
const Gear = preload("res://scripts/equipment_catalog.gd")
const Run = preload("res://scripts/run_state.gd")
var checks = 0
var failures = 0
func check(ok: bool, label: String):
	checks += 1
	if ok: print("PASS equipment progression: ",label)
	else:
		failures += 1
		push_error(label)
func _initialize():
	var seen = {}
	var previous_average = 0.0 # Current designs have no equipment-level ladder.
	for sector in range(1,6):
		var valid = true
		var level_sum = 0
		var counts = {"normal":0,"uncommon":0,"rare":0,"legendary":0}
		for source in range(6000):
			var item = Gear.roll(5197,source,source%16,false,sector*2)
			seen[item.kind] = true
			counts[item.rarity] += 1
			level_sum += Gear.level(item.kind)
			valid = valid and Gear.level(item.kind) <= sector*2 and item == Gear.roll(5197,source,source%16,false,sector*2)
			var table = Gear.DROP_TABLES[Gear.ROLE_TABLES[source%16]]
			valid = valid and (not Gear.part_slot(item.kind).is_empty() or table.any(func(row): return ("left_gun" if row[0] == "right_gun" else row[0]) == Gear.family(item.kind)))
		var average = level_sum/6000.0
		check(valid,"sector %d drops respect level cap, enemy family and seeded reload" % sector)
		check(average == 1.0 and seen.keys().all(func(id): return id in Gear.Data.ACTIVE_IDS),"only distinct current mechanisms drop at sector %d" % sector)
		check(counts.normal > 3600 and counts.uncommon > 1300 and counts.rare > 450 and counts.legendary > 35,"four rarity tiers retain their independent probabilities")
		previous_average = average
		var rewards_valid = true
		var shop_valid = true
		var shops = 0
		for seed_value in range(120):
			var r = Run.new(seed_value)
			r.enable_items()
			r.sector = sector
			r.current = r.make_route("scrapyard")
			r.offer_rewards()
			for id in r.reward_options:
				if not Gear.part_slot(id.trim_prefix("gear:")).is_empty(): continue
				var level = Gear.level(id.trim_prefix("gear:"))
				rewards_valid = rewards_valid and id.trim_prefix("gear:") in Gear.Data.ACTIVE_IDS
			var course = Run.FieldCourse.new(r.current)
			for index in range(course.destinations.size()):
				if course.destinations[index].encounter != "shop": continue
				r.current.destination_index = index
				r.advance_after_reward()
				shops += 1
				var families = {}
				for offer in r.current.shop_offers:
					var id: String = offer.trim_prefix("gear:")
					families[Gear.family(id)] = true
					shop_valid = shop_valid and Gear.level(id) <= sector*2 and Run.Services.price(offer) == 28+4*Gear.level(id)
				shop_valid = shop_valid and families.size() == 3
		check(rewards_valid,"clear rewards offer current designs without legacy minor variants")
		check(shop_valid and (shops == 0 if sector == 5 else shops > 10),"ordinary shops sell three distinct families; final base has no shop: shops=%d, offers_valid=%s" % [shops,shop_valid])
	check(seen.size() == Gear.Data.ACTIVE_IDS.size(),"all accessories and vehicle parts are obtainable through real enemy drop tables")
	var boss_valid = true
	for source in range(500): boss_valid = boss_valid and Gear.roll(42,source,0,true,10).rarity != "normal"
	check(boss_valid,"boss quality never falls below uncommon at maximum level")
	print("EQUIPMENT PROGRESSION RESULT: ",checks," checks, ",failures," failures")
	quit(1 if failures else 0)
