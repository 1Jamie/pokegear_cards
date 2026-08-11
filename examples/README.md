# Examples

Consumer demos that ship with **pokegear_cards**. They are normal mods nested
under `examples/` so the engine does not auto-load them (discovery is only
one level under `mods/`).

## What’s here

| Folder | What it is |
|---|---|
| [`example_pokegear_card/`](example_pokegear_card) | Tiny Gen 2 mod: DEMO strip card, phone NOTES row, clock DEMO OK line |

Read that folder’s own [`README.md`](example_pokegear_card/README.md) for what
the mod *does* in-game (player-facing). The implementation to copy is
[`example_pokegear_card/main.lua`](example_pokegear_card/main.lua) — it is the
full `mod.find` → `register` / `append` integration against this library’s
exports. API details live in the [library README](../README.md).

## How to run an example

```sh
# from your gen1recomp tree, with this repo at mods/pokegear_cards
cp -r mods/pokegear_cards/examples/example_pokegear_card mods/

python3 tools/modkit.py validate mods/example_pokegear_card --base imported
luajit mods/example_pokegear_card/tests/example_pokegear_card_test.lua
```

Enable **pokegear_cards** and **example_pokegear_card** (launcher Mods tab or
F10), boot Gold, open the POKéGEAR.

## How to build on an example

1. Copy `example_pokegear_card` to `mods/<your_id>/`
2. Edit `manifest.json` (`id`, `name`, `description`)
3. Edit `main.lua`: change the card/append ids and replace the DEMO UI
4. Keep `"dependencies": ["pokegear_cards"]` (or optional + degrade on Red)
5. Talk only to `mod.find("pokegear_cards").exports` — never `require` Pokegear

```sh
cp -r mods/pokegear_cards/examples/example_pokegear_card mods/my_gear_tool
# edit, validate, enable, play
```
