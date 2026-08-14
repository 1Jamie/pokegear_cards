-- Pokegear card registry: shared, append-only surface for Gen 2 gear UI.
--
-- Contract:
--   * ADD custom strip cards (full panel control: draw / update / triggers).
--   * ADD entries onto vanilla CLOCK / MAP / PHONE / RADIO (overlays + phone
--     rows). Vanilla cards are never replaced, hidden, or rewritten.
--   * Consumers use mod.find("pokegear_cards").exports — never require
--     Pokegear themselves.
--
-- The engine documents phone/radio/landmarks *content* registries, but not
-- custom cards or UI appends. This library is that interim inter-mod seam.

local Cards = {}

Cards.API_VERSION = 1
Cards.DEFAULT_ICON = 0x40
Cards.BLANK_TILE = 0x4f
Cards.MAX_ICON_X = 18
Cards.VANILLA_HOSTS = { clock = true, map = true, phone = true, radio = true }
Cards.PHONE_ROWS = 4
Cards.PHONE_CONTACTS = 10
-- Overlay scissor: below the 2-row strip, 20x14 tiles (rows 2..15). Keeps
-- map/radio/clock append draws off strip chrome and the far bottom edge.
Cards.OVERLAY_SCISSOR = { x = 0, y = 2 * 8, w = 20 * 8, h = 14 * 8 }
-- When any phone append is visible, updatePhone is fully forked (see README).
Cards.PHONE_INPUT_FORKED = true

local customEntries = {} -- strip cards
local customById = {}

local appendEntries = {} -- vanilla host appends
local appendById = {}
local appendByHost = { clock = {}, map = {}, phone = {}, radio = {} }

-- Per-card / per-append scratch bags (mods should not invent _kr* fields).
local stateBags = {}

local installed = false
local log

local function info(fmt, ...)
  if log and log.info then log:info(fmt, ...) end
end

local function warn(fmt, ...)
  if log and log.warn then log:warn(fmt, ...) end
end

local function sortByPriority(list)
  table.sort(list, function(a, b)
    local pa, pb = a.priority or 100, b.priority or 100
    if pa ~= pb then return pa < pb end
    return tostring(a.id) < tostring(b.id)
  end)
end

