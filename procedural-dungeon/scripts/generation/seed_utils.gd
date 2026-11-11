extends RefCounted
## Creating, reading and reporting run seeds. Pure functions, no nodes or I/O.
##
## A seed is an int in 0..MAX_SEED, so it can be shown on the HUD, typed back
## by a player and pasted into a bug report as plain decimal digits.
## new_seed() is the only place where unseeded randomness is allowed: it picks
## the seed before generation starts; the seed is then stored with the run and
## everything after it is deterministic (architecture.md §5.4, §6.1).

const DungeonGenerator := preload("res://scripts/generation/dungeon_generator.gd")

## Largest seed (2^31 - 1): at most 10 digits, and seed + attempt * stride in
## the generator stays far from the 64-bit int limit.
const MAX_SEED := 2_147_483_647
const ERR_EMPTY := "Seed is empty"
const ERR_NOT_DIGITS := "Seed must contain only digits 0-9"
const ERR_TOO_LARGE := "Seed must be at most %d" % MAX_SEED


## Returns a new random seed for a run. Pass an rng to get a reproducible
## sequence (tests); without one, the rng is randomized from the clock.
static func new_seed(rng: RandomNumberGenerator = null) -> int:
	if rng == null:
		rng = RandomNumberGenerator.new()
		rng.randomize()
	return rng.randi_range(0, MAX_SEED)


static func is_valid_seed(seed_value: int) -> bool:
	return seed_value >= 0 and seed_value <= MAX_SEED


## Reads a seed typed by a player. Surrounding spaces and leading zeros are
## ignored. Returns {"ok": bool, "seed": int, "error": String}; seed is 0 when
## ok is false.
static func parse_seed(text: String) -> Dictionary:
	var digits := text.strip_edges()
	if digits.is_empty():
		return _parse_error(ERR_EMPTY)
	for c in digits:
		if c < "0" or c > "9":
			return _parse_error(ERR_NOT_DIGITS)
	digits = digits.lstrip("0")
	if digits.is_empty():
		return {"ok": true, "seed": 0, "error": ""}
	# Check the length first: to_int() would overflow on very long input.
	if digits.length() > str(MAX_SEED).length() or digits.to_int() > MAX_SEED:
		return _parse_error(ERR_TOO_LARGE)
	return {"ok": true, "seed": digits.to_int(), "error": ""}


## Text shown to the player (HUD, end screen). parse_seed() reads it back.
static func format_seed(seed_value: int) -> String:
	return str(seed_value)


## One line with everything needed to regenerate a dungeon, for logs and bug
## reports (AC-SEED-03). Config keys are sorted so the line does not depend on
## dictionary order.
static func seed_report(seed_value: int, config: Dictionary) -> String:
	var keys := config.keys()
	keys.sort()
	var parts: Array[String] = []
	for key in keys:
		parts.append("%s=%s" % [key, config[key]])
	return "seed=%s generator_version=%d config={%s}" % [
		format_seed(seed_value), DungeonGenerator.GENERATOR_VERSION, ", ".join(parts)]


static func _parse_error(message: String) -> Dictionary:
	return {"ok": false, "seed": 0, "error": message}
