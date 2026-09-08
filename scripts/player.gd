extends CharacterBody3D

## Move speed in meters per second.
@export var speed := 5.0
## Upward velocity when jumping (meters per second).
@export var jump_velocity := 4.5
## How sensitive mouse look is. 0.001 to 0.004 feels normal.
@export var mouse_sensitivity := 0.0025

## Movement feel.
@export var sprint_speed := 8.0
## How fast we reach target speed on the ground (m/s per second).
@export var acceleration := 30.0
## Much weaker control while airborne.
@export var air_acceleration := 10.0
## How fast we stop when no input.
@export var friction := 25.0
## You can still jump this long after walking off a ledge.
@export var coyote_time := 0.1
## FOV kick while sprinting for a sense of speed.
@export var base_fov := 75.0
@export var sprint_fov := 82.0
## Flip vertical mouse look.
@export var invert_y := false
## Camera kick + drift while shooting (recoil animation stays either way).
@export var view_kick := true

## Health.
@export var max_health := 100.0
## Seconds without damage before health regenerates.
@export var regen_delay := 4.0
## Health restored per second while regenerating.
@export var regen_rate := 5.0
## Seconds before respawning when dead.
@export var respawn_delay := 2.0

## Emitted whenever the active weapon, ammo or reload state changes.
signal ammo_changed(weapon_name: String, current: int, max_ammo: int, reloading: bool)
## Emitted whenever health changes (the HUD listens).
signal health_changed(current: int, max_hp: int)
## Emitted whenever this player takes damage (HUD flashes blood).
signal player_damaged(amount: int)

## The gun's rest position relative to the camera (right hand, lower right of screen).
const GUN_REST := Vector3(0.35, -0.32, -0.55)
## How fast the bob cycle runs while moving.
const BOB_SPEED := 10.0
## How far the gun sways left/right while walking.
const BOB_SWAY := 0.02
## How far the gun bounces up/down while walking.
const BOB_BOUNCE := 0.025
## How much the gun rolls and pitches while walking.
const BOB_ROLL := 0.03
const BOB_PITCH := 0.015
## How far the legs swing while walking.
const STEP_ANGLE := 0.5
## Look-around swing: a spring that lags behind the mouse, then settles.
const SWING_STIFFNESS := 80.0
const SWING_DAMPING := 12.0
const SWING_IMPULSE := 0.8
const SWING_PITCH := 0.0004 # radians per pixel of vertical lag
const SWING_YAW := 0.0006 # radians per pixel of horizontal lag
const SWITCH_TIME := 0.25
const MELEE_TIME := 0.25
## How long the weapon recoil kicks for.
const RECOIL_TIME := 0.12
## How often the owned player broadcasts its pose in multiplayer (seconds).
const SYNC_INTERVAL := 0.033
## How far behind real time remote players are replayed (interpolation).
const REMOTE_DELAY := 0.1
## Damage dealt by a bullet or knife hit.
const BULLET_DAMAGE := 25

const BULLET_SCENE := preload("res://scenes/Bullet.tscn")
const SHOOT_SND := preload("res://audio/shoot.wav")
## Three different footsteps, picked at random while walking.
const STEP_SNDS := [
	preload("res://audio/step1.wav"),
	preload("res://audio/step2.wav"),
	preload("res://audio/step3.wav"),
]
const RELOAD_SND := preload("res://audio/reload.wav")
const SWITCH_SND := preload("res://audio/switch.wav")
const SWISH_SND := preload("res://audio/swish.wav")
const DAMAGE_SND := preload("res://audio/hit.wav")

@onready var camera: Camera3D = $Camera3D
@onready var weapons: Array = [$Camera3D/Weapons/Rifle, $Camera3D/Weapons/Pistol, $Camera3D/Weapons/Knife]
## The whole weapons container bobs/swings; individual weapons just swap visibility.
@onready var gun: Node3D = $Camera3D/Weapons
@onready var muzzle_light: OmniLight3D = $Camera3D/Weapons/MuzzleFlash
@onready var leg_l: Node3D = $Body/LegL
@onready var leg_r: Node3D = $Body/LegR
@onready var name_tag: Label3D = $NameTag

