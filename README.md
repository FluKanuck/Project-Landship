# Landship — The Wedge

The first prototype of the landship carrier game: a spiritual successor to Carrier
Command 2 in the tone of Homeworld: Deserts of Kharak. You are the commander of a massive
carrier landship and you fight the war from a single bridge.

The wedge is thick at the bridge and thin everywhere else. The test it has to pass:
**sit in the chair, send the scout out, speed up time, and feel the jolt when a contact
pings on the map.**

Engine: Godot 4.7 (GDScript). Assets: Blender 5.3 via Python (`bpy`). Voices: Piper TTS.

---

## Play

| Build | How |
| --- | --- |
| Windows | `build/windows/Landship-Wedge.exe` |
| Linux | `build/linux/Landship-Wedge.x86_64` |
| Web | `build/web/` — serve the folder with any web server (`python3 -m http.server`), then open `index.html`. Uses the Compatibility renderer: no volumetric dust. |
| Editor | Open `project.godot` in Godot 4.7 and press F5. |

Click once to take command. Headphones help: the crew talks.

### Controls

| Where | Input | Does |
| --- | --- | --- |
| Seated | Mouse | Look around. The display stays fixed in front of the chair. |
| Seated | Hold **ALT** (or press **TAB**) | Cursor: use the display and the chair buttons |
| Seated | **1 2 3 4** | Chair buttons: COMBAT / RECON / TRANSIT layouts, ACTION STATIONS |
| Seated | **5 6** | LOGISTICS / FITTING layouts |
| Display | Drag a section header onto another section | Swap the two sections |
| Tactical / holo | **F1 F2 F3** | Select SWIFT-1 / SWIFT-2 / LANDSHIP |
| Tactical / holo | **F4** | Cycle the haulers and lifters |
| Tactical / holo | Left click | Add a waypoint (uses the ACT and ROE you last picked) |
| Tactical / holo | Right click | Remove the last waypoint |
| Tactical | Mouse wheel | Zoom inside the operational area |
| Drone feed | Mouse wheel | Camera zoom. THERMAL button for the heat view. |
| Anywhere | **,** and **.** | Time compression x1 / x4 / x16 / x64 |
| Anywhere | **E** | Stand up / sit / use the holo table / use the settings terminal |
| Walking | **WASD**, **SHIFT** | Walk, run |
| Holo table | Right drag, wheel | Pan, zoom (it can show the whole theatre) |
| Anywhere | **H** | Help card |

### What is in the wedge

* **The bridge.** Walkable command room with a raised command chair, crew pits with
  faceless helmeted crew who glance about and type, a holo table in the centre, a
  maintenance terminal in the corner for the settings, and a window band over the bow.
* **The projected display.** One large configurable display in front of the chair, opaque
  in the centre and see-through at the edges. Sections snap to halves and quarters,
  presets switch with the chunky chair buttons, and any section can be dragged onto
  another to swap them. Sections: Tactical, Drone feed, Sensors/Contacts, Helm/Time,
  Comms log, Forward camera.
* **Orders.** Carrier Command style waypoint chains. Each waypoint has an action
  (MOVE / LOIT / SCAN) and rules of engagement (FREE / RTRN / FLEE), sticky to the last
  pick. Path segments are coloured by ROE. The carrier takes a plotted course and four
  throttle settings; it stops at the end of its course.
* **Sensors and intel.** The map starts as the coarse pre-war survey and sharpens wherever
  a sensor has looked. Terrain knowledge is permanent; enemy positions are only live
  under coverage. Lost contacts become ghost markers that show their age and fade.
* **C4I.** Drones need a data link (5 km). Beyond it the feed dies, the orders lock, the
  map shows a *predicted* position flown on the last orders, and what the drone saw comes
  back as a data burst when the link returns.
* **The enemy.** Alien light raiders on hover: fast, hit-and-run, energy-limited, so they
  run home to a recharge node to refuel. Unarmed Swifts on FLEE break off when shot at;
  on FREE they hold course and can be lost. Fabrication rebuilds a lost Swift in 20 min.
* **Time compression** up to x64, dropping to x1 with a callout, a ping and a red banner
  on any new contact.
* **Atmosphere.** Low-poly geometry, warm Kharak palette, low sun, volumetric dust and
  sun shafts on desktop, haze, a sandstorm front on the western horizon, radio callouts
  from five crew voices, murmur from the pits, hum and track rumble that follow speed.
* **Objectives.** Find the raiders' base, establish a hub, run a supply load home, destroy
  the recharge node.

### The supply war (systems prototype)

Design: `docs/design/territory-and-logistics.md`, plan: `docs/design/systems-prototype-plan.md`.
Every number lives in `scripts/sim/logi.gd`.

* **Stores.** The landship carries FUEL (her tank, every Swift sortie and every vehicle run)
  and MATERIALS (everything the fabricator builds). Both show in the top strip.
* **Resource sites.** Fixed places (fuel, materials or mixed, with a richness) placed by
  density and spacing rules, so the same code fills a 10 km box or a 100 km theatre.
  They appear as you scout them. Some are already held by the aliens.
