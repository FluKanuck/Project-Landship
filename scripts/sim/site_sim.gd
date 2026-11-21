class_name SiteSim
extends RefCounted
## A resource site: a fixed place on the map where a hub can stand. It holds the hub's
## local stockpile (or the aliens' cache once they inhabit it), whatever is lootable there,
## and what the bridge last knew about it.

var id := 0
var name := ""
var pos := Vector2.ZERO
var kind := Logi.SiteKind.MIXED
var richness := 1.0
var owner := Logi.Owner.NONE
var stock := [0.0, 0.0] # [fuel, mat]
var salvage := 0.0 # loose materials: wreckage, the remains of a facility
var discovered := false
var linked := false # a player hub here can report and dispatch
# what the bridge last heard: shown while the site is dark (cut off, or never re-seen)
var known_owner := Logi.Owner.NONE
var known_stock := [0.0, 0.0]
var known_time := -1.0
var known_parts := "" # e.g. "EXT TUR PAD"
var under_attack := 0.0 # seconds since last hit, counts down


func yield_per_s(res: int) -> float:
	return Logi.YIELD[kind][res] * richness / 3600.0


func structures(sim: SimCore, alive_only := true) -> Array[StructureSim]:
	var out: Array[StructureSim] = []
	for s in sim.structures:
		if s.site == id and (not alive_only or not s.dead):
			out.append(s)
	return out


func find(sim: SimCore, kind_: int, online_only := true) -> StructureSim:
	for s in structures(sim):
		if s.kind == kind_ and (s.online() or not online_only):
			return s
	return null


func lootable() -> float:
	return stock[0] + stock[1] + salvage


func label() -> String:
	return "%s %s" % [name, Logi.SITE_KIND_SHORT[kind]]


## Refresh what the bridge knows (called while the site is under linked coverage).
func observe(sim: SimCore) -> void:
	known_owner = owner
	known_stock = stock.duplicate()
	known_time = sim.game_time
	var parts := []
	for s in structures(sim):
		var t: String = Logi.KIND_SHORT[s.kind]
		if not s.online():
			t += "%d%%" % int(s.build * 100.0)
		parts.append(t)
	known_parts = " ".join(parts)
