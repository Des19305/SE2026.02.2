extends "res://tests/test_case.gd"
## Tests for creating, reading and reporting run seeds (FR-03, FR-11, AC-SEED-03).

const SeedUtils := preload("res://scripts/generation/seed_utils.gd")
const DungeonGenerator := preload("res://scripts/generation/dungeon_generator.gd")

const CONFIG := {
	"width": 50,
	"height": 50,
	"min_rooms": 8,
	"max_rooms": 12,
	"min_room_size": 5,
	"max_room_size": 10,
}


# --- new_seed ---------------------------------------------------------------

func test_new_seed_is_in_supported_range() -> void:
	for i in 200:
		var seed_value := SeedUtils.new_seed()
		check(SeedUtils.is_valid_seed(seed_value), "seed %d out of range" % seed_value)


func test_new_seed_with_injected_rng_is_reproducible() -> void:
	var a := RandomNumberGenerator.new()
	var b := RandomNumberGenerator.new()
	a.seed = 7
	b.seed = 7
	check_eq(SeedUtils.new_seed(a), SeedUtils.new_seed(b), "same rng state, same seed")


func test_new_seeds_are_not_all_the_same() -> void:
	var seen := {}
	for i in 20:
		seen[SeedUtils.new_seed()] = true
	check(seen.size() > 1, "20 new seeds were all equal")


func test_new_seed_produces_valid_and_repeatable_dungeon() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 2026
	for i in 20:
		var seed_value := SeedUtils.new_seed(rng)
		var first := DungeonGenerator.generate_dungeon(seed_value, CONFIG)
		var second := DungeonGenerator.generate_dungeon(seed_value, CONFIG)
		check(first["ok"], "seed %d: %s" % [seed_value, first.get("error_message", "")])
		check_eq(second["tiles"], first["tiles"], "seed %d tiles" % seed_value)
		check_eq(second["boss_cell"], first["boss_cell"], "seed %d boss_cell" % seed_value)


func test_largest_seed_generates_valid_dungeon() -> void:
	var dungeon := DungeonGenerator.generate_dungeon(SeedUtils.MAX_SEED, CONFIG)
	check(dungeon["ok"], "MAX_SEED: %s" % dungeon.get("error_message", ""))


# --- is_valid_seed ----------------------------------------------------------

func test_is_valid_seed_bounds() -> void:
	check(SeedUtils.is_valid_seed(0), "0 is valid")
	check(SeedUtils.is_valid_seed(SeedUtils.MAX_SEED), "MAX_SEED is valid")
	check(not SeedUtils.is_valid_seed(-1), "-1 is invalid")
	check(not SeedUtils.is_valid_seed(SeedUtils.MAX_SEED + 1), "MAX_SEED + 1 is invalid")


# --- parse_seed -------------------------------------------------------------

func test_parse_accepts_decimal_seeds() -> void:
	var cases := {"12345": 12345, "0": 0, "  42 ": 42, "007": 7, "2147483647": 2147483647}
	for text in cases:
		var result := SeedUtils.parse_seed(text)
		check(result["ok"], "'%s' should be accepted: %s" % [text, result["error"]])
		check_eq(result["seed"], cases[text], "'%s'" % text)
		check_eq(result["error"], "", "'%s' error" % text)


func test_parse_rejects_invalid_text() -> void:
	var cases := {
		"": "Seed is empty",
		"   ": "Seed is empty",
		"-1": "Seed must contain only digits 0-9",
		"+5": "Seed must contain only digits 0-9",
		"12a": "Seed must contain only digits 0-9",
		"1 2": "Seed must contain only digits 0-9",
		"1.5": "Seed must contain only digits 0-9",
		"2147483648": "Seed must be at most 2147483647",
		"99999999999999999999999": "Seed must be at most 2147483647",
	}
	for text in cases:
		var result := SeedUtils.parse_seed(text)
		check(not result["ok"], "'%s' should be rejected" % text)
		check_eq(result["seed"], 0, "'%s' seed" % text)
		check_eq(result["error"], cases[text], "'%s' error" % text)


func test_new_seed_round_trips_through_text() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 99
	for i in 50:
		var seed_value := SeedUtils.new_seed(rng)
		check_eq(SeedUtils.parse_seed(SeedUtils.format_seed(seed_value))["seed"], seed_value, "round trip")


# --- format_seed / seed_report ----------------------------------------------

func test_format_seed_is_plain_decimal() -> void:
	check_eq(SeedUtils.format_seed(0), "0", "0")
	check_eq(SeedUtils.format_seed(2147483647), "2147483647", "max")


func test_seed_report_contains_what_is_needed_to_reproduce() -> void:
	var report := SeedUtils.seed_report(12345, CONFIG)
	check_eq(report,
		"seed=12345 generator_version=%d config={height=50, max_room_size=10, max_rooms=12, min_room_size=5, min_rooms=8, width=50}" % DungeonGenerator.GENERATOR_VERSION,
		"report")


func test_seed_report_does_not_depend_on_key_order() -> void:
	var reordered := {}
	var keys := CONFIG.keys()
	keys.reverse()
	for key in keys:
		reordered[key] = CONFIG[key]
	check_eq(SeedUtils.seed_report(1, reordered), SeedUtils.seed_report(1, CONFIG), "key order")
