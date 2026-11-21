class_name Fitting
extends RefCounted
## Slots with a size limit; modules with tiers. A module fits any slot of its size or
## larger. While a slot is being refitted its module is offline. The landship's numbers
## (link range, sensor range, hangar size, crane, ramp, stores...) all come from here.

var slots: Array[Dictionary] = [] # {size, module: String, tier: int, refit: float, next: String, next_tier: int}


func _init(layout: Array, start := {}) -> void:
	for s in layout:
		slots.append({"size": s, "module": "", "tier": 0, "refit": 0.0, "next": "", "next_tier": 0})
	for i in start:
		slots[i].module = start[i][0]
		slots[i].tier = start[i][1]


func step(dt: float, sim: SimCore) -> void:
	for i in slots.size():
		var s := slots[i]
		if s.refit > 0.0:
			s.refit = maxf(0.0, s.refit - dt)
			if s.refit <= 0.0:
				s.module = s.next
				s.tier = s.next_tier
				s.next = ""
				sim.emit_event("refit_done", {"slot": i, "module": s.module, "tier": s.tier})


func has(module: String) -> bool:
	return tier_of(module) >= 0


## Tier (0-based) of the online module with this id, or -1.
func tier_of(module: String) -> int:
	var best := -1
	for s in slots:
		if s.module == module and s.refit <= 0.0:
			best = maxi(best, s.tier)
	return best


func stat(name: String) -> Variant:
	for id in Logi.MODULES:
		var m: Dictionary = Logi.MODULES[id]
		if m.stat == name:
			var t := tier_of(id)
			if t >= 0:
				return m.tiers[t]
	return Logi.STAT_DEFAULT[name]


func can_fit(slot: int, module: String) -> bool:
	if slot < 0 or slot >= slots.size():
		return false
	if module == "":
		return true
	return Logi.fits(Logi.MODULES[module].size, slots[slot].size)


## Begin swapping a slot to `module` at `tier` ("" empties it). Offline for REFIT_TIME.
func begin_refit(slot: int, module: String, tier := 0) -> bool:
	if not can_fit(slot, module):
		return false
	var s := slots[slot]
	s.next = module
	s.next_tier = tier
	s.refit = Logi.REFIT_TIME
	return true


## Raise the tier of whatever is fitted (no downtime: upgrades are done in place).
func set_tier(slot: int, tier: int) -> void:
	slots[slot].tier = clampi(tier, 0, 2)


func slot_text(i: int) -> String:
	var s := slots[i]
	if s.refit > 0.0:
		return "REFIT %s %d:%02d" % [Logi.MODULES[s.next].name if s.next != "" else "EMPTY", int(s.refit) / 60, int(s.refit) % 60]
	if s.module == "":
		return "EMPTY"
	return "%s %s" % [Logi.MODULES[s.module].name, Logi.tier_name(s.tier)]


func describe() -> String:
	var out := []
	for i in slots.size():
		out.append("%s:%s" % [Logi.SIZE_NAMES[slots[i].size], slot_text(i)])
	return " ".join(out)
