class_name Logi
## The logistics catalogue: every number the supply war runs on, in one place so the
## balance pass has one file to tune. Data only — the systems that use it live in
## stores.gd, fitting.gd, fabricator.gd, site_sim.gd, structure_sim.gd and vehicle_sim.gd.
##
## Units: FUEL and MATERIALS are both counted in "units" (u). The landship's tank holds
## 1000 u; at cruise she burns about 32 u an hour.

enum Res { FUEL, MAT }
const RES_NAMES := ["FUEL", "MAT"]

# ------------------------------------------------------------------ landship stores
const TANK_BASE := 1000.0 # fuel the landship can hold with no stores module
const MAT_BASE := 300.0 # materials hold with no stores module
const START_FUEL := 860.0
const START_MAT := 220.0
const DRONE_FUEL_PER_HOUR := 6.0 # fuel drawn from stores to refill a Swift after an hour aloft

# ------------------------------------------------------------------ fitting
enum Size { S, M, L }
const SIZE_NAMES := ["S", "M", "L"]
## Landship slot layout. A module fits any slot of its size or larger.
const LANDSHIP_SLOTS := [Size.L, Size.L, Size.L, Size.M, Size.M, Size.M, Size.M, Size.S, Size.S, Size.S]

## Module catalogue. `tiers` holds the value of `stat` at tier I, II, III; `cost` the
## materials for each tier (tier I = fabricate the module, II/III = upgrade).
const MODULES := {
	"comms": {"name": "COMMS MAST", "size": Size.L, "stat": "link_range", "tiers": [5000.0, 6500.0, 8000.0],
		"cost": [60, 120, 200], "time": [300, 600, 900], "desc": "Data link range around the landship"},
	"hangar": {"name": "HANGAR", "size": Size.L, "stat": "air_capacity", "tiers": [3, 4, 5],
		"cost": [60, 110, 180], "time": [300, 600, 900], "desc": "Aircraft carried (Swifts + lifters); faster refuel"},
	"fabricator": {"name": "FABRICATOR", "size": Size.L, "stat": "fab_speed", "tiers": [1.0, 1.5, 2.2],
		"cost": [80, 140, 220], "time": [300, 600, 900], "desc": "Build speed for everything made aboard"},
	"sensors": {"name": "SENSOR SUITE", "size": Size.M, "stat": "sensor_range", "tiers": [2600.0, 3200.0, 3800.0],
		"cost": [50, 100, 160], "time": [240, 480, 720], "desc": "Landship sensor radius"},
	"crane": {"name": "CRANE RIG", "size": Size.M, "stat": "crane_time", "tiers": [90.0, 60.0, 40.0],
		"cost": [40, 80, 130], "time": [240, 480, 720], "desc": "Grab haulers alongside; plant kits beside the hull"},
	"ramp": {"name": "STERN RAMP", "size": Size.M, "stat": "ramp_time", "tiers": [40.0, 30.0, 20.0],
		"cost": [40, 80, 130], "time": [240, 480, 720], "desc": "Haulers drive aboard at crawl; vehicle bay size"},
	"stores": {"name": "STORES BUNKER", "size": Size.M, "stat": "stores_bonus", "tiers": [300.0, 600.0, 1000.0],
		"cost": [40, 90, 150], "time": [240, 480, 720], "desc": "More materials hold and fuel bunkerage"},
	"pd": {"name": "POINT DEFENCE", "size": Size.S, "stat": "pd_range", "tiers": [900.0, 1100.0, 1300.0],
		"cost": [30, 60, 100], "time": [180, 360, 540], "desc": "Guns on the hull: raiders and alien structures in range"},
	"baffles": {"name": "BAFFLES", "size": Size.S, "stat": "signature_mult", "tiers": [0.85, 0.75, 0.65],
		"cost": [30, 60, 100], "time": [180, 360, 540], "desc": "Quieter drive: raids find her less often"},
	"flightctl": {"name": "FLIGHT CONTROL", "size": Size.S, "stat": "endurance_mult", "tiers": [1.15, 1.3, 1.45],
		"cost": [30, 60, 100], "time": [180, 360, 540], "desc": "Longer Swift and lifter endurance"},
}
## What she leaves port with: slot index -> [module, tier (0-based)]
const START_FIT := {0: ["comms", 0], 1: ["hangar", 0], 2: ["fabricator", 0], 3: ["sensors", 0],
	4: ["crane", 0], 5: ["ramp", 0], 7: ["pd", 0]}
## Value of a stat when no module provides it.
const STAT_DEFAULT := {"link_range": 3000.0, "air_capacity": 2, "fab_speed": 0.5, "sensor_range": 1800.0,
	"crane_time": 0.0, "ramp_time": 0.0, "stores_bonus": 0.0, "pd_range": 0.0, "signature_mult": 1.0,
	"endurance_mult": 1.0}
const REFIT_TIME := 120.0 # seconds to swap a module in or out of a slot
const REMOVE_REFUND := 0.5