var current_weapon := 0
var _ammo: Array = []
var _reloading: Array = []
var _reload_left: Array = []
var _fire_cd: Array = []
var _bob_time := 0.0
var _anim_time := 0.0
var _swing := Vector2.ZERO
var _swing_vel := Vector2.ZERO
var _land_dip := 0.0
var _switch_t := 0.0
var _melee_t := 0.0
var _step_t := 0.0
var _recoil_t := 0.0
var _recoil_power := 0.0
var _was_airborne := false
var _sprinting := false
var _coyote := 0.0
var _sync_timer := 0.0

## Remote copies of other players replay from a small packet buffer.
var _net_samples: Array = []

var health := 100.0
var _dead := false
var _regen_timer := 0.0
var _home := Vector3.ZERO

## Round-robin pools so rapid fire doesn't cut a still-playing shot sound.
var _shoot_snds: Array[AudioStreamPlayer] = []
var _shoot_idx := 0
var _reload_snd: AudioStreamPlayer
var _switch_snd: AudioStreamPlayer
var _step_snd: AudioStreamPlayer
var _swish_snd: AudioStreamPlayer
var _damage_snd: AudioStreamPlayer3D

func _ready() -> void:
	_home = global_position
	name_tag.visible = Net.role != Net.Role.SOLO and not _is_owned()
	if _is_owned():
		camera.current = true
		if DisplayServer.get_name() != "headless":
			Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	for w in weapons:
		_ammo.append(w.mag_size)
		_reloading.append(false)
		_reload_left.append(0.0)
		_fire_cd.append(0.0)
	# Round-robin shot players: each player can only play once, so overlapping
	# rapid shots need several of them.
	for i in 3:
		_shoot_snds.append(_make_player(SHOOT_SND, -1.0))
	_reload_snd = _make_player(RELOAD_SND, -4.0)
	_switch_snd = _make_player(SWITCH_SND, -6.0)
	_step_snd = _make_player(STEP_SNDS[0], -6.0)
	_swish_snd = _make_player(SWISH_SND, -4.0)
	# Positional damage sound (falls off with distance, keeps direction).
	_damage_snd = AudioStreamPlayer3D.new()
	_damage_snd.stream = DAMAGE_SND
	_damage_snd.volume_db = -4.0
	_damage_snd.attenuation_model = AudioStreamPlayer3D.ATTENUATION_DISABLED
	add_child(_damage_snd)
	health = max_health
	health_changed.emit(int(health), int(max_health))
	_select_weapon(0)

func _make_player(stream: AudioStream, volume: float) -> AudioStreamPlayer:
	var p := AudioStreamPlayer.new()
	p.stream = stream
	p.volume_db = volume
	add_child(p)
	return p

## The HUD calls this once at startup to get the initial weapon/ammo state.
func hud_info() -> Array:
	var i := current_weapon
	return [weapons[i].display_name, _ammo[i], weapons[i].mag_size, _reloading[i]]

# ---------- multiplayer ----------

## Called on every peer's copy of the owned player with the owner's latest pose.
@rpc("any_peer", "call_remote", "unreliable", 20)
func sync_pos(new_pos: Vector3, new_yaw: float, new_pitch: float) -> void:
	if multiplayer.get_remote_sender_id() != get_multiplayer_authority():
		return
	# Buffer recent poses; _remote_process interpolates between them.
	_net_samples.append([Time.get_ticks_msec() / 1000.0, new_pos, new_yaw, new_pitch])
	if _net_samples.size() > 20:
		_net_samples.pop_front()

