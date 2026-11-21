# Territory Control & Logistics — design discussion

Status: **open discussion**. Nothing here is decided until it moves to "Decisions".

## What the wedge already has (the ground we build on)

| System | Today | Numbers |
| --- | --- | --- |
| Carrier fuel | One tank, burn by throttle, restart cost grows while parked | 0.86 start; cruise ~26 h / ~570 km, flank ~11 h / ~390 km |
| Drone fuel | Endurance, auto-RTB on bingo, refuel on deck | 60 min endurance, 3 min refuel |
| Fabrication | Rebuilds a lost Swift, free and unlimited | 20 min |
| C4I | Data link bubble around the carrier | 4.3 km good, 5 km max |
| Knowledge | Terrain knowledge permanent, enemy positions only live under coverage | 128² knowledge grid |
| Enemy logistics | Raiders burn hover energy, return to a recharge node | node on a mesa at (2700, -3100) |
| Objective | Find the raiders' base | — |

Observation: the enemy already *has* a logistics loop (energy → node) and the player does not.
That asymmetry is the seed: the raiders' node is a supply point the player can find and deny.

## Framing questions

1. **What does "territory" mean for a single carrier?** Painted map regions (owned/contested),
   or a network of points (depots, relays, wells) whose links define what you hold?
2. **What does the player run out of?** Fuel only, or fuel + munitions + parts/materials
   for fabrication?
3. **Where does supply come from?** Off-map rear (convoys along a line you must keep open),
   on-map resources (wells, wrecks, salvage), or both?
4. **How much is the carrier tied to its territory?** Free raider at sea (CC2) vs. an army
   with a supply line that stretches (Kharak campaign feel)?
5. **Does the enemy contest territory, or only raid it?**
6. **Scale:** one operational area (~10 km) or a theatre map with several?

## Starting proposals (to argue with)

- **Points, not paint.** Territory = a graph of fixed sites (wells, relay masts, depots,
  salvage fields). Holding a site = a deployed asset on it. Lines between held sites form the
  supply net; the display colours the net, not the ground.
- **Relays extend C4I.** A relay mast pushes the 5 km link bubble outward. Territory and the
  existing link mechanic become the same thing: *what you hold is where you can see and order.*
- **Three stocks:** FUEL (carrier + drones), MUNITIONS (when weapons arrive), PARTS
  (fabrication). Fabrication stops being free: a Swift costs parts.
- **Supply moves physically.** Convoys/haulers drive between sites at real speeds through real
  terrain; the enemy can intercept them. Logistics you can watch on the map and lose.
- **The carrier is the forward depot.** Its stores are finite; resupply needs a link to a held
  site or a rendezvous.
- **Enemy mirror.** Raider recharge nodes are their territory. Denying a node strands raiders
  (they already go home when low) — logistics warfare on both sides.

## Research pass (Nov 2026)

| Game | How territory works | How supply reaches the mobile base | Take for Landship |
| --- | --- | --- | --- |
| **Carrier Command 2** | Islands with a command centre; captured by landing virus bots once no enemy is within ~1.5 km. Each island has its own defences and output. | Barges carry stock Island → Warehouse → Carrier. Warehouses shorten delivery and can't be restocked. More barges come from capturing barge-factory islands. | The physical barge is good. The routing rules confuse players: forum threads ask whether island → carrier works without a warehouse. **Keep it to one readable hop: hub → landship.** |
| **Carrier Command: Gaea Mission** | Each captured island is set to *defence*, *resource* or *production*. | Islands only contribute when linked to the stockpile island. Supply subs run the network and a barque brings stock to the carrier. | Giving each site one role is clean. A site must be *connected* to count. |
| **Deserts of Kharak** | Resource fields and wrecks, no ownership. | Salvagers carry resources back to the carrier or a support cruiser. The carrier is the mobile base and builds everything. | Closest to our model: **the landship is the depot and the factory**, and haulers come to it. |
| **Company of Heroes** | Sectors captured at points. | A point only pays out while it is connected to the HQ through owned sectors. Cut-off points stay yours but produce nothing. The "cutoff move" is a core tactic. | Our relay network plays this role: a hub cut off from the link can't be seen, ordered or dispatched. |
| **Foxhole** | Player-built bases. | Players gather, craft and truck everything, later by rail too. The manual hauling burned players out, and a logistics strike pushed the devs to rework it. | **Hauling must not be a chore.** The player sets policy (standing routes, priorities). The drama is interception, not clicking every trip. |
| **HighFleet** | Cities and depots on a strategic map. | Fuel and cash keep the fleet moving. Fuel depots are cheap and intel outposts are separate sites. | Fuel as the strategic leash on the whole fleet. Today's landship tank (~26 h at cruise) is too generous for that. |

