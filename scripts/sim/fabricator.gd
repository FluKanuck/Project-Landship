class_name Fabricator
extends RefCounted
## The build queue aboard the landship. Only the head of the queue is worked on. It pays
## its materials when work starts; with too little in the hold it waits, and the queue
## waits behind it. Speed comes from the fabricator module (a hull without one still
## builds, at half speed).

var queue: Array[Dictionary] = [] # {uid, kind, name, cost, total, progress, paid, data}
var built := 0
var _uid := 0


func add(kind: String, data := {}) -> Dictionary:
	var item := {"uid": _uid, "kind": kind, "progress": 0.0, "paid": false, "data": data}
	_uid += 1
	if kind == "module":
		var m: Dictionary = Logi.MODULES[data.module]
		item.name = "%s %s" % [m.name, Logi.tier_name(data.tier)]
		item.cost = float(m.cost[data.tier])
		item.total = float(m.time[data.tier])
	else:
		var f: Dictionary = Logi.FAB[kind]
		item.name = f.name
		item.cost = float(f.cost)
		item.total = float(f.time)
	queue.append(item)
	return item


func cancel(uid: int, stores: Stores) -> bool:
	for i in queue.size():
		if queue[i].uid == uid:
			if queue[i].paid:
				stores.put(Logi.Res.MAT, queue[i].cost)
				stores.delivered[Logi.Res.MAT] -= queue[i].cost
			queue.remove_at(i)
			return true
	return false


## Put an item at the front (used for urgent work such as a replacement Swift).
func promote(uid: int) -> void:
	for i in queue.size():
		if queue[i].uid == uid and i > 0:
			var it: Dictionary = queue[i]
			queue.remove_at(i)
			# never jump ahead of work that is already paid for and running
			var at := 1 if queue[0].paid else 0
			queue.insert(at, it)
			return


func head() -> Dictionary:
	return queue[0] if not queue.is_empty() else {}


func waiting_for_mat() -> bool:
	return not queue.is_empty() and not queue[0].paid


func count(kind: String) -> int:
	var n := 0
	for it in queue:
		if it.kind == kind:
			n += 1
	return n


func eta(uid: int, speed: float) -> float:
	var t := 0.0
	for it in queue:
		t += (it.total - it.progress) / maxf(speed, 0.01)
		if it.uid == uid:
			return t
	return -1.0


func step(dt: float, sim: SimCore) -> void:
	if queue.is_empty():
		return
	var it: Dictionary = queue[0]
	if not it.paid:
		if not sim.stores.has(Logi.Res.MAT, it.cost):
			if not it.get("warned", false):
				it.warned = true
				sim.emit_event("fab_waiting", {"name": it.name, "cost": it.cost})
			return
		sim.stores.take(Logi.Res.MAT, it.cost)
		it.paid = true
		sim.emit_event("fab_start", {"name": it.name})
	var speed: float = sim.fitting.stat("fab_speed")
	it.progress += dt * speed
	if it.progress >= it.total:
		queue.remove_at(0)
		built += 1
		sim.fab_done(it)
