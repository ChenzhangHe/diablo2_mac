# 灰烬圣印 · Ashen Sigil

An original isometric action RPG for macOS (Apple Silicon), written in Swift + SpriteKit.
See [PLAN.md](PLAN.md) for the design and milestone plan.

## Run

```bash
swift run AshenSigil          # debug run
swift test                    # core logic tests
./scripts/bundle.sh           # build/AshenSigil.app (release)
open build/AshenSigil.app
```

## Controls (current)

| Key | Action |
|---|---|
| Left click / hold | Move (A* pathfinding) / attack monster under cursor |
| 1 / 2 | Health / mana potion (heals over time) |
| I / B | Inventory (left click pick/place, right click equip/use) |
| C | Character sheet |
| Esc | Close panels |
| Right click / Q W E R | Use skill bound to that key |
| T | Skill trees (left click learn; hover + Q/W/E/R/right click to bind) |
| P | Read a town portal scroll |
| Tab | Automap |
| Click NPC / portal / waypoint | Talk, trade, travel |
| F5 | New game (next seed) |

## Layout

- `Sources/AshenCore` — pure game logic (world gen, RNG, math). No rendering; unit-tested.
- `Sources/AshenApp` — SpriteKit rendering, input, UI. All art is procedurally generated.
- `Tests/AshenCoreTests` — XCTest suite.

Debug: `ASHEN_SNAPSHOT=out.png swift run AshenSigil` renders a screenshot and quits.
