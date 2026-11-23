extends RefCounted
## Textures and colors for the battle screen, from the placeholder art in
## res://art/ (D-031, docs/ART.md). Sprites are drawn 100 units to a tile and
## import at 2 texture pixels a unit.

const Palette := preload("res://art/palette.gd")
const PX_PER_UNIT := 2.0

static var _cache: Dictionary = {}


static func texture(path: String) -> Texture2D:
	if not _cache.has(path):
		_cache[path] = load(path)
	return _cache[path]


static func alien(id: String) -> Texture2D:
	return texture("res://art/aliens/%s.svg" % id)


static func tower_head(id: String) -> Texture2D:
	return texture("res://art/towers/%s.svg" % id)


static func tower_base() -> Texture2D:
	return texture("res://art/towers/base.svg")


static func core() -> Texture2D:
	return texture("res://art/core/core.svg")


static func halo() -> Texture2D:
	return texture("res://art/fx/halo.svg")


static func icon(klass: String) -> Texture2D:
	return texture("res://art/icons/%s.svg" % klass)


## The Sprite2D scale that draws a sprite at its intended size when a tile is tile_px wide.
static func sprite_scale(tile_px: float) -> float:
	return tile_px / (100.0 * PX_PER_UNIT)


static func class_color(klass: String) -> Color:
	return Palette.CLASS_COLORS.get(klass, Color.WHITE)


## A material that adds light: glows, flashes and tracers.
static func additive() -> CanvasItemMaterial:
	var material := CanvasItemMaterial.new()
	material.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
	return material
