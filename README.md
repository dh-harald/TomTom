![GitHub Release](https://img.shields.io/github/v/release/dh-harald/TomTom) ![GitHub Actions Workflow Status](https://img.shields.io/github/actions/workflow/status/dh-harald/TomTom/package.yaml) ![GitHub Downloads (all assets, all releases)](https://img.shields.io/github/downloads/dh-harald/TomTom/total)
# TomTom (Ace3v)

Your personal navigation assistant for World of Warcraft 1.12.1: set a waypoint, and a floating
"crazy-taxi" arrow points you at it while pins mark it on the minimap and the world map.

This is a **vanilla 1.12.1 addon**. Its base is the community **TomTomVanilla** port of Cladhaire's
TomTom, rebuilt here on [Ace3v](https://github.com/laytya/Ace3v) with a new map layer written from
scratch. The current retail TomTom is a relative, not an ancestor: no code from it is involved here,
and this is not a backport of it. See [What was rewritten](#what-was-rewritten).

## Requirements

- WoW **1.12.1** (`## Interface: 11200`), Lua 5.0.
- No other addons required. Everything it needs is bundled in `Libs/`.

Developed and tested against **Unreal Azeroth**, a from-scratch reimplementation of the 1.12.1
client. The code is written to Lua 5.0 and detects client capabilities rather than clients, so it
is intended to work on any 1.12.1 server — but only Unreal Azeroth has actually been tested.

## Installation

Extract so that the addon lands at:

```
Interface/AddOns/TomTom/TomTom.toc
```

**The folder must be named exactly `TomTom`.** The artwork is loaded from hardcoded paths under
`Interface\AddOns\TomTom\Images\`, so a folder called `TomTom-2.0` or `TomTom-master` loads without
error and then shows no arrow and no pins. Rename it if your unzip tool added a suffix.

Settings live in `TomTomDB` (`SavedVariables`), per character profile.

## Usage

### Slash commands

`/way` has two aliases, `/tway` and `/tomtomway`, for when another addon has claimed `/way`.

| Command | Effect |
|---|---|
| `/way 45.4 28.1` | Waypoint at those coordinates in your current zone |
| `/way 45.4 28.1 Herb patch` | ...with a description |
| `/way Durotar 20 20` | Waypoint in a named zone, wherever you are |
| `/way Elwynn Forest 34.2 50.7 Party!` | Multi-word zone names work; the coordinates end the name |
| `/way list` | List the waypoints in your current zone |
| `/way list all` | List every waypoint |
| `/way list Durotar` | List the waypoints in a named zone |
| `/way reset` | Remove the waypoints in your current zone |
| `/way reset all` | Remove every waypoint (asks first, unless you turn that off) |
| `/way reset Durotar` | Remove the waypoints in a named zone |
| `/wayb`, `/wayback` | Waypoint where you are standing right now, titled "Wayback" |
| `/cway`, `/closestway` | Point the arrow at the closest waypoint |
| `/tomtom` | Open the options window |

Coordinates are percentages of the zone, `0`–`100`, the same numbers the world map shows.
`45,4` works as well as `45.4` — whichever decimal separator your client uses. `reset` also answers
to `remove`, `clear`, `clean`, `del` and `delete`.

Zone names are matched loosely: case and punctuation are ignored, so `elwynnforest`, `Elwynn Forest`
and `ELWYNN FOREST` are the same zone. Localized zone names work on a non-English client when
`LibBabble-Zone-2.2` is present, which it is by default.

### The world map

Hold **Ctrl** and **right-click** the world map to drop a waypoint there. The modifier is
configurable — Shift, Ctrl, Alt, or any combination of them.

### Pins

Waypoints appear on the minimap and on the world map, and a minimap pin turns into an arrow at the
edge of the minimap when its target is out of range. Hovering a pin shows the zone, the coordinates
and the live distance.

**Right-click a pin** for a menu: point the arrow at it, remove it, remove everything in that zone,
remove everything, or toggle whether it survives a logout.

### The crazy arrow

The arrow points at the active waypoint and shows the distance in yards plus an estimated time of
arrival based on how fast you are actually closing on it. It turns into a downward icon when you
arrive, and can play a sound at that moment.

Unlock it in the options to drag it somewhere else, then lock it again. Its position is saved
against whichever screen edge or corner it ends up nearest, so it stays where you put it across a
resolution or window-size change.

## Options

`/tomtom` opens the options window:

| Group | Contains |
|---|---|
| **General** | Chat announcements, the confirm-before-removing-all prompt, corpse waypoints |
| **Crazy Arrow** | Show/hide, lock, arrival distance, arrival sound, right-click menu, reset position |
| **Saving** | Whether new waypoints survive a logout, and the distance at which a waypoint clears itself |
| **World Map** | Pins on/off, tooltip, right-click menu, the create-waypoint modifier |
| **Minimap** | Pins on/off, tooltip, right-click menu |
| **Profiles** | Create, switch, copy, reset and delete saved profiles |

## What was rewritten

The starting point was the Ace2-based **TomTomVanilla** port. It worked, but not on Unreal Azeroth,
and the reason was structural rather than cosmetic.

**`Astrolabe-0.2` is gone**, replaced by two new libraries written for this project and shipped
standalone as well: **`LibHereBeDragons-1.0`** and **`LibHereBeDragons-Pins-1.0`**, following the API
of Nevcairiel's HereBeDragons. Retail TomTom left Astrolabe for HereBeDragons too, for its own
reasons and with its own code; the reason here is that Astrolabe walks the entire world map at load,
one `SetMapZoom` per zone, and builds its zone table from what it sees. On Unreal Azeroth `GetMapZones(continent)` ignores its argument and
answers for whichever continent happens to be selected, so that table came out wrong: zone
dimensions were zeroed or assigned to the wrong zone, which meant wrong distances and pins in the
wrong place.

The replacement never enumerates the map. Zone geometry is a **static table generated offline from
the vanilla `WorldMapArea` DBC**, cross-checked against Astrolabe's own numbers, so the same data is
right before the client has been asked anything. Zone identity is a stable numeric map id and the
locale-independent `mapFile` string; the zone *index*, the identifier that is unreliable here, takes
no part in coordinate maths or in anything saved to disk.

**Ace2 is gone.** Seventeen embedded Ace2-era libraries went with it — most of them were never
called — replaced by the Ace3v modules the addon actually uses.

**The options window is new.** The Ace2 version had no GUI at all, only a slash-command tree; the
same options table now drives a real window through `LibConfig-1.0`, with profile management from
`AceDBOptions-3.0`.

A number of things that had never worked were fixed on the way, among them: `/way list all` and
`/way reset <zone>` both errored out instead of running, the crazy arrow pointed the wrong way (its
sprite sheet turns counter-clockwise, and the original also carried a systematic error across the
eastern half of the compass), a waypoint's zone could be reported as the zone you were standing in
rather than its own, and removing a zone's waypoints left the arrow pointing at nothing instead of
at the next waypoint. Distances are labelled **yards**, which is the unit they were always in.

## Libraries

Bundled under `Libs/`, all vanilla-compatible:

| Library | For |
|---|---|
| `LibStub`, `CallbackHandler-1.0` | Library plumbing |
| `AceAddon-3.0`, `AceCore-3.0`, `AceConsole-3.0`, `AceDB-3.0`, `AceDBOptions-3.0`, `AceHook-3.0`, `AceLocale-3.0` | Addon framework, saved variables, slash commands |
| `LibConfig-1.0` | The options window |
| `LibHereBeDragons-1.0`, `LibHereBeDragons-Pins-1.0` | Map coordinates, distances, minimap and world map pins |
| `LibBabble-Zone-2.2` | Localized zone names, so `/way <zone>` works on a non-English client |

`AceGUI-3.0` and `AceConfigDialog-3.0` are deliberately **not** shipped: they do not work on Unreal
Azeroth, which is why `LibConfig-1.0` exists.

## Credits

- **Cladhaire** (jnwhiteh) — TomTom itself, and still maintaining it on retail. The current release
  lives at [WoWInterface](https://www.wowinterface.com/downloads/info7032-TomTom.html).
- **Aero, Schaka, Logonz, Dyaxler, Alphaest, cralor** — TomTomVanilla, the 1.12.1 port that is the
  direct base of this one.
- **Esamynn** — Astrolabe, which did the map maths in TomTom for years and whose zone offsets are
  still the reference this project validates against.
- **Nevcairiel** — HereBeDragons, whose API the two new libraries follow.
- **laytya** — the Ace3v backport of Ace3 to 1.12.1.
- **dh-harald** (Peter Nyilas) — `LibConfig-1.0`, released under the MIT licence.
- **shagu** — pfQuest, the reference for what actually works in a vanilla map layer.

TomTomVanilla's own `.toc` names `cladhaire` as `## Author` and lists its porters under
`## Credits` — it never presented itself as a separate work. This `.toc` keeps that attribution
exactly as it found it.

## Licence

A grey area. Stated as plainly as it can be, rather than papered over.

**TomTom has never shipped a licence file.** The earliest releases carry no licence statement at all;
an explicit **All Rights Reserved** notice appears in the source between `1.1.0-beta` and
`1.1.1-beta`, and the changelog entry announcing it describes it as having always been the case,
which the earlier releases do not bear out. In practice both states land in the same place: absent a
grant, the author keeps their rights, so "no licence" is not permission either. TomTomVanilla added
nothing and named Cladhaire as its author rather than itself. This addon is a derivative work two
steps down that chain, so **ask Cladhaire before redistributing it**.

The one clearly licensed piece of the old tree was **Astrolabe**, bundled under the **LGPL**. It is
no longer shipped here.

**The bundled libraries are not a grey area, and their notices ship with them:**

| Library | Licence |
|---|---|
| `AceAddon-3.0`, `AceCore-3.0`, `AceConsole-3.0`, `AceDB-3.0`, `AceDBOptions-3.0`, `AceHook-3.0`, `AceLocale-3.0` | Ace3's BSD-style terms, Ace3 Development Team |
| `LibConfig-1.0` | MIT, DeepSeek and Peter Nyilas — deliberately permissive, so this one is freely reusable |
| `LibStub` | Public domain, per its own header |
| `CallbackHandler-1.0` | No statement in the file |
| `LibBabble-Zone-2.2` | No statement in the file; ported from ckknight's Babble-Zone-2.2 |

Both the Ace3 and the MIT terms require their notice to travel with the code, so those notices belong
in the package alongside the libraries.

**The two map libraries are separate from all of the above** -- they contain no TomTom code -- but
they are not equally independent of HereBeDragons, and the difference matters:

- **`LibHereBeDragons-1.0`** is an independent implementation. It follows HereBeDragons' public API
  and shares none of its internals: upstream queries the client and works from world coordinates,
  this works from a static table generated offline from the vanilla `WorldMapArea` DBC and from
  0-1 map coordinates, because the client it targets has no `UnitPosition` at all.
- **`LibHereBeDragons-Pins-1.0`** is mostly this project's own -- notably the whole world-map layer,
  since retail's canvas provider does not exist here -- but its minimap placement maths is a **close
  port of `drawMinimapPin` from HereBeDragons-Pins-2.0**, with one sign changed for this port's axis
  convention, and its minimap yard table is the same data (which Astrolabe and pfQuest also carry).

HereBeDragons declares `## X-License: BSD`, so both libraries are released under **BSD 2-Clause**,
the same terms as the work they follow. `LibHereBeDragons-Pins-1.0` carries Nevcairiel's copyright
alongside Peter Nyilas's for the ported parts; `LibHereBeDragons-1.0` carries only the latter. Each
one's `LICENSE` names exactly which parts derive from upstream and which do not.
