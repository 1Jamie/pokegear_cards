-- Standalone (from the gen1recomp tree):
--   luajit mods/pokegear_cards/examples/example_pokegear_card/tests/example_pokegear_card_test.lua
package.path = "./?.lua;./?/init.lua;" .. package.path

local T = require("tests.modkit")
local GameVersion = require("src.core.GameVersion")

GameVersion.set("gold")

local run = T.sdk.loadMods({
  "mods/pokegear_cards",
  "mods/pokegear_cards/examples/example_pokegear_card",
}, { generation = 2 })

T.eq(#run.errors, 0, "loads clean (" .. tostring(run.errors[1]) .. ")")

local cards = run.loader.exports.pokegear_cards
T.check(cards ~= nil, "pokegear_cards exports present")
T.eq(cards.apiVersion, 1, "apiVersion 1")

T.check(cards.get("example_demo") ~= nil, "DEMO card registered")
T.check(cards.get("example_phone_notes") ~= nil, "phone NOTES append registered")
T.check(cards.get("example_clock_line") ~= nil, "clock overlay registered")

local listed = cards.list()
local kinds = { card = 0, append = 0 }
for _, row in ipairs(listed) do
  kinds[row.kind] = (kinds[row.kind] or 0) + 1
end
T.check(kinds.card >= 1, "list includes a custom card")
T.check(kinds.append >= 2, "list includes phone + clock appends")

local Pokegear = require("src.ui.gen2.Pokegear")
T.check(Pokegear._pokegearCards == true, "shared Pokegear patch installed")

local gear = setmetatable({
  fly = false,
  save = { pokegearFlags = { map = true, phone = true, radio = true } },
}, Pokegear)
gear.cards = gear:visibleCards()
local hasDemo = false
for _, card in ipairs(gear.cards) do
  if card.id == "example_demo" then hasDemo = true end
end
T.check(hasDemo, "DEMO appears in visibleCards")

-- Options gate: flip demo off and refresh.
run.loader.modOptions["example_pokegear_card"] =
  run.loader.modOptions["example_pokegear_card"] or {}
local opts = run.loader.modOptions["example_pokegear_card"]
opts.show_demo = false
gear.cards = gear:visibleCards()
hasDemo = false
for _, card in ipairs(gear.cards) do
  if card.id == "example_demo" then hasDemo = true end
end
T.eq(hasDemo, false, "SHOW DEMO CARD off hides the strip card")
opts.show_demo = true

run.release()
T.finish("example_pokegear_card")
