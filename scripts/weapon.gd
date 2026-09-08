extends Node3D

## Display name shown in the HUD.
@export var display_name := "RIFLE"
## Seconds between attacks (smaller = faster).
@export var fire_cooldown := 0.12
## Rounds per magazine (unused for melee weapons).
@export var mag_size := 12
## Seconds a reload takes.
@export var reload_time := 1.2
## Bullet speed in meters per second.
@export var bullet_speed := 60.0
## Melee weapons (the knife) don't use ammo or bullets.
@export var melee := false
## Recoil strength: 1.0 is the rifle, 0 sounds like a launcher on rails.
@export var recoil := 1.0
