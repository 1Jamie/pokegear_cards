-- Library entry: publish the append-only Pokegear extension API.
--
--   local api = mod.find("pokegear_cards").exports
--   api.register({ ... })          -- new strip card
--   api.append({ host = "phone", ... })  -- add entry on a vanilla card
--
-- Vanilla CLOCK/MAP/PHONE/RADIO are never replaced.

local Cards = require("mods.pokegear_cards.cards")

return function(mod)
  Cards.boot(mod)

  mod.exports.apiVersion = Cards.API_VERSION
  mod.exports.version = mod.manifest and mod.manifest.version or "1.1.0"

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
