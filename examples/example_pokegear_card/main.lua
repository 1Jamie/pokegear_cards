-- Example consumer for pokegear_cards.
-- Walkthrough: examples/example_pokegear_card/README.md
--   1) strip card   — api.register
--   2) phone row    — api.append host "phone"
--   3) clock line   — api.append host "clock"
-- Gen 2 only; hard-depends on pokegear_cards.

local CARD_ID = "example_demo"
local PHONE_ID = "example_phone_notes"
local CLOCK_ID = "example_clock_line"

return function(mod)
  mod.options:define({
    { key = "show_demo", label = "SHOW DEMO CARD", type = "toggle", default = true },
    { key = "show_phone", label = "SHOW PHONE ROW", type = "toggle", default = true },
    { key = "show_clock", label = "SHOW CLOCK LINE", type = "toggle", default = true },
  })

  local handle = mod.find("pokegear_cards")
  local api = handle and handle.exports
  if not api or api.apiVersion ~= 1 then
    mod.log:warn("pokegear_cards missing or wrong apiVersion; demo idle")
    return
  end

  local H = api.helpers

  -- ------- 1) custom strip card ---------------------------------------------

  api.register({
    id = CARD_ID,
    label = "DEMO",
    icon = api.DEFAULT_ICON,
    priority = 80,
    owner = mod.id,
    visible = api.when.option(mod, "show_demo", true),
    onHighlight = function(gear)
      local s = api.state(CARD_ID)
      if not s.lines then
        s.lines = {
          "POKEGEAR CARDS DEMO",
          "A:OPEN  B:BACK",
          "See README for API.",
        }
        s.cursor = 0
      end
    end,
    open = function(gear)
      local s = api.state(CARD_ID)
      s.opened = (s.opened or 0) + 1
    end,
    draw = function(gear)
      local s = api.state(CARD_ID)
      local lines = s.lines or { "DEMO" }
      local cursor = s.cursor or 0
      H.drawStrip(gear)
      H.textbox(gear, 0, 4, 18, 8)
      for i, line in ipairs(lines) do
        local ty = 5 + (i - 1)
        local text = line
        if #text > 16 then text = text:sub(1, 16) end
        H.text(gear, text, 2, ty)
        if (i - 1) == cursor then
          H.cursor(gear, 1, ty)
        end
      end
      local opened = s.opened or 0
      H.text(gear, ("OPENS %d"):format(opened), 1, 15)
    end,
    update = function(gear, input)
      local s = api.state(CARD_ID)
      local lines = s.lines or { "DEMO" }
      local n = #lines
      if n == 0 then return end
      local cursor = s.cursor or 0
      if input:wasPressed("up") then
        cursor = (cursor - 1) % n
      elseif input:wasPressed("down") then
        cursor = (cursor + 1) % n
      end
      s.cursor = cursor
    end,
  })

  -- ------- 2) phone append (extra row, not a contact rewrite) ---------------

  api.append({
    host = "phone",
    id = PHONE_ID,
    kind = "action",
    label = "NOTES",
    right = "DEMO",
    priority = 20,
    owner = mod.id,
    visible = api.when.option(mod, "show_phone", true),
    onSelect = function(gear)
      local s = api.state(PHONE_ID)
      s.taps = (s.taps or 0) + 1
      -- Tiny feedback on the gear instance; real mods would push a screen.
      gear._exampleNotesFlash = 60
    end,
    draw = function(gear)
      -- Optional overlay after the list (still scissored? phone path draws
      -- append.draw outside the map scissor on purpose — keep it subtle).
      if gear._exampleNotesFlash and gear._exampleNotesFlash > 0 then
        H.text(gear, "NOTED!", 1, 16)
        gear._exampleNotesFlash = gear._exampleNotesFlash - 1
      end
    end,
  })

  -- ------- 3) clock overlay -------------------------------------------------

  api.append({
    host = "clock",
    id = CLOCK_ID,
    kind = "overlay",
    owner = mod.id,
    visible = api.when.option(mod, "show_clock", true),
    draw = function(gear)
      H.text(gear, "DEMO OK", 1, 10)
    end,
  })

  mod.log:info("example_pokegear_card registered (DEMO + phone NOTES + clock)")
end
