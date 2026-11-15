extends RefCounted


static func setup(characters: Array) -> void:
	for c in characters:
		c.motion_mode = CharacterBody2D.MOTION_MODE_FLOATING
		c.platform_floor_layers = 0
		c.platform_wall_layers = 0
		for o in characters:
			if o != c:
				c.add_collision_exception_with(o)


static func resolve(body: CharacterBody2D, vel: Vector2, delta: float) -> Vector2:
	if vel == Vector2.ZERO or delta <= 0.0:
		return vel
	var me := _footprint(body)
	if me.is_empty():
		return vel
	for other in body.get_parent().get_children():
		if other == body or not other is CharacterBody2D or not other.is_visible_in_tree():
			continue
		var o := _footprint(other)
		if o.is_empty():
			continue
		var pts := Geometry2D.get_closest_points_between_segments(me["a"], me["b"], o["a"], o["b"])
		var d: Vector2 = pts[0] - pts[1]
		var dist := d.length()
		var reach: float = me["r"] + o["r"]
		if dist > reach + vel.length() * delta:
			continue
		var n: Vector2 = d / dist if dist > 0.001 else (me["c"] - o["c"]).normalized()
		if n == Vector2.ZERO:
			n = Vector2.DOWN
		var inward := -vel.dot(n)
		var allow := maxf(dist - reach, 0.0) / delta
		if inward > allow:
			vel += n * (inward - allow)
	return vel


static func _footprint(body: Node) -> Dictionary:
	var cs := body.get_node_or_null("CollisionShape2D") as CollisionShape2D
	if cs == null or cs.disabled or cs.shape == null:
		return {}
	var scale := absf(cs.global_scale.x)
	var r := 10.0
	var half := 0.0
	if cs.shape is CapsuleShape2D:
		var cap := cs.shape as CapsuleShape2D
		r = cap.radius
		half = maxf(cap.height * 0.5 - cap.radius, 0.0)
	elif cs.shape is CircleShape2D:
		r = (cs.shape as CircleShape2D).radius
	elif cs.shape is RectangleShape2D:
		var s := (cs.shape as RectangleShape2D).size
		r = minf(s.x, s.y) * 0.5
		half = absf(s.y - s.x) * 0.5
	var c := cs.global_position
	var axis := Vector2.DOWN.rotated(cs.global_rotation)
	if cs.shape is RectangleShape2D and (cs.shape as RectangleShape2D).size.x > (cs.shape as RectangleShape2D).size.y:
		axis = Vector2.RIGHT.rotated(cs.global_rotation)
	return {"c": c, "a": c - axis * half * scale, "b": c + axis * half * scale, "r": r * scale}