Sources: [CC2 Steam discussion (logistics routing)](https://steamcommunity.com/app/1489630/discussions/0/5503948370860958792),
[CC2 basic guide](https://gamepretty.com/carrier-command-2-basic-guide-equipment-layered-attack-method-common-issues-and-blueprints-further-goals/),
[CC2 PvP strategies (capture)](https://www.gamenguides.com/carrier-command-2-pvp-tournament-strategies),
[CC2 store page](https://www.xbox.com/games/store/carrier-command-2/9mvtc1f5f68s),
[Gaea Mission (Wikipedia)](https://en.wikipedia.org/wiki/Carrier_Command:_Gaea_Mission),
[DoK unit list](https://www.gamepressure.com/homeworlddesertsofkharak/list-of-units/z48f42),
[DoK carrier](https://www.gamepressure.com/homeworlddesertsofkharak/carrier/z58f43),
[CoH2 territory](https://www.gamepressure.com/companyofheroes2/territory/ze516b),
[CoH resources](https://companyofheroes.fandom.com/wiki/Resources),
[Foxhole (Wikipedia)](https://en.wikipedia.org/wiki/Foxhole_(video_game)),
[Foxhole logistics strike (PC Gamer)](https://pcgamer.com/logistics-players-in-mmo-wargame-foxhole-go-on-strike),
[HighFleet tips](https://culturedvultures.com/?p=161089).
Mostly community guides; CC2 details may predate later patches.

## Working model (from the 21 Nov discussion)

Territory = **resource hubs**. Their output travels **by air or land to the landship**,
which is the only depot and the only factory.

### Sites (fixed on the map, found by scouting)
- **Resource sites**: where a hub can be built. Kinds TBD (see questions).
- **Any open ground**: relays and scanners can go almost anywhere, with better range on high ground.

### Structures the player can build
| Structure | Does | Notes |
| --- | --- | --- |
| **Light extraction hub** | Extracts into a local stockpile (capped). Basic point defence. Loading pad for lifters and a ramp for haulers. | A full stockpile stops extracting. A hub is a target. |
| **Data link relay** | Extends the C4I bubble (today 5 km around the landship). Relays chain. | If destroyed, everything downstream loses link (the CoH "cutoff"). |
| **Scanner post** | Fixed sensor: live enemy positions under its footprint, and keeps terrain knowledge fresh. | Only reports while linked. Unlinked scanners buffer and burst, like drones today. |

### Transport
| | **Air lifter** | **Land hauler** |
| --- | --- | --- |
| Speed | Fast | Slow, follows the terrain |
| Load | Small | Large |
| Meets the landship | Lands on deck anywhere in range | Needs a rendezvous: the landship stops, or both plot to a meeting point |
| Risk | Raider fire, needs a link | Ambush on the route, can be shadowed back to the landship |
| Orders | Standing route + priority, like a drone waypoint chain | Same |

Rule: **a hub only dispatches while it is linked.** A cut-off hub keeps extracting but sits idle and dark.

### Fit with the wedge
- Relays and scanners reuse the existing link, knowledge and ghost-marker code.
- Lifters and haulers reuse the waypoint and ROE orders.
- Fabrication stops being free, so a Swift costs materials.
- Landship fuel must drop so that resupply matters.
- Raiders gain targets: hubs, haulers in the open and relays (to blind and cut off).

## Round 2 detail (21 Nov)

### Construction: built aboard, planted in the field
- The landship's fabricator builds structures. Small ones (relay, scanner) come out whole.
  A hub comes out as **kits**: extractor, turret, loading pad.
- **Planting:**
  - *Crane rig:* the landship sets a kit down alongside. Fast, but only next to the hull,
    so the landship has to drive to the site.
  - *Engineering vehicle:* carries kits out (one at a time, or with a hauler) and assembles
    them on site. Assembly takes time and the vehicle is exposed while it works.
- A hub goes live in stages: the extractor runs as soon as it's assembled, the turret
  covers it once its kit arrives, and the pad enables dispatch. An undefended hub is a
  deliberate gamble.

### Resources: FUEL and MATERIALS
- **FUEL:** the landship's tank, drone sorties, and vehicle runs. Landship endurance gets
  cut so that resupply matters (target TBD).
- **MATERIALS:** fabrication of drones, vehicles, structure kits, repairs (and munitions later).

### Loading at the landship (no stop needed)
- **Ramp / lowered elevator:** a hauler matches speed and drives aboard. Needs the
  landship at crawl and good ground.
- **Crane grab:** the crane lifts a hauler or its pod off the sand alongside. Works on rough
  ground but is slower per load, and the crane is busy.
- Either way, the hauler unloads into the landship's stores and goes back out on its standing route.

### Raiders vs hubs: destroy, loot, inhabit
1. **Attack:** they hit the turret, then the pad.
2. **Loot:** they take the stockpiled fuel and materials home. The stockpile cap now cuts
   both ways: a full hub is a prize.
3. **Inhabit:** they plant their own facility on the site (a recharge node, or an alien
   extractor). The site turns hostile and has to be cleared and retaken. Their territory
   grows on the same sites ours does.
- **Mirror:** an alien node on a site is something we can strike, loot (?) and reclaim.

### Hub defence
- Basic turrets. They fire at any enemy in range, with no player ROE. Visible to enemy scouting.

## Round 3 detail (21 Nov)

### Engineering = hauler + engineer kit
- One ground chassis. Fitted with a cargo pod it hauls; fitted with an engineer kit it
  carries structure kits and assembles them on site. Refits happen aboard the landship.
- Fewer unit types, and a real trade: a hauler that is building isn't hauling.

### Clearing an alien site
- We take **whatever is lootable** (their stockpile, salvageable materials from the wreck
  of their facility) **and the site itself**, which is then free to build our own hub on.
- Looting is a hauler job: it has to drive in, load and get back to the landship.

### Site placement: think in density, not counts
- The 10 km area is a test box; the final map is much larger. So sites are specified as a
  **density and a spacing rule**, not a fixed number, so the same rules scale.
- Starting proposal to tune in play:
  - Roughly **1 resource site per 8–12 km²**, with a **minimum spacing of 1.5–2 km**
    (enough that a single turret never covers two sites).
  - Site kinds differ (**fuel-rich** vs **materials-rich**, some mixed), so the network
    you build is a choice rather than "take everything near you".
  - Richer sites sit further from the start and nearer alien ground, and are more often
    already inhabited.
  - Relay and scanner value comes from **high ground**, which the terrain generator
    already produces (mesas).
- Balance levers: yield rate, stockpile cap, distance to the landship's likely track, and
  exposure (open flats vs broken ground for haulers).

## Round 4 detail (21 Nov)

### Air lifters stay
- They carry **small, fast loads** (a fuel bladder or materials pod) and **units**: a
  sling-loaded light vehicle, an engineer kit, a relay or scanner.
- That gives air two jobs ground can't do quickly: urgent resupply, and fast placement of
  relays and scanners on high ground haulers can't reach.
- Limits: they need a link, are exposed to raider fire, carry small loads and burn fuel.

### Landship fuel: a slow strategic gauge
- Longer than the 4–6 h proposal. Fuel **should not be a constant concern**.
- Intent: the tank is a slow pressure that only bites when the network is neglected or
  you push far beyond it. Day-to-day, fuel matters through **sorties and vehicle runs**,
  not through the landship's tank.
- Keep the current tank (~26 h cruise) as the baseline and retune once the large map exists.

### Coverage on the large map: relays + landship upgrades
- The landship's base ranges stay modest. Coverage grows through:
  - **Relays** in the field (territory).
  - **Upgradable facilities aboard the landship**, built with materials. Candidates:
    - Comms mast: data link range.
    - Sensor suite: landship sensor range.
    - Hangar: drone and lifter capacity, drone endurance.
    - Fabricator: build speed, kit size.
    - Crane rig / elevator: loading speed, heavier lifts.
- The two routes trade off: relays are cheap and far-reaching but can be cut; upgrades are
  expensive and safe, and travel with you.

## Open questions (round 5)
1. **Units carried by lifters:** which units are in scope beyond Swifts, haulers and lifters
   (e.g. a light armed escort for haulers)?
2. **Upgrade structure:** a short linear tier per facility (I/II/III), or slots where you pick
   what to fit?
3. **Next step:** turn this into a scoped "wedge 2" prototype plan (one hub, one relay, one
   hauler, raider looting) so we can test the loop?

## Decisions

- Territory = resource hubs; output moves by air or land to the landship, which is the single depot and factory.
- Player-built structures: light extraction hub (basic defence + loading facilities), data link relay, scanner post.
- Structures are fabricated aboard the landship (hubs as kits) and planted by crane rig or an engineering vehicle that assembles them on site.
- Two resources: FUEL and MATERIALS.
- Haulers load without the landship stopping: by ramp/lowered elevator or crane grab.
- Raiders destroy, loot and then inhabit hub sites with their own facilities.
- Hub turrets fire automatically at any enemy in range; no player ROE.
- The engineering vehicle is a hauler fitted with an engineer kit.
- Clearing an alien site yields whatever is lootable there, plus the site itself.
- Resource sites are specified by density and spacing (not a fixed count) so the rules scale to the much larger final map; exact numbers come from balancing.
- Air lifters stay: small, fast loads and units.
- Landship fuel is a slow strategic gauge, not a constant concern; keep about today's endurance and tune later.
- Coverage on the large map comes from relays plus upgradable facilities aboard the landship.

## Parked

_(ideas raised and set aside)_
