class_name SiteGen
## Places resource sites from rules, not a list: one site per SITE_KM2, never closer than
## SITE_MIN_SPACING, richer the further they are from the start and the nearer to alien
## ground, and more often already inhabited out there. The same rules fill the 10 km test
## box or a theatre many times its size.

const NAMES := ["ANVIL", "BRASS", "CINDER", "DROSS", "EMBER", "FLINT", "GYPSUM", "HALITE", "IRONSTONE",
	"JASPER", "KILN", "LODE", "MARL", "NITRE", "OCHRE", "PUMICE", "QUARTZ", "RUST", "SHALE", "TALC",
	"UMBER", "VITRIOL", "WADI", "XERIC", "YARDANG", "ZINC"]


## `half`: half the map size in metres. `valid`: Callable(Vector2) -> bool for buildable
## ground. `seeds`: [{pos, kind, name, owner?, salvage?, richness?}] placed first.
## Returns [{pos, kind, name, richness, owner, salvage}].
static func generate(half: float, start: Vector2, alien_core: Vector2, seeds: Array, valid: Callable, seed_ := 11) -> Array:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_
	var out: Array = []
	for s in seeds:
		var d: Dictionary = s.duplicate()
		if not d.has("richness"):
			d.richness = _richness(d.pos, start, alien_core, half)
		d.owner = d.get("owner", Logi.Owner.NONE)
		d.salvage = d.get("salvage", 0.0)
		out.append(d)
	var area_km2 := (half * 2.0 / 1000.0) * (half * 2.0 / 1000.0)
	var target := int(round(area_km2 / Logi.SITE_KM2))
	var tries := 0
	var margin := minf(600.0, half * 0.12)
	var name_i := 0
	while out.size() < target and tries < target * 80:
		tries += 1
		var p := Vector2(rng.randf_range(-half + margin, half - margin), rng.randf_range(-half + margin, half - margin))
		if p.distance_to(start) < 1200.0:
			continue
		var ok := true
		for o in out:
			if p.distance_to(o.pos) < Logi.SITE_MIN_SPACING:
				ok = false
				break
		if not ok or not valid.call(p):
			continue
		var t := _far(p, start, half)
		var roll := rng.randf()
		var kind: int
		if t < 0.35:
			kind = Logi.SiteKind.FUEL if roll < 0.42 else (Logi.SiteKind.MAT if roll < 0.84 else Logi.SiteKind.MIXED)
		else:
			kind = Logi.SiteKind.FUEL if roll < 0.33 else (Logi.SiteKind.MAT if roll < 0.66 else Logi.SiteKind.MIXED)
		var near_alien := 1.0 - clampf(p.distance_to(alien_core) / (half * 0.9), 0.0, 1.0)
		var owner := Logi.Owner.NONE
		if rng.randf() < clampf(near_alien * 0.7 + t * 0.25 - 0.25, 0.0, 0.6):
			owner = Logi.Owner.ALIEN
		var nm: String = NAMES[name_i % NAMES.size()]
		if name_i >= NAMES.size():
			nm += "-%d" % (name_i / NAMES.size() + 1)
		name_i += 1
		out.append({"pos": p, "kind": kind, "name": nm, "richness": _richness(p, start, alien_core, half) * rng.randf_range(0.85, 1.15),
			"owner": owner, "salvage": 0.0})
	return out


static func _far(p: Vector2, start: Vector2, half: float) -> float:
	return clampf(p.distance_to(start) / (half * 1.6), 0.0, 1.0)


static func _richness(p: Vector2, start: Vector2, alien_core: Vector2, half: float) -> float:
	var near_alien := 1.0 - clampf(p.distance_to(alien_core) / (half * 0.9), 0.0, 1.0)
	return 0.75 + _far(p, start, half) * 0.6 + near_alien * 0.35
