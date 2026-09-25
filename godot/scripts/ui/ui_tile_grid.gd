class_name UITileGrid
extends Control
## Fixed-cell tile layout (FH4 menu pages): tiles span whole cells, e.g. a 2x2 hero tile beside
## 2x1 and 1x1 tiles. Pad navigation is set explicitly by geometry (nearest tile in each
## direction) so it stays predictable with mixed spans.

var cell := Vector2(196, 128)
var gap := 12.0
var tiles: Array[UITile] = []

func _init(p_cell := Vector2(196, 128), p_gap := 12.0) -> void:
	cell = p_cell
	gap = p_gap
	mouse_filter = Control.MOUSE_FILTER_IGNORE

func add_tile(t: UITile, col: int, row: int, cols := 1, rows := 1) -> UITile:
	t.position = Vector2(col * (cell.x + gap), row * (cell.y + gap))
	t.size = Vector2(cols * cell.x + (cols - 1) * gap, rows * cell.y + (rows - 1) * gap)
	t.pivot_offset = t.size * 0.5
	add_child(t)
	tiles.append(t)
	var extent := t.position + t.size
	custom_minimum_size = Vector2(maxf(custom_minimum_size.x, extent.x), maxf(custom_minimum_size.y, extent.y))
	size = custom_minimum_size
	return t

func clear() -> void:
	for t in tiles:
		t.queue_free()
	tiles.clear()
	custom_minimum_size = Vector2.ZERO

## Wire focus neighbours: for each direction pick the tile whose centre lies that way with the
## smallest distance, weighting sideways offset double so rows/columns are preferred.
func link_focus() -> void:
	for t in tiles:
		var c := t.position + t.size * 0.5
		for d in [[Vector2.LEFT, "focus_neighbor_left"], [Vector2.RIGHT, "focus_neighbor_right"], [Vector2.UP, "focus_neighbor_top"], [Vector2.DOWN, "focus_neighbor_bottom"]]:
			var dir: Vector2 = d[0]
			var best: UITile = null
			var best_score := INF
			for o in tiles:
				if o == t:
					continue
				var oc := o.position + o.size * 0.5
				var v := oc - c
				var along := v.dot(dir)
				# Must be past this tile's edge in that direction.
				var half := (t.size.x if dir.x != 0 else t.size.y) * 0.5
				if along <= half * 0.5:
					continue
				var side := absf(v.dot(Vector2(dir.y, dir.x)))
				var score := along + side * 2.0
				if score < best_score:
					best_score = score
					best = o
			t.set(d[1], t.get_path_to(best) if best else t.get_path_to(t))

func first() -> UITile:
	return tiles[0] if not tiles.is_empty() else null