func _remote_process(delta: float) -> void:
	if _dead or _net_samples.size() < 2:
		return
	# Replay the pose from REMOTE_DELAY ago, interpolating between packets.
	var t := Time.get_ticks_msec() / 1000.0 - REMOTE_DELAY
	var idx := -1
	for i in range(_net_samples.size() - 1, -1, -1):
		if _net_samples[i][0] <= t:
			idx = i
			break
	if idx == -1:
		var first: Array = _net_samples[0]
		position = first[1]
		rotation.y = first[2]
		camera.rotation.x = first[3]
		return
	if idx + 1 < _net_samples.size():
		var a: Array = _net_samples[idx]
		var b: Array = _net_samples[idx + 1]
		var w := clampf((t - a[0]) / maxf(b[0] - a[0], 0.0001), 0.0, 1.0)
		position = a[1].lerp(b[1], w)
		rotation.y = lerp_angle(a[2], b[2], w)
		camera.rotation.x = lerp_angle(a[3], b[3], w)
	else:
		var last: Array = _net_samples[-1]
		position = last[1]
		rotation.y = last[2]
		camera.rotation.x = last[3]

func _unhandled_input(event: InputEvent) -> void:
	# Mouse look: rotate the body left/right, pitch the camera up/down.
	if event is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		rotate_y(-event.relative.x * mouse_sensitivity)
		var y_sign := 1.0 if invert_y else -1.0
		camera.rotation.x = clampf(
			camera.rotation.x + y_sign * event.relative.y * mouse_sensitivity,
			deg_to_rad(-85.0),
			deg_to_rad(85.0)
		)
		# Kick the swing spring: the gun lags behind the view and settles.
		_swing_vel += event.relative * SWING_IMPULSE
		_swing_vel = _swing_vel.limit_length(600.0)

	# A click re-captures the mouse if it was released.
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
		if Input.mouse_mode != Input.MOUSE_MODE_CAPTURED:
			Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
			_fire_cd[current_weapon] = 0.25 # don't fire the click that captured the mouse

	# R starts a reload, 1/2/3 switch weapons.
	if event.is_action_pressed("reload"):
		_start_reload()
	elif event.is_action_pressed("weapon_1"):
		_select_weapon(0)
	elif event.is_action_pressed("weapon_2"):
		_select_weapon(1)
	elif event.is_action_pressed("weapon_3"):
		_select_weapon(2)

func _is_owned() -> bool:
	# is_multiplayer_authority() errors in export templates when no peer is
	# assigned (solo), so decide ownership ourselves.
	if multiplayer.multiplayer_peer == null:
		return true # solo: the only player is ours
	return get_multiplayer_authority() == multiplayer.get_unique_id()

