# Ironmon HP Ruler

An [Ironmon Tracker](https://github.com/besteon/Ironmon-Tracker) extension for **Pokémon FireRed / LeafGreen** that overlays a ruler on the enemy's HP bar, making it easy to estimate how much HP they have left at a glance.

<img width="265" height="99" alt="image" src="https://github.com/user-attachments/assets/0488270f-8a75-4d12-9ac2-ea94eb5ea234" />


## What it does

- Draws a **tick mark every 10%** above the enemy HP bar, with taller ticks at 0 / 50 / 100.
- Draws faint **lines across the bar at 25 / 50 / 75%**, with small labeled number boxes underneath.
- Purely visual — it does **not** read or display the enemy's exact HP values.
- Waits for the healthbox slide-in animations before appearing (battle start and switch-ins), and hides while a fainted Pokémon's box is off-screen.
- Works in singles and doubles (a ruler for each enemy slot).

## Requirements

- Ironmon Tracker running on **BizHawk** (the mGBA tracker can't draw overlays)
- Pokémon FireRed or LeafGreen (the ruler stays hidden in other games)

## Install

**Automatic:** in the Tracker, go to Settings (gear) → **Extensions** → **Install New Extension**, and paste this repo's URL:

```
https://github.com/WaffleSmacker/IronmonHpRuler-IronmonExtension
```

## Options

Open the extension's page in the Tracker and click **Options** to configure:

- **Reverse numbers** — show `75 50 25` instead of `25 50 75`, so the labels read as damage dealt rather than HP remaining.
- **Colors** for the tick marks, the lines across the bar, the numbers, and the number boxes (border and fill), as `AARRGGBB` hex (`AA` = opacity, `FF` = solid; plain `RRGGBB` works too).

Choices are saved to the Tracker's `Settings.ini` and persist across restarts.

More knobs (hiding individual elements, position nudging, appear-delay timing) are available as a `Settings` table at the top of `EnemyHPRuler.lua`.

