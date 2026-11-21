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

## Decisions

_(none yet)_

## Parked

_(ideas raised and set aside)_
