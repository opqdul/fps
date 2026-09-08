extends Area3D

## Meters per second; set by the weapon that fired this bullet.
@export var speed := 60.0
## Seconds before the bullet despawns.
const LIFETIME := 2.0

var _life := LIFETIME

func _ready() -> void:
	body_entered.connect(_on_body_entered)

func _physics_process(delta: float) -> void:
	# The bullet flies along its own -Z (the player aims it with look_at()).
	global_position += -global_transform.basis.z * speed * delta
	_life -= delta
	if _life <= 0.0:
		queue_free()

func _on_body_entered(body: Node3D) -> void:
	# Anything with a get_hit() method reacts; everything else just stops the bullet.
	if body.has_method("get_hit"):
		body.get_hit()
		# Tell every peer (via the server) so all machines play the same hit.
		var tid = body.get("target_id")
		if tid != null and Net.role != Net.Role.SOLO:
			get_tree().current_scene.hit_target.rpc(tid)
	queue_free()