* **Hubs.** Fabricate kits aboard, then plant them: with the **crane** beside the hull (the
  landship at crawl or stopped, LANDSHIP selected, CRANE PLANT), with an **engineer
  hauler** (BUILD waypoints, it assembles on site) or by **lifter sling** (drops a kit;
  relays and scanners erect themselves). A hub is an extractor, a turret and a pad. The
  extractor fills a capped local stockpile; the turret fires at anything in range; the pad
  lets haulers and lifters load.
* **Haulers and lifters.** Waypoint chains like the Swifts, with MOVE / LOAD / BUILD /
  LOOT / HOME, coloured by ROE, and a STANDING ROUTE toggle that repeats the chain with no
  further attention. Haulers come aboard without stopping the landship: up the stern ramp
  at crawl on firm ground, or grabbed by the crane at up to cruise. Lifters land on deck.
  Either can be refitted aboard (cargo pod, engineer kit or sling, and a light gun).
* **The link network.** The comms mast plus relays. A relay links when it stands inside a
  linked bubble; high ground gives it more range. Everything beyond a destroyed relay goes
  dark: a dark hub keeps extracting but can't dispatch, and the bridge only sees its last
  report. Scanner posts give fixed sensor coverage and burst what they saw when relinked.
* **Fitting.** Ten slots (3 L, 4 M, 3 S); a module fits its size or bigger. Modules have
  tiers I-III: comms mast, hangar, fabricator, sensor suite, crane rig, stern ramp, stores
  bunker, point defence, baffles, flight control. Swapping a module takes the slot offline.
* **The enemy economy.** Raiders recharge at the node or any outpost they hold. They
  assault hubs (turret first), loot the stockpile, wreck the rest and plant an outpost.
  Replacements cost them stock, which comes from the node and their outposts. Kill the
  node and the outposts and the survivors are stranded. Clear an alien site and you get
  its salvage and the site.

---

## Project layout

```
project.godot
scenes/main.tscn            entry point (everything is built in code)
scripts/
  main.gd                   builds the world, the bridge and the commander; start-up sequence
  sim/                      the war as data: sim.gd (autoload Sim), carrier, drone, raider,
                            logi.gd (every logistics number), stores, fabricator, fitting,
                            site_sim + site_gen, structure_sim, link_net, vehicle_sim
  world/                    terrain.gd (generator + map textures), world_view.gd (visuals)
  bridge/                   bridge.gd, player.gd, projection.gd, holo.gd, settings_ui.gd
  ui/                       the display: mfd.gd, panel_frame.gd, map_view.gd and the panels
                            (tactical, logistics, fitting_panel, feed, contacts, helm, comms)
  audio/sfx.gd              callouts, comms log, subtitles, ambience (autoload Sfx)
  core/                     palette, shared materials, asset loader, settings (autoload Prefs)
  debug/director.gd         scripted test scenarios + screenshots
shaders/                    hull dust, terrain, alien sheen, projection, holo, map, feed, storm
assets/models/*.glb         generated by tools/blender (do not edit by hand)
assets/audio/*.ogg          generated by tools/audio
tools/blender/              kit.py (shared helpers) + one script per asset group
tools/audio/                generate_audio.py
tools/dev/shots.sh          re-import and run a test scenario with screenshots
```

## Rebuild the assets

All 3D assets are Python scripts that follow the Art Profile (see the design doc):

```bash
pip install bpy                        # Blender as a Python module
python3 tools/blender/build_all.py     # every asset; or: build_all.py crew drone
```

Each script prints its triangle count against the Art Profile limit and stops if an
asset is over. Sockets are Empties named `socket_<type>_<n>`; moving parts are separate
objects with the origin on the axis; materials are swapped in Godot by name
(`hull`, `interior`, `alien`, `emit`, `glass`, `screen`, `rock`).

## Rebuild the audio

```bash
pip install piper-tts numpy && apt install sox ffmpeg
# voices: download the .onnx + .onnx.json files from https://huggingface.co/rhasspy/piper-voices
python3 tools/audio/generate_audio.py --voices /path/to/voices
```

## Tests

```bash
godot --headless --path . -- --scenario=simtest     # hours of game time, prints every event
godot --headless --path . -- --scenario=logitest    # 14 h of the supply war: hubs, routes, raids
godot --headless --path . -- --scenario=sitegen     # site rules at 10 / 40 / 100 km (--map-size=)
tools/dev/shots.sh logishots /tmp/shots             # LOGISTICS / FITTING / crane screens
tools/dev/shots.sh logilook /tmp/shots              # exterior: hub, hauler, lifter, relay, outpost
tools/dev/shots.sh quick /tmp/shots                 # screenshots (needs xvfb)
tools/dev/shots.sh interact /tmp/shots              # drives the display with mouse events
```

## Credits

* Fonts: Share Tech Mono and Oxanium, SIL Open Font License (`assets/fonts/`).
* Voices: Piper TTS voices (alan, jenny_dioco, northern_english_male, cori, ryan, amy),
  see each voice's model card on Hugging Face for its licence before shipping.
* Everything else in this repository was generated for this project.
