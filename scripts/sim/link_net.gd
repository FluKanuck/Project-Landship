class_name LinkNet
extends RefCounted
## The data link as a network: the landship's comms mast plus every relay that can hear a
## linked node. A relay is linked when it stands inside the bubble of a node that is
## already linked; everything beyond a destroyed relay goes dark with it.

const WEAK_MARGIN := 700.0 # the last 700 m inside a bubble is a weak signal

var nodes: Array[Dictionary] = [] # {pos, range, src (StructureSim or null for the landship)}
var edges: Array = [] # [Vector2, Vector2] parent -> child, for the maps
var dark_relays: Array[StructureSim] = []


func rebuild(sim: SimCore) -> void:
	nodes.clear()
	edges.clear()
	dark_relays.clear()
	nodes.append({"pos": sim.carrier.pos2(), "range": float(sim.fitting.stat("link_range")), "src": null})
	var pending: Array[StructureSim] = []
	for s in sim.structures:
		if s.kind == Logi.Kind.RELAY and s.owner == Logi.Owner.PLAYER and s.online():
			pending.append(s)
		s.linked = false
	var grew := true
	while grew and not pending.is_empty():
		grew = false
		for s in pending.duplicate():
			for n in nodes:
				if s.pos.distance_to(n.pos) <= n.range:
					nodes.append({"pos": s.pos, "range": s.link_range(), "src": s})
					edges.append([n.pos, s.pos])
					s.linked = true
					pending.erase(s)
					grew = true
					break
	dark_relays = pending
	for s in sim.structures:
		if s.kind != Logi.Kind.RELAY and not s.is_alien():
			s.linked = covers(s.pos)


## How far inside the network a point is (negative: outside, in metres).
func margin(p: Vector2) -> float:
	var best := -INF
	for n in nodes:
		best = maxf(best, n.range - p.distance_to(n.pos))
	return best


func covers(p: Vector2) -> bool:
	return margin(p) > 0.0