local function rebuildHostIndex()
  appendByHost = { clock = {}, map = {}, phone = {}, radio = {} }
  for _, entry in ipairs(appendEntries) do
    local bucket = appendByHost[entry.host]
    if bucket then bucket[#bucket + 1] = entry end
  end
  for _, bucket in pairs(appendByHost) do sortByPriority(bucket) end
end

local function resolveLabel(entry, gear)
  local label = entry.label
  if type(label) == "function" then
    local ok, out = pcall(label, gear)
    if ok and type(out) == "string" then return out end
    return entry.id
  end
  return label or entry.id
end

local function resolveText(value, gear, fallback)
  if value == nil then return fallback end
  if type(value) == "function" then
    local ok, out = pcall(value, gear)
    if ok and out ~= nil then return tostring(out) end
    return fallback
  end
  return tostring(value)
end

local function isVisible(entry, gear)
  if entry.visible == nil then return true end
  local ok, out = pcall(entry.visible, gear)
  if not ok then
    warn("visible(%s) error: %s", entry.id, tostring(out))
    return false
  end
  return out and true or false
end

local function visibleHostAppends(host, gear)
  local out = {}
  for _, entry in ipairs(appendByHost[host] or {}) do
    if isVisible(entry, gear) then out[#out + 1] = entry end
  end
  return out
end

local function runOverlayDraws(host, gear)
  for _, entry in ipairs(visibleHostAppends(host, gear)) do
    if type(entry.draw) == "function" then
      local ok, err = pcall(entry.draw, gear)
      if not ok then warn("append.draw(%s) error: %s", entry.id, tostring(err)) end
    end
  end
end

-- Clip append draws to the panel interior so markers cannot paint the strip
-- or spill past the gear frame. Restores any prior scissor (nested safe).
local function runOverlayDrawsClipped(host, gear)
  local G = love.graphics
  local sc = Cards.OVERLAY_SCISSOR
  local px, py, pw, ph = G.getScissor()
  G.setScissor(sc.x, sc.y, sc.w, sc.h)
  local ok, err = pcall(runOverlayDraws, host, gear)
  if px then
    G.setScissor(px, py, pw, ph)
  else
    G.setScissor()
  end
  if not ok then
    warn("overlay(%s) error: %s", host, tostring(err))
  end
end

-- Rebuild the strip list from the live registry, keeping the selected card
-- by id when it still exists. Call on every update/draw so unregister while
-- the gear is open cannot leave a ghost icon or panel.
local function refreshCards(self)
  if self.fly then return end
  local prev = self.cards and self.cards[self.cardIndex or 1]
  local prevId = prev and prev.id
  self.cards = self:visibleCards()
  if prevId then
    for i, card in ipairs(self.cards) do
      if card.id == prevId then
        self.cardIndex = i
        return
      end
    end
  end
  local n = #self.cards
  if n == 0 then
    self.cardIndex = 1
  elseif (self.cardIndex or 1) > n then
    self.cardIndex = n
  elseif (self.cardIndex or 1) < 1 then
    self.cardIndex = 1
  end
end

local function materializeCustom(entry, gear, iconX)
  -- Only id/label/icon/iconX are load-bearing on the instance. Live dispatch
  -- always goes through customById[id] so unregister cannot ghost a panel.
  return {
    id = entry.id,
    label = resolveLabel(entry, gear),
    icon = entry.icon or Cards.DEFAULT_ICON,
    iconX = iconX,
  }
end

local function phoneCombined(gear)
  local Phone = require("src.core.gen2.Phone")
  local contacts = Phone.contacts(gear.save)
  local extras = visibleHostAppends("phone", gear)
  local rows = {}
  for i = 1, Cards.PHONE_CONTACTS do
    rows[i] = { kind = "contact", contactId = contacts[i] or 0 }
  end
  for _, entry in ipairs(extras) do
    -- info rows are drawn but not selectable; action rows take A.
    rows[#rows + 1] = {
      kind = entry.kind == "info" and "info" or "action",
      entry = entry,
    }
  end
  return rows
end

local function phoneSelectionRow(gear)
  local rows = gear._pgcPhoneRows or phoneCombined(gear)
  local index = (gear.phoneScroll or 0) + (gear.phoneCursor or 0) + 1
  return rows[index], index, rows
end

local function install()
  if installed then return true end
  local ok, Pokegear = pcall(require, "src.ui.gen2.Pokegear")
  if not ok or not Pokegear then
    warn("src.ui.gen2.Pokegear unavailable; cards idle")
    return false
  end
  if Pokegear._pokegearCards then
    installed = true
    return true
  end
  Pokegear._pokegearCards = true
  installed = true

  local Chrome = require("src.ui.gen2.Chrome")
  local Phone = require("src.core.gen2.Phone")

  -- ----- custom strip cards -------------------------------------------------

  local origVisible = Pokegear.visibleCards
  function Pokegear:visibleCards()
    local out = origVisible(self)
    if self.fly then return out end
    local maxX = -2
    for _, card in ipairs(out) do
      local x = tonumber(card.iconX) or 0
      if x > maxX then maxX = x end
    end
    for _, entry in ipairs(customEntries) do
      if isVisible(entry, self) then
        local iconX = entry.iconX
        if iconX == nil then
          maxX = maxX + 2
          iconX = maxX
        else
          iconX = tonumber(iconX) or maxX
          if iconX > maxX then maxX = iconX end
        end
        if iconX > Cards.MAX_ICON_X then
          warn("card %s needs iconX=%d; strip full, skipped", entry.id, iconX)
        else
          out[#out + 1] = materializeCustom(entry, self, iconX)
        end
      end
    end
    return out
  end

  local origStrip = Pokegear.drawStrip
  function Pokegear:drawStrip()
    refreshCards(self)
    local cards = self.cards or {}
    local maxX = 7
    local hasCustom = false
    for _, card in ipairs(cards) do
      if customById[card.id] then hasCustom = true end
      local right = (tonumber(card.iconX) or 0) + 1
      if right > maxX then maxX = right end
    end
    if not hasCustom and maxX <= 7 then
      return origStrip(self)
    end
    local blank = Cards.BLANK_TILE
    for x = 0, maxX do
      self:tile(blank, x, 0)
      self:tile(blank, x, 1)
    end
    for _, card in ipairs(cards) do
      local n, x = card.icon, card.iconX
      if n and x then
        self:tile(n, x, 0)
        self:tile(n + 1, x + 1, 0)
        self:tile(n + 0x10, x, 1)
        self:tile(n + 0x11, x + 1, 1)
      end
    end
  end

  -- Live registry only. Never trust a pointer baked into self.cards.
  local function customFor(self)
    local card = self:card()
    if not card then return nil, nil end
    return customById[card.id], card
  end

  local origDrawPanel = Pokegear.drawPanel
  function Pokegear:drawPanel()
    refreshCards(self)
    local entry, card = customFor(self)
    if not entry or type(entry.draw) ~= "function" then
      return origDrawPanel(self)
    end
    local G = love.graphics
    if self:styled() then
      local ground = self.groundColor and self:groundColor() or { 0, 0, 0 }
      G.setColor(ground[1] / 255, ground[2] / 255, ground[3] / 255, 1)
      G.rectangle("fill", 0, 0, 20 * 8, 18 * 8)
      local ok, err = pcall(entry.draw, self)
      if not ok then warn("draw(%s) error: %s", entry.id, tostring(err)) end
      if self.drawModeArrow then self:drawModeArrow() end
      G.setColor(1, 1, 1, 1)
    else
      Chrome.clear()
      Chrome.box(0, 0, 20, 4)
      Chrome.print(card.label or entry.id, 2, 1)
      local ok, err = pcall(entry.draw, self)
      if not ok then warn("draw(%s) error: %s", entry.id, tostring(err)) end
    end
  end

  local function fireTrigger(entry, gear, reason)
    if type(entry.trigger) == "function" then
      local ok, err = pcall(entry.trigger, gear, reason)
      if not ok then warn("trigger(%s) error: %s", entry.id, tostring(err)) end
    end
    if reason == "enter" and type(entry.open) == "function" then
      local ok, err = pcall(entry.open, gear)
      if not ok then warn("open(%s) error: %s", entry.id, tostring(err)) end
    end
  end

  local function stepCard(gear, delta)
    local n = gear.cards and #gear.cards or 0
    if n <= 1 then return end
    local cur = gear.cardIndex or 1
    local nextIndex = cur + delta
    if nextIndex > n then nextIndex = 1
    elseif nextIndex < 1 then nextIndex = n end

    local oldCard = gear.cards[cur]
    local oldId = oldCard and oldCard.id
    if oldId == "radio" then
      gear:stopRadio()
    end
    gear.call = nil
    gear.phoneSubmenu = nil

    gear.cardIndex = nextIndex
    local newCard = gear.cards[nextIndex]
    local newId = newCard and newCard.id
    if newId == "radio" then
      gear:ensureTuned()
      gear.mode = "card"
    elseif newId == "phone" then
      gear.mode = "card"
    else
      gear.mode = "strip"
    end
  end

  local origUpdate = Pokegear.update
  function Pokegear:update(dt)
    if self.fly then return origUpdate(self, dt) end
    local input = self.game and self.game.input
    if not input then return end

    local prior = self.cards and self.cards[self.cardIndex or 1]
    local priorId = prior and prior.id
    local priorWasCustom = priorId ~= nil and not Cards.VANILLA_HOSTS[priorId]
    refreshCards(self)

    local card = self:card()
    local cardId = card and card.id
    local custom = cardId and customById[cardId]
    local isCustomStrip = custom ~= nil

    -- 1. Custom strip card in card mode
    if isCustomStrip and self.mode == "card" then
      self.iconTimer = ((self.iconTimer or 0) + 1) % 32
      local busy = false
      if type(custom.busy) == "function" then
        local ok, out = pcall(custom.busy, self)
        busy = ok and out and true or false
      end
      if not busy and input:wasPressed("b") then
        self.mode = "strip"
        if type(custom.onLeave) == "function" then pcall(custom.onLeave, self) end
        fireTrigger(custom, self, "leave")
        return
      end
      if type(custom.update) == "function" then
        local ok, err = pcall(custom.update, self, input, dt)
        if not ok then warn("update(%s) error: %s", custom.id, tostring(err)) end
      end
      return
    end

    -- Custom card unregistered while focused: drop to strip
    if self.mode == "card" and priorWasCustom and not customById[priorId] then
      self.mode = "strip"
    end

    -- 2. Strip mode navigation across ANY card
    if self.mode == "strip" then
      if isCustomStrip and type(custom.onHighlight) == "function" then
        pcall(custom.onHighlight, self)
      end
      if input:wasPressed("left") then
        stepCard(self, -1)
        return
      elseif input:wasPressed("right") then
        stepCard(self, 1)
        return
      elseif input:wasPressed("a") then
        self.mode = "card"
        if isCustomStrip then
          if type(custom.onEnter) == "function" then pcall(custom.onEnter, self) end
          fireTrigger(custom, self, "enter")
        elseif cardId == "radio" then
          self:ensureTuned()
        end
        return
      elseif input:wasPressed("b") then
        if self.onClose then self.onClose() end
        return
      end
      return
    end

    -- 3. Card mode on vanilla host cards (bidirectional navigation + host loops)
    if cardId == "phone" then
      local phoneBusy = (self.call ~= nil or self.phoneSubmenu ~= nil)
      if not phoneBusy then
        if input:wasPressed("left") then
          stepCard(self, -1)
          return
        elseif input:wasPressed("right") then
          stepCard(self, 1)
          return
        elseif input:wasPressed("b") then
          if self.onClose then self.onClose() end
          return
        end
      end
      self:updatePhone(input)
      return
    elseif cardId == "radio" then
      if input:wasPressed("left") then
        stepCard(self, -1)
        return
      elseif input:wasPressed("right") then
        stepCard(self, 1)
        return
      elseif input:wasPressed("b") then
        self.mode = "strip"
        self:stopRadio()
        return
      end
      self:ensureTuned()
      if input:wasPressed("up") then
        local stations = self.stations and self:stations() or {}
        if self.station < #stations then
          self.station = self.station + 1
          self:tuneRadio()
        end
      elseif input:wasPressed("down") then
        if self.station > 1 then
          self.station = self.station - 1
          self:tuneRadio()
        end
      end
      self:tickRadio()
      return
    elseif cardId == "map" then
      if input:wasPressed("left") then
        stepCard(self, -1)
        return
      elseif input:wasPressed("right") then
        stepCard(self, 1)
        return
      elseif input:wasPressed("b") then
        self.mode = "strip"
        return
      end
      self:moveMapCursor(input)
      return
    elseif cardId == "clock" then
      if input:wasPressed("left") then
        stepCard(self, -1)
        return
      elseif input:wasPressed("right") then
        stepCard(self, 1)
        return
      elseif input:wasPressed("b") then
        self.mode = "strip"
        return
      end
      return
    end
  end

  -- ----- append-only overlays on vanilla cards ------------------------------

  local origDrawClock = Pokegear.drawClock
  function Pokegear:drawClock()
    origDrawClock(self)
    runOverlayDrawsClipped("clock", self)
  end

  local origDrawMap = Pokegear.drawMap
  function Pokegear:drawMap()
    origDrawMap(self)
    runOverlayDrawsClipped("map", self)
  end

  local origDrawRadio = Pokegear.drawRadio
  function Pokegear:drawRadio()
    origDrawRadio(self)
    runOverlayDrawsClipped("radio", self)
  end

  local origDrawPhone = Pokegear.drawPhone
  function Pokegear:drawPhone()
    local extras = visibleHostAppends("phone", self)
    if #extras == 0 then
      return origDrawPhone(self)
    end
    -- Same chrome as vanilla; list is contacts + appended rows (additive).
    self:drawTilemap(self.gfx and self.gfx.cards and self.gfx.cards.phone)
    self:drawStrip()
    self:tile(0x3c, 17, 1)
    self:tile(0x3d, 18, 1)
    self:tile(0x3e, 17, 2)
    if Phone.mapHasService(self:phoneContext()) then
      self:tile(0x3f, 18, 2)
    end
    self:textbox(0, 12, 18, 4)
    if self.call then
      Chrome.printWrapped(self.call.text or self:phoneText("GearEllipse"),
        1, 14, 18, 3)
    else
      self:printBoxText(self:phoneText("AskWhoCall"))
    end

    local rows = phoneCombined(self)
    self._pgcPhoneRows = rows
    local maxScroll = math.max(0, #rows - Cards.PHONE_ROWS)
    if (self.phoneScroll or 0) > maxScroll then self.phoneScroll = maxScroll end

    for row = 1, Cards.PHONE_ROWS do
      local item = rows[row + (self.phoneScroll or 0)]
      local ty = 4 + (row - 1) * 2
      if item and item.kind == "contact" then
        local label, className = self:contactRow(item.contactId or 0)
        self:text(label, 2, ty)
        if className then self:text(className, 5, ty + 1) end
      elseif item and item.entry then
        local label = resolveLabel(item.entry, self)
        local right = resolveText(item.entry.right, self, "")
        if #label > 12 then label = label:sub(1, 12) end
        self:text(label, 2, ty)
        if right ~= "" then
          if #right > 6 then right = right:sub(1, 6) end
          self:text(right, 12, ty)
        end
        if item.kind == "info" then
          -- Dim cue: no class line; cursor still lands here but A is a no-op.
        end
      end
    end
    Chrome.cursor(1, 4 + (self.phoneCursor or 0) * 2)
    self:drawPhoneSubmenu()
    -- Optional phone overlays (badges, etc.) after the list.
    for _, entry in ipairs(extras) do
      if type(entry.draw) == "function" then
        pcall(entry.draw, self)
      end
    end
  end

  -- PHONE INPUT FORK: when any phone append is visible, this path does NOT
  -- call origUpdatePhone. DPAD/A for the extended list (10 contacts + append
  -- rows) are reimplemented here. Engine changes to native phone input
  -- (new hotkeys, debug toggles, SELECT handlers, …) are swallowed until
  -- extras are unregistered. Call/submenu still delegate to vanilla helpers.
  -- Documented as Cards.PHONE_INPUT_FORKED / README "Known limits".
  local origUpdatePhone = Pokegear.updatePhone
  function Pokegear:updatePhone(input)
    local extras = visibleHostAppends("phone", self)
    if #extras == 0 then
      return origUpdatePhone(self, input)
    end
    if self.call then
      if input:wasPressed("a") or input:wasPressed("b") then
        self:hangUp()
      end
      return
    end
    if self.phoneSubmenu then
      self:updatePhoneSubmenu(input)
      return
    end

    local rows = phoneCombined(self)
    self._pgcPhoneRows = rows
    local total = #rows
    local maxScroll = math.max(0, total - Cards.PHONE_ROWS)

    if input:wasPressed("a") then
      local item = rows[(self.phoneScroll or 0) + (self.phoneCursor or 0) + 1]
      if not item then return end
      if item.kind == "contact" then
        if (item.contactId or 0) ~= 0 then self:openPhoneSubmenu() end
        return
      end
      if item.kind == "action" and item.entry then
        if type(item.entry.onSelect) == "function" then
          local ok, err = pcall(item.entry.onSelect, self)
          if not ok then
            warn("append.onSelect(%s) error: %s", item.entry.id, tostring(err))
          end
        end
        if type(item.entry.trigger) == "function" then
          pcall(item.entry.trigger, self, "select")
        end
      end
      return
    end

    if input:wasPressed("up") then
      if self.phoneCursor > 0 then
        self.phoneCursor = self.phoneCursor - 1
      elseif self.phoneScroll > 0 then
        self.phoneScroll = self.phoneScroll - 1
      end
    elseif input:wasPressed("down") then
      if self.phoneCursor < Cards.PHONE_ROWS - 1
          and (self.phoneScroll or 0) + self.phoneCursor + 1 < total then
        self.phoneCursor = self.phoneCursor + 1
      elseif (self.phoneScroll or 0) < maxScroll then
        self.phoneScroll = self.phoneScroll + 1
      end
    end
  end

  -- phoneSelection must resolve contacts for the submenu when an append
  -- extended the list; vanilla reads scroll+cursor into phoneList only.
  local origPhoneSelection = Pokegear.phoneSelection
  function Pokegear:phoneSelection()
    local extras = visibleHostAppends("phone", self)
    if #extras == 0 then return origPhoneSelection(self) end
    local item = select(1, phoneSelectionRow(self))
    if item and item.kind == "contact" then return item.contactId or 0 end
    return 0
  end

  info("Pokegear card registry installed")
  return true
end

-- ------- public: custom strip cards -----------------------------------------

--- Register a custom strip card (never a vanilla id).
-- Spec fields:
--   id, label, icon?, iconX?, priority?, owner?, visible?
--   draw?, update?, busy?, onEnter?, onLeave?, onHighlight?
--   open?(gear)      -- fired on strip->card (after onEnter); push screens etc.
--   trigger?(gear, reason) -- "enter" | "leave" | (future reasons)
-- @return unregister fn | nil, err
function Cards.register(spec)
  if type(spec) ~= "table" then return nil, "spec must be a table" end
  local id = spec.id
  if type(id) ~= "string" or id == "" then return nil, "spec.id is required" end
  if spec.label == nil then return nil, "spec.label is required" end
  if type(spec.label) ~= "string" and type(spec.label) ~= "function" then
    return nil, "spec.label must be a string or function"
  end
  if Cards.VANILLA_HOSTS[id] then
    return nil, "spec.id '" .. id .. "' is a vanilla Pokegear card; "
      .. "use append{ host = \"" .. id .. "\", ... } to add entries"
  end

  install()

  local entry = {
    id = id,
    label = spec.label,
    icon = spec.icon,
    iconX = spec.iconX,
    priority = tonumber(spec.priority) or 100,
    owner = spec.owner,
    visible = spec.visible,
    draw = spec.draw,
    update = spec.update,
    busy = spec.busy,
    onEnter = spec.onEnter,
    onLeave = spec.onLeave,
    onHighlight = spec.onHighlight,
    open = spec.open,
    trigger = spec.trigger,
  }

  if customById[id] then
    for i, old in ipairs(customEntries) do
      if old.id == id then customEntries[i] = entry break end
    end
    info("replaced custom Pokegear card %s", id)
  else
    customEntries[#customEntries + 1] = entry
    info("registered Pokegear card %s", id)
  end
  customById[id] = entry
  sortByPriority(customEntries)
  return function() return Cards.unregister(id) end
end

function Cards.unregister(id)
  if type(id) ~= "string" then return false end
  if Cards.VANILLA_HOSTS[id] then return false end
  if not customById[id] and not appendById[id] then return false end
  if customById[id] then
    customById[id] = nil
    for i = #customEntries, 1, -1 do
      if customEntries[i].id == id then table.remove(customEntries, i) end
    end
    stateBags[id] = nil
  end
  if appendById[id] then
    return Cards.unappend(id)
  end
  return true
end

function Cards.get(id)
  return customById[id] or appendById[id]
end

function Cards.list()
  local out = {}
  for _, entry in ipairs(customEntries) do
    out[#out + 1] = {
      kind = "card",
      id = entry.id,
      label = entry.label,
      icon = entry.icon or Cards.DEFAULT_ICON,
      iconX = entry.iconX,
      priority = entry.priority,
      owner = entry.owner,
      hasDraw = type(entry.draw) == "function",
      hasUpdate = type(entry.update) == "function",
    }
  end
  for _, entry in ipairs(appendEntries) do
    out[#out + 1] = {
      kind = "append",
      host = entry.host,
      id = entry.id,
      label = entry.label,
      priority = entry.priority,
      owner = entry.owner,
      entryKind = entry.kind,
      hasDraw = type(entry.draw) == "function",
      hasOnSelect = type(entry.onSelect) == "function",
    }
  end
  return out
end

-- ------- public: append to vanilla hosts ------------------------------------

--- Add an entry onto a vanilla card. Never replaces vanilla content.
-- Spec:
--   host     "clock"|"map"|"phone"|"radio" (required)
--   id       unique string (required; must not be a vanilla host name)
--   label    string|fn  (required for phone action/info rows; optional else)
--   kind     "action"|"info"|"overlay" (default: phone -> "action", else "overlay")
--   right    string|fn  (phone row right column)
--   priority number
--   owner    string
--   visible  fn(gear)->bool
--   draw     fn(gear)   -- painted AFTER vanilla (map markers, clock footer…)
--   onSelect fn(gear)   -- phone action rows (A)
--   trigger  fn(gear, reason)  -- "select" on phone actions
function Cards.append(spec)
  if type(spec) ~= "table" then return nil, "spec must be a table" end
  local host = spec.host
  if not Cards.VANILLA_HOSTS[host] then
    return nil, "spec.host must be clock, map, phone, or radio"
  end
  local id = spec.id
  if type(id) ~= "string" or id == "" then return nil, "spec.id is required" end
  if Cards.VANILLA_HOSTS[id] then
    return nil, "spec.id cannot be a vanilla host name"
  end
  if customById[id] then
    return nil, "spec.id '" .. id .. "' is already a custom card"
  end

  local kind = spec.kind
  if kind == nil then
    kind = (host == "phone") and "action" or "overlay"
  end
  if kind ~= "action" and kind ~= "info" and kind ~= "overlay" then
    return nil, "spec.kind must be action, info, or overlay"
  end
  if host == "phone" and (kind == "action" or kind == "info") then
    if spec.label == nil then
      return nil, "phone action/info appends require spec.label"
    end
  end

  install()

  local entry = {
    host = host,
    id = id,
    label = spec.label,
    kind = kind,
    right = spec.right,
    priority = tonumber(spec.priority) or 100,
    owner = spec.owner,
    visible = spec.visible,
    draw = spec.draw,
    onSelect = spec.onSelect,
    trigger = spec.trigger,
  }

  if appendById[id] then
    for i, old in ipairs(appendEntries) do
      if old.id == id then appendEntries[i] = entry break end
    end
    info("replaced append %s on %s", id, host)
  else
    appendEntries[#appendEntries + 1] = entry
    info("appended %s on %s", id, host)
  end
  appendById[id] = entry
  rebuildHostIndex()
  return function() return Cards.unappend(id) end
end

function Cards.unappend(id)
  if type(id) ~= "string" or not appendById[id] then return false end
  appendById[id] = nil
  for i = #appendEntries, 1, -1 do
    if appendEntries[i].id == id then table.remove(appendEntries, i) end
  end
  stateBags[id] = nil
  rebuildHostIndex()
  return true
end

--- Scratch table for a card/append id (created on first touch).
function Cards.state(id)
  if type(id) ~= "string" or id == "" then return nil end
  local bag = stateBags[id]
  if not bag then
    bag = {}
    stateBags[id] = bag
  end
  return bag
end

-- ------- gating helpers -----------------------------------------------------

Cards.when = {
  -- Use directly: visible = api.when.always
  always = function() return true end,
  never = function() return false end,
  all = function(...)
    local preds = { ... }
    return function(gear)
      for _, pred in ipairs(preds) do
        if type(pred) == "function" then
          if not pred(gear) then return false end
        end
      end
      return true
    end
  end,
  any = function(...)
    local preds = { ... }
    return function(gear)
      for _, pred in ipairs(preds) do
        if type(pred) == "function" and pred(gear) then return true end
      end
      return false
    end
  end,
  -- ENGINE_* / pokegearFlags / save.flags style boolean map.
  flag = function(key)
    return function(gear)
      local save = gear and (gear.save or (gear.game and gear.game.save))
      if not save then return false end
      if save.flags and save.flags[key] then return true end
      if save.engineFlags and save.engineFlags[key] then return true end
      if save.pokegearFlags and save.pokegearFlags[key] then return true end
      if save.eventFlags and save.eventFlags[key] then return true end
      return false
    end
  end,
  option = function(mod, key, want)
    return function()
      if not mod or not mod.options then return false end
      local value = mod.options:get(key)
      if want == nil then return value and true or false end
      return value == want
    end
  end,
}

function Cards.installed()
  return installed
end

function Cards.resetForTests()
  customEntries = {}
  customById = {}
  appendEntries = {}
  appendById = {}
  rebuildHostIndex()
  stateBags = {}
end

function Cards.bindLog(modLog)
  log = modLog
end

Cards.helpers = {
  DEFAULT_ICON = Cards.DEFAULT_ICON,
  BLANK_TILE = Cards.BLANK_TILE,
  MAX_ICON_X = Cards.MAX_ICON_X,
  VANILLA_HOSTS = Cards.VANILLA_HOSTS,

  text = function(gear, str, tx, ty)
    if gear.text then
      gear:text(str, tx, ty)
    else
      require("src.ui.gen2.Chrome").print(str, tx, ty)
    end
  end,

  cursor = function(_, tx, ty)
    require("src.ui.gen2.Chrome").cursor(tx, ty)
  end,

  textbox = function(gear, tx, ty, interiorW, interiorH)
    if gear.textbox then
      gear:textbox(tx, ty, interiorW, interiorH)
    elseif gear.drawPlate then
      gear:drawPlate(tx, ty, interiorW + 2, interiorH + 2)
    end
  end,

  drawStrip = function(gear)
    if gear.drawStrip then gear:drawStrip() end
  end,

  drawModeArrow = function(gear)
    if gear.drawModeArrow then gear:drawModeArrow() end
  end,

  -- Tiny marker helper for map overlays (pixel rect fallback).
  marker = function(gear, x, y, rgb)
    local G = love.graphics
    local c = rgb or { 255, 0, 0 }
    G.setColor(c[1] / 255, c[2] / 255, c[3] / 255, 1)
    G.rectangle("fill", (x or 0) - 2, (y or 0) - 2, 4, 4)
    G.setColor(1, 1, 1, 1)
  end,
}

function Cards.boot(mod)
  Cards.bindLog(mod and mod.log)
  install()
end

return Cards