func _physics_process(delta: float) -> void:
	# Remote copies don't move themselves; they follow sync_pos.
	if not _is_owned():
		_remote_process(delta)
		return
	if _dead:
		return

	# Gravity: only pull down when we're not standing on something.
	if not is_on_floor():
		velocity.y -= ProjectSettings.get_setting("physics/3d/default_gravity") * delta

	# WASD comes in as a 2D vector: x = left/right, y = forward/backward.
	var input_dir := Input.get_vector("move_left", "move_right", "move_forward", "move_backward")
	# Rotate that vector with the body so "forward" matches where we look.
	var direction := (transform.basis * Vector3(input_dir.x, 0.0, input_dir.y)).normalized()
	# Sprint: hold Shift while moving on the ground to run faster.
	var moving := direction != Vector3.ZERO and is_on_floor()
	_sprinting = Input.is_action_pressed("sprint") and moving
	var move_speed := sprint_speed if _sprinting else speed

	# Acceleration-based movement: ease toward the target velocity instead of
	# teleporting to it, with much weaker control while airborne.
	var accel := acceleration if is_on_floor() else air_acceleration
	if direction != Vector3.ZERO:
		velocity.x = move_toward(velocity.x, direction.x * move_speed, accel * delta)
		velocity.z = move_toward(velocity.z, direction.z * move_speed, accel * delta)
	else:
		velocity.x = move_toward(velocity.x, 0.0, friction * delta)
		velocity.z = move_toward(velocity.z, 0.0, friction * delta)

	# Coyote time: you can still jump shortly after walking off a ledge.
	_coyote = coyote_time if is_on_floor() else maxf(_coyote - delta, 0.0)
	if Input.is_action_just_pressed("jump") and _coyote > 0.0:
		velocity.y = jump_velocity
		_coyote = 0.0

	# move_and_slide() applies velocity and slides along walls for us.
	move_and_slide()

	# FOV kick while sprinting.
	camera.fov = lerpf(camera.fov, sprint_fov if _sprinting else base_fov, minf(delta * 6.0, 1.0))

	# Broadcast our pose to the server and other players.
	if Net.role != Net.Role.SOLO:
		_sync_timer += delta
		if _sync_timer >= SYNC_INTERVAL:
			_sync_timer = 0.0
			sync_pos.rpc(position, rotation.y, camera.rotation.x)

	# ---------- timers, swing spring, lights ----------
	_anim_time += delta
	for i in weapons.size():
		_fire_cd[i] = maxf(_fire_cd[i] - delta, 0.0)
	_swing_vel += -_swing * SWING_STIFFNESS * delta
	_swing_vel *= exp(-delta * SWING_DAMPING)
	_swing += _swing_vel * delta
	_swing = _swing.limit_length(300.0)
	muzzle_light.light_energy = maxf(muzzle_light.light_energy - delta * 80.0, 0.0)
	_switch_t = maxf(_switch_t - delta, 0.0)
	_melee_t = maxf(_melee_t - delta, 0.0)
	_recoil_t = maxf(_recoil_t - delta, 0.0)

	# Hold left mouse to fire (the shoot action is the left button).
	if Input.is_action_pressed("shoot") and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		_try_fire()

	# Reload timer for the active weapon.
	var i := current_weapon
	if _reloading[i]:
		_reload_left[i] -= delta
		if _reload_left[i] <= 0.0:
			_reloading[i] = false
			_ammo[i] = weapons[i].mag_size
			_sync_hud()

	# Health regeneration after a quiet period (only report whole HP changes).
	_regen_timer += delta
	if not _dead and _regen_timer >= regen_delay and health < max_health:
		var before := int(health)
		health = minf(health + regen_rate * delta, max_health)
		if int(health) != before:
			health_changed.emit(int(health), int(max_health))

	# Landing dip: when we touch the ground after being airborne.
	var on_floor := is_on_floor()
	if on_floor and _was_airborne:
		_land_dip = 0.05
	_was_airborne = not on_floor
	_land_dip *= exp(-delta * 10.0)

	# ---------- gun animation ----------
	var target_pos := GUN_REST
	var target_rot := Vector3.ZERO

	if moving:
		# Walk bob: sway, bounce, roll and pitch (faster while sprinting).
		_bob_time += delta * BOB_SPEED * (1.25 if _sprinting else 1.0)
		target_pos.x += sin(_bob_time) * BOB_SWAY
		target_pos.y -= absf(cos(_bob_time)) * BOB_BOUNCE
		target_rot.z += sin(_bob_time * 0.5) * BOB_ROLL
		target_rot.x += absf(cos(_bob_time)) * BOB_PITCH
	else:
		# Idle: gentle breathing while standing still.
		_bob_time = 0.0
		target_pos.y += sin(_anim_time * 2.0) * 0.004
		target_rot.x += sin(_anim_time * 1.3) * 0.006

	# Landing dip (recovers via the exp decay above).
	target_pos.y -= _land_dip

	# Reload: dip the gun down and tilt it, then bring it back.
	if _reloading[i]:
		var k: float = 1.0 - _reload_left[i] / weapons[i].reload_time
		var dip := sin(k * PI)
		target_pos.y -= dip * 0.18
		target_rot.x += dip * 0.5

	# Weapon switch: quick dip and recover.
	if _switch_t > 0.0:
		var k := 1.0 - _switch_t / SWITCH_TIME
		target_pos.y -= sin(k * PI) * 0.12
		target_rot.x += sin(k * PI) * 0.3

	# Knife swing: a fast sideways slash.
	if _melee_t > 0.0:
		var k := 1.0 - _melee_t / MELEE_TIME
		target_rot.z += sin(k * PI) * 0.7
		target_rot.x += sin(k * PI) * 0.25

	# Recoil: snap the gun back and muzzle-up, then recover.
	if _recoil_t > 0.0:
		var k := 1.0 - _recoil_t / RECOIL_TIME
		target_pos.z += sin(k * PI) * 0.05 * _recoil_power
		target_rot.x += sin(k * PI) * 0.1 * _recoil_power

	# Look-around swing lag.
	target_rot.x += _swing.y * SWING_PITCH
	target_rot.z -= _swing.x * SWING_YAW

	# Ease toward the target pose so transitions stay smooth.
	gun.position = gun.position.lerp(target_pos, minf(delta * 14.0, 1.0))
	gun.rotation = gun.rotation.lerp(target_rot, minf(delta * 14.0, 1.0))

	# ---------- body / legs ----------
	var leg_angle := sin(_bob_time) * STEP_ANGLE if moving else 0.0
	leg_l.rotation.x = lerpf(leg_l.rotation.x, leg_angle, minf(delta * 12.0, 1.0))
	leg_r.rotation.x = lerpf(leg_r.rotation.x, -leg_angle, minf(delta * 12.0, 1.0))

	# Footsteps: random pick, slight pitch variation, one per step cycle.
	# (The timer resets when idle so the FIRST step of a walk always plays.)
	if moving and _bob_time >= _step_t:
		_step_t = _bob_time + PI
		_step_snd.stream = STEP_SNDS[randi_range(0, STEP_SNDS.size() - 1)]
		_step_snd.pitch_scale = randf_range(0.92, 1.08)
		_step_snd.play()
	elif not moving:
		_step_t = 0.0

	# Hide your own upper body when looking down so it doesn't fill the view
	# (legs stay visible; remote players keep their full body).
	var top_visible := camera.rotation.x > -0.5
	$Body/Torso.visible = top_visible
	$Body/Shoulders.visible = top_visible

