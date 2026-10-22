extends Node3D
## Bounded roadside silhouettes; footprints are owned by the course plan.
func build(world, course):
	name = "Landmarks"
	for plan in course.landmarks:
		var group = Node3D.new()
		add_child(group)
		group.position = plan.position
		group.rotation.y = plan.yaw
		group.scale = Vector3.ONE*plan.radius/8.0
		match plan.kind:
			"rocks":
				world.cylinder(group,Vector3(0,1.8,0),6.8,3.6,"land_detail",6,5.5)
				world.cylinder(group,Vector3(-2,4,-1),4,4,"land_detail",5,2.8)
				world.cylinder(group,Vector3(4,0.7,2),2.5,1.4,"stone",5,1.8)
				for x in [-3.0,0,3]: world.box(group,Vector3(x,3.65,3),Vector3(0.2,0.08,3),"stone")
			"deadwood":
				for offset in [Vector3(-3,0,-2),Vector3(3,0,2),Vector3(0,0,4)]:
					var top = offset+Vector3(0,7+plan.variant,0)
					world.beam(group,offset,top,0.5,"wood",6)
					world.beam(group,offset+Vector3(0,4,0),top+Vector3(2,-1,1),0.2,"wood",5)
					world.beam(group,offset+Vector3(0,3,0),top+Vector3(-2,-2,-1),0.25,"wood",5)
				world.box(group,Vector3(0,0.2,0),Vector3(8,0.4,1.2),"wood")
			"ruin":
				world.box(group,Vector3(0,0.1,0),Vector3(10,0.2,8),"land_patch")
				world.box(group,Vector3(-4,2.7,0),Vector3(0.9,5.4,8),"land_detail")
				for x in [-3.0,3.0]: world.box(group,Vector3(x,2,3.5),Vector3(3,4,0.8),"land_detail")
				world.box(group,Vector3(0,4.4,3.5),Vector3(9,0.8,0.8),"land_detail")
				var fallen = world.box(group,Vector3(1,0.7,-1),Vector3(6,0.8,2),"stone")
				fallen.rotation.y = 0.5
				world.box(group,Vector3(-3,5.8,2.5),Vector3(1.2,3,1.2),"machine_hot")
			"rail_depot":
				for z in range(-6,7,2): world.box(group,Vector3(0,0.08,z),Vector3(5.2,0.16,0.6),"wood")
				for x in [-1.7,1.7]: world.box(group,Vector3(x,0.25,0),Vector3(0.22,0.35,13),"steel")
				world.box(group,Vector3(0,1.3,-1),Vector3(4,1,7),"machine_hot")
				for z in [-4.0,2.0]:
					for x in [-2.0,2.0]: world.box(group,Vector3(x,2.4,z),Vector3(0.3,2.6,0.3),"machine_iron")
				for z in [-3.0,-1.0,1.0]: world.box(group,Vector3(0,2.1,z),Vector3(3.5,1.2,1.5),"wood")
				world.box(group,Vector3(5,3.5,3),Vector3(0.25,7,0.25),"pipe_joint")
				world.box(group,Vector3(4,6.3,3),Vector3(2.4,0.4,0.25),"brass")
			"tower":
				for x in [-2.0,2.0]:
					for z in [-2.0,2.0]: world.beam(group,Vector3(x*1.5,0,z*1.5),Vector3(x,8,z),0.3,"wood",6)
				world.box(group,Vector3(0,8,0),Vector3(5,0.6,5),"wood")
				world.box(group,Vector3(0,9.8,0),Vector3(5.4,0.35,5.4),"machine_hot")
				for x in [-2.0,2.0]: world.box(group,Vector3(x,9,0),Vector3(0.2,2,4.5),"wood")
