# Pokegear Cards

Small Gen 2 library mod so other mods can put stuff on the POKéGEAR without
each one monkey-patching `Pokegear` themselves.

You can:

- add a whole new strip card (icon up top, your panel underneath)
- append info / actions / overlays onto the vanilla CLOCK, MAP, PHONE, RADIO

You cannot replace or hide the vanilla cards. That is on purpose. Add stuff,
dont overwrite the gear.

Mod id is `pokegear_cards`. Gen 2 only - a Red boot just skips it. Turn it on
in the launcher Mods tab or the F10 manager. Consumers should list it under
`optional_dependencies` if they also run on Gen 1 (hard dep only if you are
Gold-only, otherwise `MK401` gets mad).

Kanto Reforged's DexNav on Gold is the first real consumer of this. This
README is the author-facing half; the runnable demo is
[`example_pokegear_card`](../examples/example_pokegear_card).

## Why this exists

The engine already has good seams for Pokegear *content* (phone contacts,
landmarks, radio stations, `phone.contact_list`, etc.). What it does not have
yet is a Runtime hook for "put another card on the strip" or "one more row
under the phone list". So every mod that wants that would be have to write their own
fragile wrap of `visibleCards` / `drawPanel`. This lib owns that wrap once and
hands you `mod.exports`.

Same idea as Modern UI's export contract: you `mod.find`, you call the API,
you do not `require` private files.

## Install / depend

```json
"optional_dependencies": ["pokegear_cards"]
```

```lua
local handle = mod.find("pokegear_cards")
local api = handle and handle.exports
if not api or api.apiVersion ~= 1 then
  -- degrade: no gear card this boot
  return
end
```

`mod.find` is nil when the lib is missing, disabled, failed, or has not run
yet. Call `next` / degrade instead of crashing.

## What you can do

### 1. New strip card

```lua
api.register({
  id = "mytool",
  label = "MY TOOL",            -- or function(gear) -> string
  icon = api.DEFAULT_ICON,      -- MAP chrome tile; fine for a demo
  priority = 100,               -- lower sorts earlier among custom cards
  owner = mod.id,
  visible = api.when.option(mod, "show_tool", true),
  onHighlight = function(gear)
    -- strip preview: refresh whatever you show while the icon is lit
  end,
  open = function(gear)
    -- A opened card mode; push a screen, fire a script, whatever
  end,
  trigger = function(gear, reason)
    -- "enter" / "leave"
  end,
  draw = function(gear)
    local H = api.helpers
    H.drawStrip(gear)
    H.text(gear, "HELLO", 1, 3)
  end,
  update = function(gear, input, dt)
    -- card mode only; B already backs out to the strip unless busy()
  end,
})
```

`register` returns an unregister function. Re-registering the same `id`
replaces the old one. Vanilla ids (`clock` / `map` / `phone` / `radio`) are
refused - use `append` for those.

Scratch state lives in `api.state("mytool")` so you dont invent `_krWhatever`
fields on the gear instance.

### 2. Append onto a vanilla card

Contacts stay contacts. Map stays the map. You only *add*.

```lua
-- Phone: rows AFTER the ten contacts. Contacts themselves are untouched.
api.append({
  host = "phone",
  id = "my_radar_row",
  kind = "action",              -- action | info | overlay
  label = "RADAR",
  right = function(gear) return "HERE" end,
  onSelect = function(gear)
    -- A on this row
  end,
})

-- Map: draw AFTER vanilla (markers etc). No cursor steal.
api.append({
  host = "map",
  id = "my_roamer_dot",
  draw = function(gear)
    api.helpers.marker(gear, x, y, { 255, 80, 80 })
  end,
})

-- Clock / radio: same idea, post-draw info.
api.append({
  host = "clock",
  id = "my_egg_hint",
  draw = function(gear)
    api.helpers.text(gear, "EGG 1200", 1, 10)
  end,
})
```

Defaults: phone → `action`, everything else → `overlay`. Phone `action` /
`info` need a `label`. `info` shows up in the list but A does nothing.

For actual contact *data* keep using the engine registries
(`phone_contacts`, `phone.contact_list`). Phone `append` is for extra UI rows
and triggers, not for rewriting Mom's number.

## Helpers worth knowing

| Thing | What it is |
|---|---|
| `api.state(id)` | scratch table per card/append id |
| `api.when.*` | `always` / `never` / `all` / `any` / `flag` / `option` |
| `api.helpers` | `text`, `textbox`, `cursor`, `drawStrip`, `marker`, … |
| `api.list()` | debug dump of cards + appends |
| `api.OVERLAY_SCISSOR` | pixel rect overlays get clipped to |
| `api.PHONE_INPUT_FORKED` | always true; documents the phone cost below |

## Caveats (read these)

**Phone appends fork the input loop.**  
If even one phone append is visible, the lib reimplements DPAD/A for the
extended list and does **not** call the engine's `updatePhone`. Call /
submenu helpers still run, but any future native phone hotkey the engine
adds will get swallowed until your extras are gone. Prefer contact
registries for data. Unregister when you dont need the row.
`PHONE_INPUT_FORKED` is a warning flag, not a toggle.

**Map / clock / radio overlays are scissored.**  
Append draws on those hosts run inside a 20×14 tile panel under the strip
(`OVERLAY_SCISSOR` = `(0, 16, 160, 112)`). Markers that wander into the strip
or off the panel get clipped on purpose so you dont paint over chrome.

**No ghosts.**  
Strip membership and panel dispatch hit the live registry every
update/draw. Unregister while the gear is open and the icon drops; if that
card was focused you get kicked back to the strip. Dont cache `gear.cards`
rows across unregister.

**Strip space is finite.**  
Icons are 2 tiles wide on a 20-wide screen. Vanilla sits at 0/2/4/6. Customs
auto-layout at 8, 10, … Cap is `iconX` 18. Past that the card is skipped with
a log line.

**This mod needs `engine_internals`.**  
It patches `src.ui.gen2.Pokegear` once. You (the consumer) do not need that
permission and should not require Pokegear yourself.

## Tests

```sh
luajit mods/pokegear_cards/tests/pokegear_cards_test.lua
```

Demo mod (register + phone append + clock overlay):

```sh
luajit mods/examples/example_pokegear_card/tests/example_pokegear_card_test.lua
```
