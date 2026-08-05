class_name CelestialBodySprite
extends Node2D

const EARTH_TEXTURE := preload("res://assets/video/celestial/sources/earth_blue_marble_2048.jpg")
const MOON_TEXTURE := preload("res://assets/video/celestial/sources/moon_lroc_color_2048.jpg")
const SUN_TEXTURE := preload("res://assets/video/celestial/sources/sun_sdo_full_disk.jpg")
const SPHERE_SHADER := preload("res://assets/shaders/celestial_sphere.gdshader")
const SUN_SHADER := preload("res://assets/shaders/celestial_sun.gdshader")

var body_kind := "earth"
var display_radius := 20.0
var body_sprite: Sprite2D
var sphere_material: ShaderMaterial
var sun_material: ShaderMaterial


func _ready() -> void:
	_ensure_sprite()


func configure(kind: String, world_position: Vector2, radius: float) -> void:
	_ensure_sprite()
	body_kind = kind
	display_radius = radius
	position = world_position
	visible = true
	var detail_mix := smoothstep(11.0, 28.0, radius)
	match kind:
		"sun":
			body_sprite.texture = SUN_TEXTURE
			body_sprite.material = sun_material
			sun_material.set_shader_parameter("detail_mix", detail_mix)
		"moon":
			body_sprite.texture = MOON_TEXTURE
			body_sprite.material = sphere_material
			sphere_material.set_shader_parameter("longitude_offset", 0.02)
			sphere_material.set_shader_parameter("average_color", Color("#AAA7A0"))
			sphere_material.set_shader_parameter("rim_color", Color("#E8E2D7"))
			sphere_material.set_shader_parameter("tint", Color("#E3DDD2"))
			sphere_material.set_shader_parameter("light_direction", Vector3(-0.48, -0.16, 0.86))
			sphere_material.set_shader_parameter("minimum_light", 0.16)
			sphere_material.set_shader_parameter("rim_strength", 0.20)
			sphere_material.set_shader_parameter("detail_mix", detail_mix)
		_:
			body_sprite.texture = EARTH_TEXTURE
			body_sprite.material = sphere_material
			sphere_material.set_shader_parameter("longitude_offset", 0.08)
			sphere_material.set_shader_parameter("average_color", Color("#24568A"))
			sphere_material.set_shader_parameter("rim_color", Color("#69A9FF"))
			sphere_material.set_shader_parameter("tint", Color("#C7E2FF"))
			sphere_material.set_shader_parameter("light_direction", Vector3(-0.24, -0.14, 0.96))
			sphere_material.set_shader_parameter("minimum_light", 0.28)
			sphere_material.set_shader_parameter("rim_strength", 0.72)
			sphere_material.set_shader_parameter("detail_mix", detail_mix)
	var texture_size := body_sprite.texture.get_size()
	body_sprite.scale = Vector2(
		2.0 * radius / texture_size.x,
		2.0 * radius / texture_size.y
	)
	queue_redraw()


func hide_body() -> void:
	visible = false


func _draw() -> void:
	var glow_color := Color("#FFC76A") if body_kind == "sun" else Color("#69A9FF")
	if body_kind == "moon":
		glow_color = Color("#D9D5CC")
	draw_circle(Vector2.ZERO, display_radius * 2.5, Color(glow_color, 0.025))
	draw_circle(Vector2.ZERO, display_radius * 1.65, Color(glow_color, 0.065))
	draw_circle(Vector2.ZERO, display_radius + 2.5, Color(glow_color, 0.25))


func _ensure_sprite() -> void:
	if body_sprite != null:
		return
	body_sprite = Sprite2D.new()
	body_sprite.centered = true
	body_sprite.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	body_sprite.texture_repeat = CanvasItem.TEXTURE_REPEAT_ENABLED
	add_child(body_sprite)
	sphere_material = ShaderMaterial.new()
	sphere_material.shader = SPHERE_SHADER
	sphere_material.set_shader_parameter("light_direction", Vector3(-0.45, -0.28, 0.85))
	sphere_material.set_shader_parameter("tint", Color.WHITE)
	sun_material = ShaderMaterial.new()
	sun_material.shader = SUN_SHADER
	sun_material.set_shader_parameter("source_center", Vector2(0.5, 0.465))
	sun_material.set_shader_parameter("source_radius", Vector2(0.435, 0.435))
	sun_material.set_shader_parameter("tint", Color("#FFE2A8"))
