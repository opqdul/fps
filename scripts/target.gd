extends StaticBody3D

## How long the shrink takes after a hit (seconds).
@export var shrink_time := 0.15
## How long the grow-back takes (seconds).
@export var grow_time := 0.6
## How fast the white hit-flash fades away.
@export var flash_fade := 2.5
## Unique index (1, 2, 3...) used to sync hits across the network.
@export var target_id := 0

const FLASH_SHADER := preload("res://shaders/target_flash.gdshader")
const HIT_SND := preload("res://audio/hit.wav")

var _anim := 0 # 0 = idle, 1 = shrinking, 2 = growing
var _t := 0.0
var _home := Vector3.ZERO
var _flash := 0.0

@onready var _mesh: MeshInstance3D = $Mesh
var _mat: ShaderMaterial
var _hit_snd: AudioStreamPlayer3D

func _ready() -> void:
	# Remember where this target originally stands.
	_home = position
	# Each target gets its OWN material instance, so flashes don't sync
	# between targets that share the scene's mesh.
	_mat = ShaderMaterial.new()
	_mat.shader = FLASH_SHADER
	_mesh.material_override = _mat
	# Positional hit sound: still placed in 3D (you hear its direction),
	# but with attenuation disabled so it's always clearly audible.
	_hit_snd = AudioStreamPlayer3D.new()
	_hit_snd.stream = HIT_SND
	_hit_snd.attenuation_model = AudioStreamPlayer3D.ATTENUATION_DISABLED
	_hit_snd.volume_db = 2.0
	add_child(_hit_snd)

func get_hit() -> void:
	# Called by a bullet: flash white and start the shrink-grow cycle.
	_flash = 1.0
	_hit_snd.play()
	if _anim != 0:
		return # Already animating: ignore extra hits.
	_anim = 1
	_t = 0.0

func _process(delta: float) -> void:
	if _flash > 0.0:
		_flash = maxf(_flash - delta * flash_fade, 0.0)
		_mat.set_shader_parameter("flash", _flash)

	match _anim:
		1: # Shrink from full size to nothing.
			_t += delta
			var k := clampf(_t / shrink_time, 0.0, 1.0)
			scale = Vector3.ONE * (1.0 - k)
			if k >= 1.0:
				_anim = 2
				_t = 0.0
		2: # Grow back to full size (smoothstep gives a soft ease-out).
			_t += delta
			var k := smoothstep(0.0, 1.0, clampf(_t / grow_time, 0.0, 1.0))
			scale = Vector3.ONE * k
			if k >= 1.0:
				_anim = 0
				scale = Vector3.ONE
