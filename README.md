# NameplateThreat

Addon for WoW Forever that shows threat on enemy nameplates, inspired by the WeakAura
"Threat Differential on Nameplates".

**Status: untested in game.** Expect to adjust things after the first run.

## What it does

- Shows the threat difference between you and the group member with the most threat
  (or the runner-up, when you are tanking) as a number left of each enemy nameplate.
- Colour follows tank status:
  - Green: tanking with a comfortable lead
  - Yellow: tanking, another tank is second
  - Orange (`!!!`): tanking, a non-tank is close behind
  - Blue: another tank has the mob
  - Red: nobody is tanking
- If Forever blocks the threat numbers, the addon falls back to colour only (from the
  plain threat status) instead of throwing Lua errors.

## Install

Copy the `NameplateThreat` folder into `Interface/AddOns/` and `/reload`.

If the addon shows as out of date, change `## Interface:` in `NameplateThreat.toc` to the
number the other addons in your Forever install use.

## Commands

- `/nthreat` shows the current secure-tank threshold and whether the addon is in full or
  colour-only mode.
- `/nthreat 1500` sets the threshold for "securely tanking" (default 1000).

## Known unknowns

- Whether `UnitDetailedThreatSituation` returns usable values in Forever is not confirmed.
- The default threshold is a guess.

Bug reports with the Lua error text are welcome as issues.
