## Procedural dungeon map generator
class_name DungeonGenerator

enum RoomType { EMPTY, ENEMY, ELITE, BOSS, TREASURE, REST, SHOP, EVENT }

class Room:
	var pos: Vector2i
	var type: int
	var connections: Array[Vector2i] = []
	var visited: bool = false
	var enemies: Array[String] = []
	var cleared: bool = false

static func generate_floor(floor_num: int, seed_val: int) -> Dictionary:
	var rng = RandomNumberGenerator.new()
	rng.seed = seed_val + floor_num * 1000
	
	var rooms: Dictionary = {}
	var width = 7
	var height = 5
	
	# Generate room layout using random walk + branching
	var start = Vector2i(0, height / 2)
	var boss_pos = Vector2i(width - 1, height / 2)
	
	# Create paths from start to boss
	for path_idx in range(3):
		var pos = start
		var moved_sideways = false  # Track if we moved up/down last step
		while pos.x < width - 1:
			if not rooms.has(pos):
				var room = Room.new()
				room.pos = pos
				rooms[pos] = room
			
			# Decide direction: always advance forward after a sideways move
			var dir = Vector2i(1, 0)
			if not moved_sideways:
				var rand = rng.randf()
				if rand < 0.25 and pos.y > 0:
					dir = Vector2i(0, -1)
					moved_sideways = true
				elif rand < 0.5 and pos.y < height - 1:
					dir = Vector2i(0, 1)
					moved_sideways = true
				else:
					moved_sideways = false
			else:
				# Force forward progress after sideways step
				moved_sideways = false
			
			var next_pos = pos + dir
			next_pos.x = clampi(next_pos.x, 0, width - 1)
			next_pos.y = clampi(next_pos.y, 0, height - 1)
			
			if not rooms.has(next_pos):
				var room = Room.new()
				room.pos = next_pos
				rooms[next_pos] = room
			
			# Connect rooms
			if not rooms[pos].connections.has(next_pos):
				rooms[pos].connections.append(next_pos)
			if not rooms[next_pos].connections.has(pos):
				rooms[next_pos].connections.append(pos)
			
			pos = next_pos
	
	# Add boss room
	if not rooms.has(boss_pos):
		var room = Room.new()
		room.pos = boss_pos
		rooms[boss_pos] = room
	
	# Ensure boss is connected - find nearest room at x = width-2
	var boss_connected = false
	for conn in rooms[boss_pos].connections:
		if rooms.has(conn):
			boss_connected = true
			break
	if not boss_connected:
		# Connect boss to nearest room in column width-2
		var best_pos = Vector2i(-1, -1)
		var best_dist = 999
		for pos in rooms:
			if pos.x == width - 2:
				var dist = abs(pos.y - boss_pos.y)
				if dist < best_dist:
					best_dist = dist
					best_pos = pos
		if best_pos.x >= 0:
			rooms[best_pos].connections.append(boss_pos)
			rooms[boss_pos].connections.append(best_pos)
		else:
			# Fallback: connect to any room in column width-2 or create bridge
			for pos in rooms:
				if pos.x >= width - 3:
					rooms[pos].connections.append(boss_pos)
					rooms[boss_pos].connections.append(pos)
					break
	
	# Assign room types
	rooms[start].type = RoomType.EMPTY
	rooms[start].visited = true
	rooms[boss_pos].type = RoomType.BOSS
	
	for pos in rooms:
		if pos == start or pos == boss_pos:
			continue
		var room = rooms[pos]
		var roll = rng.randf()
		if roll < 0.4:
			room.type = RoomType.ENEMY
		elif roll < 0.55:
			room.type = RoomType.ELITE
		elif roll < 0.7:
			room.type = RoomType.TREASURE
		elif roll < 0.8:
			room.type = RoomType.REST
		elif roll < 0.9:
			room.type = RoomType.SHOP
		else:
			room.type = RoomType.EVENT
	
	# Populate enemies
	var enemy_pool = ["slime", "bat"]
	if floor_num >= 2:
		enemy_pool.append("mushroom")
	if floor_num >= 3:
		enemy_pool.append("skeleton")
		enemy_pool.append("goblin")
	if floor_num >= 4:
		enemy_pool.append("fire_elemental")
	if floor_num >= 5:
		enemy_pool.append("ghost")
		enemy_pool.append("mimic")
	if floor_num >= 7:
		enemy_pool.append("dark_knight")
		enemy_pool.append("ice_golem")
	
	for pos in rooms:
		var room = rooms[pos]
		if room.type == RoomType.ENEMY:
			var count = rng.randi_range(1, 2)
			for i in range(count):
				room.enemies.append(enemy_pool[rng.randi() % enemy_pool.size()])
		elif room.type == RoomType.ELITE:
			room.enemies.append(enemy_pool[rng.randi() % enemy_pool.size()])
			room.enemies.append(enemy_pool[rng.randi() % enemy_pool.size()])
		elif room.type == RoomType.BOSS:
			room.enemies.append("demon")
	
	return {"rooms": rooms, "start": start, "boss": boss_pos, "width": width, "height": height}
