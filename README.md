# FPS

A small first-person shooter made in Godot 4 (4.7.2). I built this game with
vibe coding in less than a day, going feature by feature with an AI copilot.

## Features

- WASD + mouse movement, sprint with FOV kick, jump, coyote time
- Three weapons: rifle (1), pistol (2), knife (3) with ammo, reload, recoil
- Target dummies with hit reactions (flash, shrink, grow back)
- Pause menu with audio, graphics and control settings
- Health, damage, respawn and blood effects
- Multiplayer: dedicated server, LAN discovery, join by IP, scoreboard, ping
- Main menu with splash screen, server browser and settings

## How to run

1. Open the project in Godot 4.7.2 (import `project.godot`).
2. Press F5 to play from the main menu.

## Controls

| Key         | Action                          |
|-------------|---------------------------------|
| WASD        | Move                            |
| Mouse       | Look                            |
| Left click  | Shoot (hold for auto)           |
| Shift       | Sprint                          |
| Space       | Jump                            |
| R           | Reload                          |
| 1 / 2 / 3   | Rifle / Pistol / Knife          |
| Tab         | Scoreboard (hold)               |
| Esc         | Pause menu                      |

## Dedicated server

Run the project headless as a dedicated server:

```
godot --headless --path . -- --server --name="My Server"
```

Clients find the server through LAN discovery in multiplayer menu, or connect
directly by typing the IP and port (default 9999).
