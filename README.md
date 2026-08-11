# Pokegear Cards

Gen 2 library mod: other mods can put stuff on the POKéGEAR without each
one monkey-patching `Pokegear`.

- add a whole new strip card (icon up top, your panel underneath)
- append info / actions / overlays onto vanilla CLOCK, MAP, PHONE, RADIO

You cannot replace or hide the vanilla cards. Add only.

| | |
|---|---|
| Mod id | `pokegear_cards` |
| Games | Gen 2 (Gold). Red boots skip it. |
| Permission | `engine_internals` (this lib only; consumers do not need it) |

Enable it in the launcher Mods tab or F10. Point consumers at
`optional_dependencies` if they also run on Gen 1 (hard dep only when
Gold-only, or `MK401` complains).

A runnable consumer lives under [`examples/`](examples/). See
[`examples/README.md`](examples/README.md) for how to load and fork it.

## Why this exists

The engine already has Pokegear *content* seams (phone contacts, landmarks,
radio stations, `phone.contact_list`, …). It does not yet have a Runtime hook
for “another strip card” or “one more phone row”. This lib owns that wrap
once and exposes `mod.exports`.

Same idea as Modern UI: `mod.find`, call the API, never `require` private
files.

## Install / depend

Clone or copy this repo to `mods/pokegear_cards`.

```json
"optional_dependencies": ["pokegear_cards"]
```

```lua
local handle = mod.find("pokegear_cards")
local api = handle and handle.exports
if not api or api.apiVersion ~= 1 then
  return  -- degrade: no gear card this boot
end
```

`mod.find` is nil when the lib is missing, disabled, failed, or has not run
yet. Degrade instead of crashing.

## API (`apiVersion = 1`)

### `register` — new strip card

```lua
api.register({
  id = "mytool",
  label = "MY TOOL",            -- or function(gear) -> string
  icon = api.DEFAULT_ICON,      -- MAP chrome tile; fine for a demo
  priority = 100,               -- lower sorts earlier among custom cards
  owner = mod.id,
  visible = api.when.option(mod, "show_tool", true),
  onHighlight = function(gear) end,  -- strip cursor on your icon
  open = function(gear) end,         -- A entered card mode
  trigger = function(gear, reason) end,  -- "enter" / "leave"
  draw = function(gear)
    local H = api.helpers
    H.drawStrip(gear)
    H.text(gear, "HELLO", 1, 3)
  end,
  update = function(gear, input, dt)
    -- card mode only; B backs to the strip unless busy()
  end,
})
```

Returns an unregister function. Re-registering the same `id` replaces.
Vanilla ids (`clock` / `map` / `phone` / `radio`) are refused — use `append`.

Scratch state: `api.state("mytool")` (do not invent `_kr*` fields on gear).

### `append` — add onto a vanilla card

Contacts stay contacts. Map stays the map. You only add.

```lua
api.append({
  host = "phone",
  id = "my_radar_row",
  kind = "action",              -- action | info | overlay
  label = "RADAR",
  right = function(gear) return "HERE" end,
  onSelect = function(gear) end,
})

api.append({
  host = "map",
  id = "my_roamer_dot",
  draw = function(gear)
    api.helpers.marker(gear, x, y, { 255, 80, 80 })
  end,
})

api.append({
  host = "clock",
  id = "my_egg_hint",
  draw = function(gear)
    api.helpers.text(gear, "EGG 1200", 1, 10)
  end,
})
```

Defaults: phone → `action`, else → `overlay`. Phone `action` / `info` need a
`label`. `info` lists but A does nothing.

Contact *data* still goes through engine registries (`phone_contacts`,
`phone.contact_list`). Phone `append` is for extra UI rows, not Mom’s number.

### Helpers

| Thing | What it is |
|---|---|
| `api.state(id)` | scratch table per card/append id |
| `api.when.*` | `always` / `never` / `all` / `any` / `flag` / `option` |
| `api.helpers` | `text`, `textbox`, `cursor`, `drawStrip`, `marker`, … |
| `api.list()` | debug dump of cards + appends |
| `api.OVERLAY_SCISSOR` | pixel rect overlays get clipped to |
| `api.PHONE_INPUT_FORKED` | always true; documents the phone cost below |

## Caveats

**Phone appends fork the input loop.**  
If any phone append is visible, the lib reimplements DPAD/A for the extended
list and does **not** call engine `updatePhone`. Prefer contact registries
for data; unregister when you do not need the row.

**Map / clock / radio overlays are scissored** to the 20×14 panel under the
strip (`OVERLAY_SCISSOR` = `(0, 16, 160, 112)`).

**No ghosts.** Live registry every update/draw. Unregister while open drops
the icon; focused custom cards kick back to the strip.

**Strip space is finite.** Vanilla icons at 0/2/4/6; customs at 8, 10, …
Cap `iconX` 18 — past that the card is skipped with a log line.

## Tests

```sh
luajit mods/pokegear_cards/tests/pokegear_cards_test.lua
```