# ------------------------------------------------------------------ vehicles
enum Veh { HAULER, LIFTER }
const VEH_NAMES := ["HAULER", "LIFTER"]
## Utility fits. A hauler takes POD or ENGINEER, a lifter POD or SLING.
const UTILITY := {
	"pod": {"name": "CARGO POD", "for": [Veh.HAULER, Veh.LIFTER]},
	"engineer": {"name": "ENGINEER KIT", "for": [Veh.HAULER]},
	"sling": {"name": "SLING", "for": [Veh.LIFTER]},
}
const GUN_COST := 10
const VEH_REFIT_TIME := 60.0
const VEHICLE := {
	Veh.HAULER: {"speed": 9.0, "rough_speed": 4.0, "cargo": 60.0, "kits": 2, "hp": 8, "fuel_per_km": 0.25, "sensor": 900.0},
	Veh.LIFTER: {"speed": 34.0, "cargo": 15.0, "kits": 1, "hp": 3, "fuel_per_km": 0.18, "sensor": 1100.0,
		"alt": 160.0, "endurance": 5400.0},
}
const LOAD_RATE := 1.0 # u per second through a hub pad
const ASSEMBLE_TIME := 240.0 # engineer: seconds per kit
const GUN_RANGE := 650.0
const GUN_CD := 2.2
const GUN_HIT := 0.25

# ------------------------------------------------------------------ structures
enum Kind { EXTRACTOR, TURRET, PAD, RELAY, SCANNER, ALIEN_NODE, ALIEN_OUTPOST }
const KIND_NAMES := ["EXTRACTOR", "TURRET", "PAD", "RELAY", "SCANNER", "RECHARGE NODE", "ALIEN OUTPOST"]
const KIND_SHORT := ["EXT", "TUR", "PAD", "RLY", "SCN", "NODE", "OUTPOST"]
const STRUCT := {
	Kind.EXTRACTOR: {"hp": 12, "self_erect": false, "on_site": true},
	Kind.TURRET: {"hp": 10, "self_erect": false, "on_site": true, "range": 950.0, "cd": 2.0, "hit": 0.35},
	Kind.PAD: {"hp": 8, "self_erect": false, "on_site": true},
	Kind.RELAY: {"hp": 5, "self_erect": true, "erect_time": 60.0, "range": 3500.0},
	Kind.SCANNER: {"hp": 5, "self_erect": true, "erect_time": 90.0, "sensor": 2000.0},
	Kind.ALIEN_NODE: {"hp": 40},
	Kind.ALIEN_OUTPOST: {"hp": 16, "build_time": 900.0},
}
## High ground: relays and scanners gain this fraction of range per 10 m above the
## average ground around them (capped).
const HIGH_GROUND_PER_10M := 0.04
const HIGH_GROUND_CAP := 0.4

# ------------------------------------------------------------------ fabricator catalogue
## kind -> {name, cost (materials), time (seconds at fab speed 1)}
const FAB := {
	"swift": {"name": "SWIFT", "cost": 40, "time": 1200.0},
	"hauler": {"name": "HAULER", "cost": 35, "time": 900.0},
	"lifter": {"name": "LIFTER", "cost": 45, "time": 900.0},
	"kit_extractor": {"name": "EXTRACTOR KIT", "cost": 30, "time": 420.0, "kind": Kind.EXTRACTOR},
	"kit_turret": {"name": "TURRET KIT", "cost": 25, "time": 360.0, "kind": Kind.TURRET},
	"kit_pad": {"name": "PAD KIT", "cost": 15, "time": 240.0, "kind": Kind.PAD},
	"kit_relay": {"name": "RELAY", "cost": 20, "time": 300.0, "kind": Kind.RELAY},
	"kit_scanner": {"name": "SCANNER", "cost": 25, "time": 360.0, "kind": Kind.SCANNER},
}
const FAB_ORDER := ["kit_extractor", "kit_turret", "kit_pad", "kit_relay", "kit_scanner", "hauler", "lifter", "swift"]
const REPAIR_RATE := 0.02 # hp per second aboard, per materials unit spent

# ------------------------------------------------------------------ sites
enum SiteKind { FUEL, MAT, MIXED }
const SITE_KIND_NAMES := ["FUEL", "MAT", "MIXED"]
const SITE_KIND_SHORT := ["F", "M", "FM"]
enum Owner { NONE, PLAYER, ALIEN }
const SITE_RADIUS := 260.0 # hub structures must stand this close to the site centre
const STOCK_CAP := 120.0 # per resource, in the hub's local stockpile
## Extraction per game hour at richness 1.0: [fuel, mat] by site kind.
const YIELD := {SiteKind.FUEL: [30.0, 0.0], SiteKind.MAT: [0.0, 22.0], SiteKind.MIXED: [16.0, 12.0]}
## Site generator: one site per this many km², and never closer than MIN_SPACING.
const SITE_KM2 := 10.0
const SITE_MIN_SPACING := 1600.0
const SALVAGE_FACILITY := 40.0 # materials salvaged from a destroyed alien facility

# ------------------------------------------------------------------ the enemy economy
const ALIEN_START_STOCK := 200.0
const NODE_YIELD := 10.0 # alien stock per game hour from the recharge node itself
const RAIDER_COST := 30.0 # alien stock to field a replacement raider
const RAIDER_RESPAWN := 1200.0 # seconds between replacement raiders from a node
const OUTPOST_YIELD := 8.0 # alien stock per game hour from an outpost
const RAIDER_CARRY := 20.0 # loot one raider can carry home, per resource
const RAIDER_HP := 4


static func module_value(id: String, tier: int) -> Variant:
	return MODULES[id].tiers[clampi(tier, 0, 2)]


static func fits(module_size: int, slot_size: int) -> bool:
	return module_size <= slot_size


static func tier_name(t: int) -> String:
	return ["I", "II", "III"][clampi(t, 0, 2)]