func _try_fire() -> void:
	var i := current_weapon
	var w = weapons[i]
	if _reloading[i] or _fire_cd[i] > 0.0:
		return
	if w.melee:
		_fire_cd[i] = w.fire_cooldown
		_melee_t = MELEE_TIME
		_swish_snd.play()
		_melee_hit()
		return
	if _ammo[i] <= 0:
		_start_reload()
		return
	_ammo[i] -= 1
	_fire_cd[i] = w.fire_cooldown
	# Recoil: kick the view up a little (you fight it back), tilt the gun,
	# and nudge the yaw so sustained fire drifts like a real weapon.
	_recoil_t = RECOIL_TIME
	_recoil_power = w.recoil
	if view_kick:
		# Kick the view up a little (you fight it back) and nudge the yaw so
		# sustained fire drifts like a real weapon.
		camera.rotation.x += 0.008 * w.recoil
		rotate_y(randf_range(-0.002, 0.002) * w.recoil)
	var muzzle: Marker3D = w.get_node("Muzzle")
	muzzle_light.global_position = muzzle.global_position
	muzzle_light.light_energy = 5.0
	_shoot_idx = _shoot_idx + 1
	if _shoot_idx >= _shoot_snds.size():
		_shoot_idx = 0
	_shoot_snds[_shoot_idx].play()
	_spawn_bullet(w)
	_sync_hud()

func _start_reload() -> void:
	var i := current_weapon
	var w = weapons[i]
	if _reloading[i] or _ammo[i] >= w.mag_size:
		return
	_reloading[i] = true
	_reload_left[i] = w.reload_time
	_reload_snd.play()
	_sync_hud()

func _select_weapon(idx: int) -> void:
	if idx != current_weapon:
		current_weapon = idx
		_switch_t = SWITCH_TIME
		_switch_snd.play()
		_reloading[idx] = false # switching cancels the old weapon's reload
	for i in weapons.size():
		weapons[i].visible = i == idx
	_sync_hud()

