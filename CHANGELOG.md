# Changelog

## [1.1.1] — 2026-08-11

### Fixed

- Unregister while the Pokegear is open no longer ghosts: cards refresh from
  the live registry each update/draw; dispatch never trusts a baked entry
  pointer on `self.cards`. Focused custom cards drop to strip mode when
  removed.
- Map / clock / radio append draws are scissored to the 20×14-tile interior
  below the strip (`OVERLAY_SCISSOR`).

### Documentation

- Documented the phone input fork: any visible phone append bypasses
  `origUpdatePhone` (`PHONE_INPUT_FORKED`).

## [1.1.0] — 2026-08-11

### Added

- Append-only vanilla host API: `append` / `unappend` for `clock`, `map`,
  `phone`, and `radio` (overlays; phone rows after the ten contacts).
- Custom-card `open` + `trigger(gear, reason)` for enter/leave hooks.
- `state(id)` scratch bags and `when.*` visibility helpers.
- Map `helpers.marker` for simple overlay dots.

### Changed

- `register` error text points authors at `append` when they pass a vanilla id.
- `list()` reports both `kind = "card"` and `kind = "append"` rows.

## [1.0.0] — 2026-08-11

### Added

- `register` / `unregister` / `get` / `list` for custom Gen 2 Pokegear cards.
- Shared one-shot patch of `src.ui.gen2.Pokegear`.
