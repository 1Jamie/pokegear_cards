-- Library entry: publish the append-only Pokegear extension API.
--
--   local api = mod.find("pokegear_cards").exports
--   api.register({ ... })          -- new strip card
--   api.append({ host = "phone", ... })  -- add entry on a vanilla card
--
-- Vanilla CLOCK/MAP/PHONE/RADIO are never replaced.
--
-- Sibling files go through load(mod:read) so they inherit Grandma's Kitchen
-- (src/mods/Sandbox.lua). require("mods.pokegear_cards.cards") would compile
-- against the real _G (package, io, debug) and skip the mod environment.

local function loadSibling(mod, rel)
  local source = mod:read(rel)
  if not source then
    error(("pokegear_cards: %s missing from %s"):format(rel, tostring(mod.path)))
  end
  local chunk, compileErr = load(source, "@" .. rel)
  if not chunk then
    error(("pokegear_cards: %s did not compile: %s"):format(rel, tostring(compileErr)))
  end
  local ok, result = pcall(chunk)
  if not ok then
    error(("pokegear_cards: %s failed: %s"):format(rel, tostring(result)))
  end
  return result
end

return function(mod)
  local Cards = loadSibling(mod, "cards.lua")

  Cards.boot(mod)

  mod.exports.apiVersion = Cards.API_VERSION
  mod.exports.version = mod.manifest and mod.manifest.version or "1.1.2"

  -- Custom strip cards
  mod.exports.register = Cards.register
  mod.exports.unregister = Cards.unregister
  mod.exports.get = Cards.get
  mod.exports.list = Cards.list

  -- Append-only vanilla hosts
  mod.exports.append = Cards.append
  mod.exports.unappend = Cards.unappend
  mod.exports.VANILLA_HOSTS = Cards.VANILLA_HOSTS
  mod.exports.PHONE_INPUT_FORKED = Cards.PHONE_INPUT_FORKED
  mod.exports.OVERLAY_SCISSOR = Cards.OVERLAY_SCISSOR

  -- Shared scratch + predicates
  mod.exports.state = Cards.state
  mod.exports.when = Cards.when
  mod.exports.helpers = Cards.helpers
  mod.exports.DEFAULT_ICON = Cards.DEFAULT_ICON

  -- Test seams (not part of the stable contract)
  mod.exports._resetForTests = Cards.resetForTests
  mod.exports._installed = Cards.installed
end