func _sync_hud() -> void:
	var i := current_weapon
	ammo_changed.emit(weapons[i].display_name, _ammo[i], weapons[i].mag_size, _reloading[i])

func _spawn_bullet(w: Node3D) -> void:
	# Spawn at the barrel tip, aimed along the camera's view direction.
	var muzzle: Marker3D = w.get_node("Muzzle")
	var dir := -camera.global_transform.basis.z
	var bullet: Area3D = BULLET_SCENE.instantiate()
	bullet.speed = w.bullet_speed
	get_tree().current_scene.add_child(bullet)
	bullet.global_position = muzzle.global_position
	bullet.look_at(muzzle.global_position + dir)

func _melee_hit() -> void:
	# Knife: a short ray cast from the camera; anything with get_hit() reacts.
	var from := camera.global_position
	var dir := -camera.global_transform.basis.z
	var query := PhysicsRayQueryParameters3D.create(from, from + dir * 2.5, 3)
	query.exclude = [get_rid()] # don't hit ourselves
	var hit := get_world_3d().direct_space_state.intersect_ray(query)
	if hit and hit.collider.has_method("get_hit"):
		hit.collider.get_hit()
		var tid = hit.collider.get("target_id")
		if tid != null and Net.role != Net.Role.SOLO:
			get_tree().current_scene.hit_target.rpc(tid)

func get_hit() -> void:
	# A bullet or knife hit this player: damage applies on every machine.
	if Net.role != Net.Role.SOLO:
		get_tree().current_scene.damage_player.rpc(get_multiplayer_authority(), BULLET_DAMAGE)
	else:
		take_damage(BULLET_DAMAGE)

func take_damage(amount: int) -> void:
	if _dead:
		return
	health -= amount
	_regen_timer = 0.0
	_damage_snd.play()
	_spawn_blood()
	player_damaged.emit(amount)
	health_changed.emit(int(health), int(max_health))
	if health <= 0.0:
		_die()

## A quick red particle burst at the victim's chest, on every machine.
func _spawn_blood() -> void:
	var parts := CPUParticles3D.new()
	parts.one_shot = true
	parts.explosiveness = 1.0
	parts.amount = 32
	parts.lifetime = 0.7
	var mesh := SphereMesh.new()
	mesh.radius = 0.05
	mesh.height = 0.1
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.7, 0.05, 0.05)
	mesh.material = mat
	parts.mesh = mesh
	parts.direction = Vector3.UP
	parts.spread = 60.0
	parts.gravity = Vector3(0, -9.0, 0)
	parts.initial_velocity_min = 1.0
	parts.initial_velocity_max = 3.5
	get_tree().current_scene.add_child(parts)
	# Must be inside the tree before its global transform is set.
	parts.global_position = global_position + Vector3(0, 1.2, 0)
	# Particles get frustum-culled if their AABB doesn't cover the burst.
	parts.visibility_aabb = AABB(Vector3(-1.5, -1.5, -1.5), Vector3(3, 3, 3))
	parts.emitting = true
	get_tree().create_timer(1.2).timeout.connect(parts.queue_free)

func _die() -> void:
	if _dead:
		return
	apply_dead_state(true)
	if Net.role != Net.Role.SOLO:
		get_tree().current_scene.set_dead.rpc(get_multiplayer_authority(), true)
	await get_tree().create_timer(respawn_delay).timeout
	health = max_health
	apply_dead_state(false)
	position = _home
	_regen_timer = 0.0
	health_changed.emit(int(health), int(max_health))
	if Net.role != Net.Role.SOLO:
		get_tree().current_scene.set_dead.rpc(get_multiplayer_authority(), false)

## Visual/collision state for a dead player (applied on every machine).
func apply_dead_state(dead: bool) -> void:
	_dead = dead
	visible = not dead
	collision_layer = 0 if dead else 1
