extends Node2D

const OUTLINE_THICKNESS: float = 0.065
const OUTLINE_COLOR: Color = Color(0.0, 0.0, 0.0, 1.0)
const TEAM_TINT_STRENGTH: float = 0.32

var _marble: Marble
var _core_sprite: Sprite2D
var _core_material: ShaderMaterial

func _ready() -> void:
	_marble = get_parent() as Marble
	if _marble == null:
		return

	_core_sprite = _marble.get_node_or_null("CoreSprite") as Sprite2D
	if _core_sprite == null:
		return

	var old_halo := _core_sprite.get_node_or_null("Halo")
	if old_halo != null:
		old_halo.queue_free()

	_setup_core_material()
	_apply_team_color(_resolve_team_color())

	if not _marble.team_changed.is_connected(_on_team_changed):
		_marble.team_changed.connect(_on_team_changed)


func _setup_core_material() -> void:
	if _core_material == null:
		_core_material = ShaderMaterial.new()
		_core_material.shader = Shader.new()
		_core_material.shader.code = """
shader_type canvas_item;

uniform vec4 team_color : source_color = vec4(0.35, 0.85, 0.55, 1.0);
uniform vec4 outline_color : source_color = vec4(0.0, 0.0, 0.0, 1.0);
uniform float outline_thickness : hint_range(0.0, 0.2) = 0.065;
uniform float team_tint_strength : hint_range(0.0, 1.0) = 0.32;

void fragment() {
	vec4 tex = texture(TEXTURE, UV);
	vec2 p = UV - vec2(0.5);
	float d = length(p);
	float radius = 0.5;
	float aa = max(fwidth(d), 0.0015) * 1.8;

	float alpha_mask = 1.0 - smoothstep(radius - aa, radius + aa, d);
	float fill_mask = 1.0 - smoothstep(radius - outline_thickness - aa, radius - outline_thickness + aa, d);
	vec3 tinted_tex = mix(tex.rgb, tex.rgb * team_color.rgb, team_tint_strength);
	vec3 final_rgb = mix(outline_color.rgb, tinted_tex, fill_mask);
	COLOR = vec4(final_rgb, tex.a * alpha_mask);
}
"""

	_core_material.set_shader_parameter("outline_color", OUTLINE_COLOR)
	_core_material.set_shader_parameter("outline_thickness", OUTLINE_THICKNESS)
	_core_material.set_shader_parameter("team_tint_strength", TEAM_TINT_STRENGTH)
	_core_sprite.material = _core_material


func _on_team_changed(_marble_ref: Marble, _new_team: int) -> void:
	_apply_team_color(_resolve_team_color())


func _apply_team_color(team_color: Color) -> void:
	if _core_material != null:
		_core_material.set_shader_parameter("team_color", team_color)


func _resolve_team_color() -> Color:
	if App != null and App.config != null:
		var colors: Array[Color] = App.config.team_colors
		if _marble.team_id >= 0 and _marble.team_id < colors.size():
			return colors[_marble.team_id]
	return Color(0.4, 0.8, 1.0, 1.0)
