# Pokegear Card Example

Tiny Gen 2 demo mod for the POKéGEAR. Needs **pokegear_cards** enabled.

## What it does

| On the gear | Behavior |
|---|---|
| **DEMO** (new strip card) | Simple scrollable panel; footer counts how many times you opened it |
| **NOTES** (phone row) | Extra row after your contacts; A flashes `NOTED!` |
| **DEMO OK** (clock) | Small line under the time |

Options (all on by default): **SHOW DEMO CARD**, **SHOW PHONE ROW**,
**SHOW CLOCK LINE**.

## Requirements

- Pokémon Gold (or another Gen 2 boot)
- Mod `pokegear_cards` installed and enabled
- This mod enabled (`example_pokegear_card`)

## Install

If you got this from the `pokegear_cards` repo, it lives under `examples/`
and must sit next to other mods to load:

```sh
cp -r mods/pokegear_cards/examples/example_pokegear_card mods/
```

Then enable both mods in the launcher Mods tab (or F10) and open the
POKéGEAR in-game.

## Tests

```sh
luajit mods/example_pokegear_card/tests/example_pokegear_card_test.lua
```
