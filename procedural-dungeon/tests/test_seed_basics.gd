extends RefCounted
# Sanity checks for the assumption the whole project rests on:
# the same seed gives the same random sequence.
# Replace/extend with real generator tests once the generator exists.


func test_same_seed_same_sequence() -> String:
    var a := RandomNumberGenerator.new()
    var b := RandomNumberGenerator.new()
    a.seed = 12345
    b.seed = 12345
    for i in 100:
        var x := a.randi()
        var y := b.randi()
        if x != y:
            return "seed 12345 diverged at draw %d: %d vs %d" % [i, x, y]
    return ""


func test_seed_is_retained() -> String:
    var rng := RandomNumberGenerator.new()
    rng.seed = 987654321
    if rng.seed != 987654321:
        return "expected seed 987654321, got %d" % rng.seed
    return ""