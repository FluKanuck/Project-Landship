class_name Stores
extends RefCounted
## The landship's holds: FUEL (her own tank, and what every sortie and vehicle run draws
## on) and MATERIALS (what the fabricator builds from). Capacity comes from the fit.

var fuel := Logi.START_FUEL
var mat := Logi.START_MAT
var fitting: Fitting
## Running totals for the logistics display and the soak test.
var delivered := [0.0, 0.0]
var spent := [0.0, 0.0]
var _trend := [0.0, 0.0] # smoothed u per hour
var _last := [0.0, 0.0]
var _trend_t := 0.0


func _init(f: Fitting) -> void:
	fitting = f
	_last = [fuel, mat]


func cap(res: int) -> float:
	var bonus: float = fitting.stat("stores_bonus")
	if res == Logi.Res.FUEL:
		return Logi.TANK_BASE + bonus * 0.7
	return Logi.MAT_BASE + bonus


func amount(res: int) -> float:
	return fuel if res == Logi.Res.FUEL else mat


func frac(res: int) -> float:
	return amount(res) / cap(res)


func has(res: int, n: float) -> bool:
	return amount(res) >= n - 0.001


## Take up to `n`; returns what was actually taken.
func take(res: int, n: float) -> float:
	var got := minf(n, amount(res))
	if res == Logi.Res.FUEL:
		fuel -= got
	else:
		mat -= got
	spent[res] += got
	return got


## Put in up to `n`; returns what fitted.
func put(res: int, n: float) -> float:
	var room := maxf(0.0, cap(res) - amount(res))
	var got := minf(n, room)
	if res == Logi.Res.FUEL:
		fuel += got
	else:
		mat += got
	delivered[res] += got
	return got


func step(dt: float) -> void:
	_trend_t += dt
	if _trend_t >= 300.0:
		for r in 2:
			var per_h: float = (amount(r) - _last[r]) / _trend_t * 3600.0
			_trend[r] = lerpf(_trend[r], per_h, 0.5)
			_last[r] = amount(r)
		_trend_t = 0.0


func trend(res: int) -> float:
	return _trend[res]
