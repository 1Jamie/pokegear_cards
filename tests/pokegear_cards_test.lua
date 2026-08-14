-- Standalone: luajit mods/pokegear_cards/tests/pokegear_cards_test.lua
package.path = "./?.lua;./?/init.lua;" .. package.path

local T = require("tests.modkit")
local GameVersion = require("src.core.GameVersion")

GameVersion.set("gold")

local run = T.sdk.loadMod("mods/pokegear_cards", { generation = 2 })
T.eq(#run.errors, 0, "loads clean (" .. tostring(run.errors[1]) .. ")")

local api = run.loader.exports.pokegear_cards
T.check(api ~= nil, "exports present")
T.eq(api.apiVersion, 1, "apiVersion is 1")
T.check(type(api.register) == "function", "register exported")
T.check(type(api.append) == "function", "append exported")
T.check(type(api.state) == "function", "state exported")
T.check(type(api.when) == "table", "when exported")
T.check(api._installed(), "Pokegear patch installed at boot")
T.eq(api.version, "1.1.2", "manifest version is published on exports")
T.eq(package.loaded["mods.pokegear_cards.cards"], nil,
  "cards.lua is load(mod:read), not require into package.loaded")

local Pokegear = require("src.ui.gen2.Pokegear")
T.check(Pokegear._pokegearCards == true, "class flag set")

api._resetForTests()

-- ------- custom cards

local drawn, updated, highlighted, opened = 0, 0, 0, 0
local unreg, err = api.register({
  id = "testcard",
  label = "TEST",
  owner = "pokegear_cards",
  priority = 50,
  visible = function() return true end,
  onHighlight = function() highlighted = highlighted + 1 end,
  open = function() opened = opened + 1 end,
  draw = function() drawn = drawn + 1 end,
  update = function() updated = updated + 1 end,
})
T.eq(err, nil, "register accepts a full spec (" .. tostring(err) .. ")")
T.check(type(unreg) == "function", "register returns unregister")

local listed = api.list()
T.eq(#listed, 1, "list has one card")
T.eq(listed[1].kind, "card", "list kind is card")
T.eq(listed[1].id, "testcard", "list id")

-- Vanilla-reserved ids are refused; message points at append.
local bad, badErr = api.register({ id = "map", label = "NOPE" })
T.eq(bad, nil, "cannot shadow MAP")
T.check(tostring(badErr):find("append", 1, true) ~= nil,
  "shadow error steers authors to append")

local gear = setmetatable({
  fly = false,
  save = { pokegearFlags = { map = true, phone = true, radio = true } },
}, Pokegear)
gear.cards = gear:visibleCards()
local custom
for _, card in ipairs(gear.cards) do
  if card.id == "testcard" then custom = card end
end
T.check(custom ~= nil, "custom card materialized")
T.eq(custom.iconX, 8, "auto iconX is column 8 after RADIO")

api.register({
  id = "other",
  label = "OTHER",
  priority = 60,
  draw = function() end,
})
gear.cards = gear:visibleCards()
local other
for _, card in ipairs(gear.cards) do
  if card.id == "other" then other = card end
end
T.eq(other.iconX, 10, "second custom card at iconX 10")

for i, card in ipairs(gear.cards) do
  if card.id == "testcard" then gear.cardIndex = i break end
end
gear.mode = "card"
gear.game = {
  input = { wasPressed = function(_, key) return key == "up" end },
}
gear:update(0)
T.eq(updated, 1, "update called in card mode")

gear.mode = "strip"
gear:update(0)
T.check(highlighted >= 1, "onHighlight called in strip mode")

local bag = api.state("testcard")
bag.cursor = 3
T.eq(api.state("testcard").cursor, 3, "state bag persists")

T.check(unreg(), "unregister via returned function")
T.eq(api.get("testcard"), nil, "testcard gone")
T.check(api.unregister("other"), "unregister by id")
T.eq(#api.list(), 0, "registry empty")

-- ------- append-only vanilla hosts

local selected = 0
local apUnreg, apErr = api.append({
  host = "phone",
  id = "extra_row",
  kind = "action",
  label = "RADAR",
  right = "HERE",
  priority = 10,
  onSelect = function() selected = selected + 1 end,
})
T.eq(apErr, nil, "phone append ok (" .. tostring(apErr) .. ")")
T.check(type(apUnreg) == "function", "append returns unappend")

local mapUnreg = api.append({
  host = "map",
  id = "roamer_dot",
  draw = function() end,
})
T.check(type(mapUnreg) == "function", "map append ok")

local listed2 = api.list()
T.eq(#listed2, 2, "list has card appends")
local hosts = {}
for _, row in ipairs(listed2) do
  T.eq(row.kind, "append", "append list kind")
  hosts[row.host] = true
end
T.check(hosts.phone and hosts.map, "phone and map appends listed")

-- Cannot append with vanilla id as the entry id.
local no, noErr = api.append({ host = "phone", id = "phone", label = "X" })
T.eq(no, nil, "append id cannot be vanilla host name")
T.check(type(noErr) == "string", "append id error")

-- Phone list: ten contacts + one action row; A on the extra fires onSelect.
local phoneGear = setmetatable({
  fly = false,
  save = { pokegearFlags = { phone = true } },
  phoneScroll = 7, -- show contacts 8-10 and the append as row 4
  phoneCursor = 3, -- fourth visible row -> index 11
  phoneSubmenu = nil,
  call = nil,
  gfx = nil,
}, Pokegear)
-- Minimal stubs so drawPhone chrome does not explode in headless.
function phoneGear:drawTilemap() end
function phoneGear:drawStrip() end
function phoneGear:tile() end
function phoneGear:textbox() end
function phoneGear:printBoxText() end
function phoneGear:phoneText() return "" end
function phoneGear:phoneContext() return {} end
function phoneGear:drawPhoneSubmenu() end
function phoneGear:text() end
function phoneGear:contactRow(id)
  if not id or id == 0 then return "----------:", nil end
  return "NAME:", "CLASS"
end
function phoneGear:openPhoneSubmenu() end

local Phone = require("src.core.gen2.Phone")
local origContacts = Phone.contacts
Phone.contacts = function()
  return { 1, 2, 3, 4, 5, 6, 7, 8, 9, 10 }
end

phoneGear:drawPhone()
T.check(phoneGear._pgcPhoneRows ~= nil, "extended phone rows cached")
T.eq(#phoneGear._pgcPhoneRows, 11, "10 contacts + 1 append")
T.eq(phoneGear._pgcPhoneRows[11].kind, "action", "last row is append action")

phoneGear.game = {
  input = { wasPressed = function(_, key) return key == "a" end },
}
phoneGear:updatePhone(phoneGear.game.input)
T.eq(selected, 1, "phone append onSelect fired")

-- Vanilla contacts still occupy the first ten slots.
T.eq(phoneGear._pgcPhoneRows[1].kind, "contact", "slot 1 remains a contact")
T.eq(phoneGear._pgcPhoneRows[1].contactId, 1, "contact ids unchanged")

Phone.contacts = origContacts
T.check(apUnreg(), "unappend phone row")
T.check(mapUnreg(), "unappend map overlay")
T.eq(#api.list(), 0, "appends cleared")

-- when helpers
T.eq(api.when.always(), true, "when.always")
T.eq(api.when.never(), false, "when.never")
T.eq(api.when.all(api.when.always, api.when.never)(), false, "when.all")
T.eq(api.when.any(api.when.never, api.when.always)(), true, "when.any")

-- ------- live registry: no ghost after unregister while "open"
local ghostDraws = 0
api.register({
  id = "ghost",
  label = "GHOST",
  draw = function() ghostDraws = ghostDraws + 1 end,
})
local openGear = setmetatable({
  fly = false,
  mode = "card",
  save = { pokegearFlags = { map = true, phone = true, radio = true } },
  game = { input = { wasPressed = function() return false end } },
}, Pokegear)
openGear.cards = openGear:visibleCards()
local ghostIndex
for i, card in ipairs(openGear.cards) do
  if card.id == "ghost" then ghostIndex = i end
end
T.check(ghostIndex ~= nil, "ghost card present before unregister")
openGear.cardIndex = ghostIndex
-- Stale pointer on the instance (pre-fix shape); must not keep dispatching.
openGear.cards[ghostIndex]._pokegearCards = api.get("ghost")
T.check(api.unregister("ghost"), "unregister ghost while open")
openGear:update(0)
local still = false
for _, card in ipairs(openGear.cards) do
  if card.id == "ghost" then still = true end
end
T.eq(still, false, "refreshCards drops unregistered strip icon")
T.eq(openGear.mode, "strip", "leaves card mode when focused card vanishes")
T.eq(ghostDraws, 0, "stale _pokegearCards pointer is ignored")

-- ------- overlay scissor applied for map appends
local scissorCalls = {}
local G = love.graphics
local savedSet, savedGet = G.setScissor, G.getScissor
local prevScissor
G.getScissor = function()
  return prevScissor and prevScissor[1], prevScissor and prevScissor[2],
    prevScissor and prevScissor[3], prevScissor and prevScissor[4]
end
G.setScissor = function(x, y, w, h)
  if x == nil then
    scissorCalls[#scissorCalls + 1] = "clear"
    prevScissor = nil
  else
    scissorCalls[#scissorCalls + 1] = { x, y, w, h }
    prevScissor = { x, y, w, h }
  end
end

api.append({
  host = "map",
  id = "scissor_dot",
  draw = function() end,
})
local mapGear = setmetatable({
  fly = false,
  save = {},
  gfx = { maps = {} },
}, Pokegear)
function mapGear:drawTilemap() end
function mapGear:drawStrip() end
function mapGear:tile() end
function mapGear:drawPlate() end
function mapGear:text() end
function mapGear:region() return "johto" end
function mapGear:mapLandmark() return nil end
function mapGear:playerLandmark() return nil end
function mapGear:drawPlayerIcon() return false end
function mapGear:mapCursorSprite() end
mapGear:drawMap()
local sc = api.OVERLAY_SCISSOR
local saw = false
for _, call in ipairs(scissorCalls) do
  if type(call) == "table"
      and call[1] == sc.x and call[2] == sc.y
      and call[3] == sc.w and call[4] == sc.h then
    saw = true
  end
end
T.check(saw, "map overlay sets OVERLAY_SCISSOR")
T.check(scissorCalls[#scissorCalls] == "clear", "map overlay clears scissor")
G.setScissor = savedSet
G.getScissor = savedGet
api.unappend("scissor_dot")

T.check(api.PHONE_INPUT_FORKED == true, "PHONE_INPUT_FORKED documents the fork")

-- ------- bidirectional card navigation across vanilla + custom strip cards
local navUnreg = api.register({
  id = "nav_demo",
  label = "NAV",
  draw = function() end,
})

local navGear = setmetatable({
  fly = false,
  save = { pokegearFlags = { map = true, phone = true, radio = true } },
  mode = "strip",
  cardIndex = 1,
}, Pokegear)
function navGear:stopRadio() self.radioStopped = (self.radioStopped or 0) + 1 end
function navGear:ensureTuned() self.radioTuned = true end
function navGear:tuneRadio() self.radioTuned = true end
function navGear:tickRadio() end
function navGear:updatePhone() end
function navGear:moveMapCursor() end
function navGear:stations() return { 1, 2, 3, 4 } end

local navInput = {
  pressed = {},
  wasPressed = function(self, k) return self.pressed[k] == true end,
}
navGear.game = { input = navInput }

local function pressNav(k)
  navInput.pressed = { [k] = true }
  navGear:update(0)
  navInput.pressed = {}
end

-- Start on Clock (1)
T.eq(navGear.cardIndex, 1, "nav test starts on card 1 (clock)")
T.eq(navGear.mode, "strip", "starts in strip mode")

-- Right: Clock -> Map (2)
pressNav("right")
T.eq(navGear.cardIndex, 2, "clock right -> map (2)")
T.eq(navGear.mode, "strip", "map in strip mode")

-- Right: Map -> Phone (3)
pressNav("right")
T.eq(navGear.cardIndex, 3, "map right -> phone (3)")
T.eq(navGear.mode, "card", "phone starts in card mode")

-- Right: Phone -> Radio (4)
pressNav("right")
T.eq(navGear.cardIndex, 4, "phone right -> radio (4)")
T.eq(navGear.mode, "card", "radio in card mode")
T.check(navGear.radioTuned, "radio tuned on arrival")

-- Right: Radio -> nav_demo (5) (resolves the dead-end)
pressNav("right")
T.eq(navGear.cardIndex, 5, "radio right -> custom card (5)")
T.eq(navGear.mode, "strip", "custom card starts in strip mode")
T.check((navGear.radioStopped or 0) >= 1, "radio stopped when moving away")

-- Right: nav_demo -> wrap to Clock (1)
pressNav("right")
T.eq(navGear.cardIndex, 1, "custom card right -> wraps to clock (1)")
T.eq(navGear.mode, "strip", "clock in strip mode")

-- Left: Clock -> wrap to nav_demo (5)
pressNav("left")
T.eq(navGear.cardIndex, 5, "clock left -> wraps to custom card (5)")
T.eq(navGear.mode, "strip", "custom card in strip mode")

-- Left: nav_demo -> Radio (4)
pressNav("left")
T.eq(navGear.cardIndex, 4, "custom card left -> radio (4)")
T.eq(navGear.mode, "card", "radio in card mode")

-- Left: Radio -> Phone (3)
pressNav("left")
T.eq(navGear.cardIndex, 3, "radio left -> phone (3)")
T.eq(navGear.mode, "card", "phone in card mode")

-- Left: Phone -> Map (2)
pressNav("left")
T.eq(navGear.cardIndex, 2, "phone left -> map (2)")
T.eq(navGear.mode, "strip", "map in strip mode")

-- Left: Map -> Clock (1)
pressNav("left")
T.eq(navGear.cardIndex, 1, "map left -> clock (1)")
T.eq(navGear.mode, "strip", "clock in strip mode")

-- Open / close custom card
pressNav("left") -- back to custom card (5)
pressNav("a")
T.eq(navGear.mode, "card", "A opens custom card into card mode")
pressNav("b")
T.eq(navGear.mode, "strip", "B exits custom card to strip mode")

navUnreg()

run.release()
T.finish("pokegear_cards")
