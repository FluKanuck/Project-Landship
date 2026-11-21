# Systems Prototype — plan

Goal: put the **whole territory and logistics system** into the game, with every loop working
end to end, tuned enough to judge, using rough art. It is not another thin wedge: the test is
whether running a supply network from the bridge is the game, not only whether one moment lands.

Design source: `territory-and-logistics.md`. This plan turns its decisions into builds.

## The loops the prototype must close

1. **Expand:** scout → find a site → fabricate kits → plant (crane rig or engineer hauler or lifter) → hub online.
2. **Supply:** hub extracts → stockpile → hauler/lifter on a standing route → loads aboard at crawl (ramp or crane) → landship stores.
3. **Spend:** stores → fabricate drones, vehicles, kits, repairs → fit or upgrade landship modules.
4. **See and hold:** relays extend the link net, scanners give fixed coverage, cut-off hubs go dark.
5. **Lose and retake:** raiders attack, loot and inhabit hubs → we clear the alien facility, loot it, retake the site.
6. **Enemy economy:** raiders run on their own nodes and sites, so taking those away has an effect.

## Architecture (fits the existing sim-as-data split)

Everything new lives in `scripts/sim/` as data, ticked by `Sim._step`, read by views and panels.

| New | Role |
| --- | --- |
| `site_sim.gd` | A resource site: kind (fuel / materials / mixed), yield, owner (none / us / alien), what is built on it. |
| `site_gen.gd` | Places sites from **density + spacing rules** (not a fixed list), so the same code fills a 10 km test box or the final large map. Seeds from the existing named places (oasis, mine, wrecks, camp). |
| `structure_sim.gd` | Hub parts (extractor, turret, pad), relay, scanner. HP, build progress, stockpile. Alien facilities use the same class with an alien owner. |
| `vehicle_sim.gd` | Hauler and lifter. Shares the waypoint/ROE order model with `DroneSim` (factor the shared part out). Fitted with pod / engineer kit / sling + light weapon. |
| `stores.gd` | Landship FUEL + MATERIALS, capacity from fitted modules. |
| `fitting.gd` | Slots (size S/M/L), modules (size, tier I–III), cost and refit time. Used by the landship and, smaller, by vehicles. |
| `fabricator.gd` | Build queue aboard: drones, vehicles, kits, module tiers. Replaces today's free 20-min Swift rebuild. |
| `link_net.gd` | The data link as a **graph**: landship + relays, each with a radius. Replaces the single 5 km bubble in `_update_links`. Answers "is this point linked?" for drones, vehicles, hubs and scanners. |
| `raider_sim.gd` (extend) | New states: target a hub, attack, loot (carry stock home), inhabit (plant alien facility). Raid planner picks rich, weakly defended or cut-off hubs. |

Changes to existing code:
- `drone_sim.gd`: fuel drawn from stores on refuel; rebuild goes through the fabricator.
- `carrier_sim.gd`: fuel tank becomes part of stores; fitted modules feed sensor range, link range, load speed.
- `sim.gd`: sensors also run for scanners; link goes through `link_net`; new events (hub online, hub under attack, hub lost, convoy hit, load aboard, stores low).
- `terrain.gd`: a `slope_at` / "good ground" query for ramp loading and hauler routes.

## UI on the bridge

- **Tactical / holo map:** site markers (kind, owner), link net drawn as lines between nodes,
  dark (cut-off) hubs greyed, standing routes, convoys. Alien-held sites shown only as
  last known.
- **New display section: LOGISTICS.** Stores (fuel, materials, trend), hubs (stockpile,
  status), routes (vehicle, load, ETA), fabricator queue.
- **New display section: FITTING.** Slot grid by size, fitted modules and tiers, upgrade/refit.
  Also reachable from a bridge terminal (like the settings terminal).
- **Orders:** select hauler/lifter with the same keys and waypoints as drones; new waypoint
  actions LOAD / UNLOAD / BUILD / LOOT; "set as standing route".
- **Callouts:** new crew lines (hub online, hub under attack, convoy hit, load aboard, stores
  low). New Piper voice lines via `tools/audio`.

## Art (rough, Art Profile limits, Blender scripts)

Hub kit (extractor, turret, pad), relay mast, scanner post, hauler (+ pod / kit variants),
lifter, alien facility on a site, landship crane rig and stern ramp sockets. One script per
group in `tools/blender/`, like today.

## Build order (each step playable and testable)

| # | Step | Done when |
| --- | --- | --- |
| 1 | **Stores + fabricator + fitting data.** Fuel and materials, build queue, slots/modules/tiers. Swift rebuild costs materials. | simtest prints stores and builds; fitting changes ranges. |
| 2 | **Sites + site generator.** Density/spacing rules, kinds, shown on the map once scouted. | Sites appear under sensor coverage; regenerate at 10 km and a 40 km test size. |
| 3 | **Link net + relays + scanners.** Graph link, cut-off logic, scanner coverage. Crane-plant only for now. | Placing a relay extends drone range; killing it drops everything downstream. |
| 4 | **Hubs.** Kits, staged build (extractor → turret → pad), extraction, stockpile cap, auto turret. | Hub fills its stockpile; turret engages raiders. |
| 5 | **Vehicles.** Hauler (pod / engineer kit), lifter (pod / sling), shared orders, light weapons, LOAD/UNLOAD/BUILD. | A standing route keeps stores rising without input. |
| 6 | **Loading at the landship.** Ramp at crawl on good ground, crane grab otherwise. | Haulers board with the landship moving. |
| 7 | **Raiders vs the network.** Attack, loot, inhabit; raid planner; alien facilities; clear, loot, retake. | A neglected hub is lost, then retaken. |
| 8 | **Bridge UI + callouts.** LOGISTICS and FITTING sections, map overlays, new voice lines. | Whole loop playable from the chair. |
| 9 | **Art pass + balance pass.** Models, and tuning yields, caps, costs, fuel, raid pressure. | A 2–3 hour session at x16 feels like a campaign, and fuel isn't a constant worry. |

Steps 1–3 can be built and checked headless. Step 8 is where it becomes playable from the bridge.

## Tests

- `simtest` extended: run hours of game time with scripted standing routes and raids; print
  stores, hub states, losses. Add a `--map-size` option to check the site generator scales.
- New director scenarios: `logistics` (build a hub, run a route, raid it) with screenshots.

## Open decisions to settle while building

- Can a smaller module go in a bigger slot? (Proposal: yes.)
- Do vehicles use the slot system too? (Proposal: yes, smaller.)
- Starting slot layout for the landship (proposal: 2 L, 3 M, 3 S) and starting fit.
- Exact costs and yields: set in step 9.
