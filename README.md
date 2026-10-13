# REALSTEEL

Spike for a Tekken-style 3D fighting game on Roblox. It proves that fighting-game netcode and a frame-data model work
on Roblox's server authority mode (client prediction, rollback and resimulation) before investing in content.

Fighters are five original robots modeled in Blender, one for each chassis (ANVIL, BULWARK, LANCE, RAZOR and MAUL), built
on one skeleton, finished in worn painted metal and animated from the simulation state. Every player fits a robot out in
the garage: a chassis, a module each for arms, core and legs, and a paint job, and can buy a premium body for any chassis
(HAYMAKER, BASTION, SPECTRE, RONIN or MONARCH) with Robux or crests with the coins every match pays. There are four
attacks (a punch and a kick for each side), a throw, guard with a guard bar that runs out, and dash, best-of-three rounds
with a clock, a computer opponent at three levels, 1v1 versus, a training mode with a frame meter, and touch controls.
Players walk around THE FOUNDRY, a robot fight club hall with the main ring in its middle, two practice pits beside it,
pads in front of the main ring that start a fight for whoever stands on them, everyone's robots in garage bays along one
wall, and a line that hands each ring to whoever should have it. Robots wait hanging from winches
under each ring's screen and are dropped onto the canvas when a match starts; wins go on the players' records, the
all-time leaderboards hang on the north wall, and whoever holds the champion's title (won and defended in 1v1s) stands
there as a gold statue.
Hit effects, lights and sound come with it.

## Where it lives

- **Code:** the private GitHub repository [yassinsolim/REALSTEEL](https://github.com/yassinsolim/REALSTEEL), branch `main`.
  The place files are built from it and never committed.
- **Game:** the private Roblox experience REALSTEEL (universe `10770512111`, place `76746803669217`).
  `.\scripts\publish.ps1` runs the validation, builds the game place and publishes it as a new version through Open
  Cloud. The API key and the IDs are kept for your Windows user outside the repository (see the notes at the top of the
  script). Commit before you publish, so every published version can be traced to a commit.

## Run it

```powershell
.\scripts\dev.ps1 validate   # format check, selene, strict typecheck, rojo build of the game and of the checks place
```

Open `build\REALSTEEL.rbxlx` in Studio and press Play. You spawn on a catwalk over the hall as your Roblox avatar. The
pads in front of the main ring start a fight when you stand on them: the two 1V1 pads (blue and red) count down from 3
once someone stands on each, and the BOT EASY, MEDIUM and HARD pads and the TRAINING pad start yours after 2 seconds.
Step off to cancel. **PLAY** (or **P**, Select on a gamepad) opens the PLAY card with the same choices: a bot (EASY,
MEDIUM or HARD) for a best-of-three match, TRAINING for a dummy with frame data, 1V1 against the next player who joins
the line, or GARAGE to build and paint your robot. Your bay along the west wall has a GARAGE prompt by your robot.
Picking a fight puts you in line: a bot match or training goes to the first free practice pit (or the main ring when both
pits are busy), a 1v1 to the main ring (or a pit while the main ring is busy). When it is your turn your character steps
into an operator's booth beside your ring and the fight camera swoops over to it. Each match is first to two rounds of 60
seconds; a KO or the clock ends a round (more health wins on time), and a drawn round is replayed. The result card offers
REMATCH while nobody is waiting for your ring and LEAVE THE RING. While nobody wants the main ring, two bots fight an
exhibition in it. See The Foundry below for the rules of the line.

| Input | Keyboard and mouse | Gamepad | Touch |
| --- | --- | --- | --- |
| Walk around the hall | W A S D, Space to jump | Left stick, A | Stick, jump button |
| PLAY card | P or the PLAY button | Select | PLAY |
| Start a fight on a pad | Stand on it | Stand on it | Stand on it |
| Garage at your bay | E at the prompt | X at the prompt | Tap the prompt |
| Back, forward | A, D | Left stick left, right | Stick, bottom left |
| Sidestep | W (away from the camera), S (toward it) | Left stick up, down | Stick |
| Jab (left punch) | Left mouse or J | X | JAB |
| Straight (right punch) | Right mouse or K | Y | STRAIGHT |
| Snap kick (left kick) | Q or U | A | SNAP KICK |
| Power kick (right kick) | E or I | B | POWER KICK |
| Grab (throw) | Both mouse buttons, or J and K, together | X and Y together | GRAB |
| Break a throw | Grab within 0.3 s of being caught | X and Y within 0.3 s | GRAB within 0.3 s |
| Guard (hold) | Left Shift | L1 or L2 | GUARD |
| Dash | Space, with a direction held (neutral backs off) | R1 or R2 | DASH |
| Leave a bot match or training | Hold P | Hold Select | Hold LEAVE |
| Garage: open, switch page, close | G on the PLAY card or E at your bay; Q E; G or Backspace | GARAGE on the PLAY card; L1 R1; B | GARAGE, tabs, DONE |
| Training: next dummy, reset | T, R | Not bound yet | DUMMY, RESET (training only) |
| Card navigation | W S or arrows, Enter, mouse; Esc or P closes | D-pad, A; B closes | Tap |

The fight controls read like the screen. The camera always keeps your fighter on the left facing right, so D is always
toward the opponent and A away, and W and S sidestep into and out of the screen. The four attacks follow the body: left
and right, punches and kicks, and both punches at once grab. The menu key sits on P, away from the punches on J and K,
and leaving a fight takes a 0.6-second hold, so a stray press never ends one. The touch layout puts the four attack
buttons in a 2x2 block (punches on top, kicks below), with GUARD, DASH and GRAB beside it and the training buttons in a
column at the left edge. LEAVE (hold) shows in a bot match and in training; DUMMY and RESET appear only while training is
on. The touch controls belong to the rings: Roblox's own stick and jump button come back in the hall, and both hide while
a card is up. Your avatar does not walk while a card or the garage is up, or while you are in a ring.

The touch layout appears when Roblox reports touch as the preferred input. Setting the attribute `ForceTouchUI` on the
local player shows it on a desktop. Tooling is pinned in `rokit.toml` (same versions as OVERLOADED).
`.\scripts\dev.ps1 serve` runs Rojo for live sync.

## Try it with a second player and on a phone

- **Two players on one PC:** in Studio, Test tab, choose Server & Clients, set 2 players, press Play. Each client window
  is a real client. Pick 1V1 in both and they are seated against each other.
- **Phone:** publish a private test place, then open it in the Roblox app signed in as the owner. To let another person
  join, add them as a collaborator or temporarily set the experience to friends only in Creator Hub.
  - Quickest: with `build\REALSTEEL.rbxlx` open, File > Publish to Roblox. This creates a private experience.
  - Scripted, like OVERLOADED: create the experience in Creator Hub, create an Open Cloud API key with the
    `universe-places` API (Write) for it, then run `.\scripts\api-key.ps1 -Set` (the key is typed at a hidden prompt and
    stored encrypted outside the repository) and `.\scripts\publish.ps1 -UniverseId <id> -PlaceId <id>`. The IDs are
    remembered afterwards. `-DryRun` shows what would be sent. Only the game place is published, never the checks place.

## Frame data

All timings are simulation frames at 60 per second. Advantage is hitstun (or blockstun) minus active plus recovery,
because the attacker is committed from the first active frame.

| Move | Startup | Active | Recovery | Damage (chip) | Guard | On hit | On block |
| --- | --- | --- | --- | --- | --- | --- | --- |
| Jab | 7 | 3 | 11 | 8 (1) | 70 | +4 | -1 |
| Straight | 12 | 3 | 17 | 16 (2) | 170 | +2 | -9 |
| Snap kick | 10 | 3 | 15 | 11 (1) | 130 | +2 | -7 |
| Power kick | 15 | 4 | 22 | 24 (3) | 260 | +3 | -14 |
| Grab | 10 | 2 | 26 | 18 | | +18 after the throw | cannot be blocked |
| Dash | 2 | 8 moving | 7 | | | | |

The punches reach farthest (jab and straight connect out to about 4.8 and 5.6 studs between centers). The kicks are
slower and shorter (about 4.3 and 4.6) but hit harder and shove the target away: the power kick pushes about 2.4 studs,
the jab about 0.9. Attacks travel along the line locked when they start, so a sidestep or backdash on reaction beats the
slow ones. The jab starts in 7 frames, which is faster than a typical human reaction, so it has to be anticipated. A
faster hit that lands during an attack's startup interrupts it. Chip damage and training hits never knock a fighter out. The
knockout blow freezes both fighters for 26 frames. Walking is quick (8 studs a second forward, 5.5 back, 6.5 sideways) and
the dash covers 3.2 studs in 8 frames, so closing a gap is a decision and not a chore. The numbers live in
`src/shared/FightConfig.luau`; the timings were tightened by about a fifth from the first version, and the advantage on hit
and block did not change.

Nobody can hold the guard up forever:

- **The guard bar.** Under each health bar is a guard bar of 1,200 points. Holding the guard drains 1 point a frame (a full
  bar lasts 20 seconds with nothing coming in), and every blocked move takes its Guard value on top of that. Once the guard
  has been down for 45 frames the bar fills back up at 6 points a frame (about four seconds from empty). It turns amber at
  half and red, pulsing, at a quarter. Blocked back to back, a guard breaks after about seven straights or fifteen jabs.
  BULWARK's guard drains 25% slower.
- **Guard break.** When the bar runs out, from a block or from holding on too long, the guard breaks: GUARD BROKEN shows,
  the robot reels with its arms knocked wide, and it is open for 60 frames (a second), long enough for any attack to land.
  The blow that broke it freezes the pair 10 frames longer. The bar starts again at half once the break is over or a hit
  ends it. Chip damage still never knocks anyone out.
- **The throw.** Both punches together grab (a jab or straight up to 2 frames before the other punch turns into the grab).
  It catches an opponent no farther than 3.3 studs away in front, who is standing, guarding, dashing, grabbing, guard-broken
  or finishing an attack. It cannot be blocked, but any attack beats it: an attack on its way out cannot be caught, and the
  jab lands first, and an opponent in hitstun or blockstun cannot be caught either. Caught, the robot is hoisted overhead
  and slammed onto its back for 18 damage, slides away and gets up, and the thrower is up 18 frames first. A missed grab
  is 38 frames of whiffing. Grabbing back within 18 frames (0.3 s) of being caught breaks the throw: both shove each other
  off and stumble back even, and two grabs that catch each other do the same.

The training overlay shows the table values for your last move, the **measured** advantage of the last exchange taken
from recorded states, and a frame meter for both fighters (guard breaks and throws have colors of their own). Measured and
table values agree for all four attacks, on hit and on block, both in the unit checks and live in Studio. The GRAB LOOP
dummy walks in and grabs, to practice breaking throws.

## How it is built

| Piece | Where | Notes |
| --- | --- | --- |
| Fight rules | `src/shared/FightSim.luau`, `FightConfig.luau` | Pure Luau, no Roblox APIs, frame-based, positions snapped to 1/1024 stud. |
| Match flow | `src/shared/MatchFlow.luau` | Pure rounds, clock, wins and phases (lobby, free, intro, fight, round end, match end). State lives on the match core, so it is predicted and rolled back like everything else. |
| Bot | `src/shared/BotBrain.luau` | A pure function of the fighters' states and the frame counter. No memory, nothing replicated: every peer computes the same inputs. See The bot. |
| Frame data | `src/shared/FrameData.luau` | Table-derived numbers, a rolling state history keyed by frame, and the advantage measurement. |
| Roblox adapter | `src/shared/Simulation.luau` | Bound with `RunService:BindToSimulation` at 60 Hz on server and client. State lives in attributes on each fighter's `Core` part. Every ring is a fight of its own (`addRing`), and each step advances them all; the server and the clients number the rings alike. |
| Inputs | `src/shared/InputSetup.luau` | Input Action System contexts created under each Player, plus a Scriptable binding on every action. `FightSim.moveFromStick` turns the screen-style stick reading into walking and sidestepping. |
| World | `src/server/` | The hall (`Foundry.luau`, `FoundryStations.luau`), the main ring's island and the practice pits (`Arena.luau`) and every ring's fighter cores (`WorldBuilder.luau`, under `Workspace.Rings`) are built from code; `FoundryLayout` (shared) holds the positions the clients need too. `Rings.luau` runs the line for the rings and publishes it, `Ring.luau` seats players in one ring and sets its fight up; `Main.server` wires players to their garage, their bay and the `Menu` remote (bot with a level, training, versus, leave, rematch). See The Foundry. |
| Ring line | `src/shared/RingQueue.luau` | Pure: who gets which ring next, how pairs from the 1V1 pads go together, when a rematch is open, which training has to make room. |
| Pads | `src/shared/PadRules.luau`; `src/server/Pads.luau`; `src/client/PadView.luau` | Pure rules for who holds each pad in front of the main ring and when its countdown runs out; the server reads where characters stand and starts the fights; the client draws names and countdowns. See The Foundry. |
| Records | `src/shared/Standings.luau`; `src/server/Records.luau` | Pure rules for records, the champion's title and leaderboard order; the server's profiles, DataStore saves, all-time boards and what it publishes on `FoundryState`. See The Foundry. |
| Winches | `src/shared/Hoist.luau`; `src/client/Cranes.luau` | Pure: how high each ring's robots hang from their winches and where the hooks are, from the ring's match phase and frame; the client draws the cables and hooks. See The Foundry. |
| Robot art | `art/`, `scripts/art.ps1` | Blender (headless) builds the five robot frames and their worn-metal textures, exports the FBX, and generates `src/shared/RobotRigs.luau`, `RobotClips.luau` and `RobotKits.luau`; the textures are wired up in `RobotWear.model.json`. See Robot art and animation. |
| Garage | `src/shared/Loadout.luau`, `Looks.luau`, `RobotKits.luau`; `src/server/Garage.luau`; `src/client/GaragePanel.luau` | Chassis, modules and paint as small integer codes, the stats they derive, the frame and crest each is drawn with, the server's profile and the screen. See The garage. |
| Shop | `src/shared/Shop.luau`; `src/server/Wallet.luau`; `scripts/products.ps1` | The cosmetic catalog and the coins matches pay; each player's coins and owned items, Robux receipts and coin purchases; the developer products. See The shop. |
| Animation | `src/shared/RobotSkeleton.luau`, `RobotAnimator.luau` | Pure Luau forward kinematics, clip sampling, and the mapping from simulation state to a pose. |
| Presentation | `src/client/` | Draws and poses the robots in every ring (`FighterView`, `RobotRig`, and `Bays` for the robots in the garage bays), the camera (`CameraRig`), hit effects (`Effects`), sound (`Sfx`), HUD (`Hud`), the hall's PLAY button and line status (`LobbyHud`), the scoreboards over the rings (`Jumbotron`), the winches' cables and hooks (`Cranes`), the champion's statue (`Statue`) and the leaderboards (`Leaderboards`), menu (`Menu`), garage (`GaragePanel`), training overlay, touch controls, smoothing of rollback corrections. |

Server authority is enabled through `Workspace` properties in `default.project.json` (`AuthorityMode`, `UseFixedSimulation`,
`NextGenerationReplication`, `PlayerScriptsUseInputActionSystem`, `StreamingEnabled`). Rules learned from the docs and tests:

- Inside the bound function only "Simulation Access" APIs work (attributes, `GetChildren`, `InputAction:GetState`,
  `IsResimulating`). `FindFirstChild`, `Name` and `Parent` do not, so instances are cached outside it.
- Fighters are not Humanoids, so the client calls `RunService:SetPredictionMode(core, On)` for each, and for the match core.
- Hit detection is plain math on simulation state, not spatial queries.
- Commands such as the bot level, dummy mode and reset are replicated attributes on the match core that the simulation reads,
  so every peer applies them on the same frame. The only remote is the menu request, which the server validates (a
  player with a seat, a known action, a level from 1 to 3, a short cooldown, and no mode changes while two humans play).
  The server reads the training hotkeys of each ring's first seat itself.
- Touch controls and tests drive actions with `InputBinding:Fire` on a Scriptable binding. `InputAction:Fire` is
  deprecated.

## Look and feel

The venue is one palette: navy and electric blue for the building, teal and amber for the light lines, and the fighters
own blue and red, so the robots are always the most saturated thing on screen.

- **Arena** (`src/server/Arena.luau`, built from code, about 1250 parts): a navy floor with a teal ring and amber
  runway lights, the ring with eight posts and three thin energy ropes, a low barricade, four steep rows of stands that get
  brighter toward the top, about 260 silhouetted fans (a few hold up lights), a wall in two blue bands, and a ring of
  girders with eight fixtures and a faint beam each. Posts and ropes carry the `RingFade` tag
  (`FightConfig.RingFadeTag`), and the client fades the ones between the camera and the fighters.
- **Stage lights** (`src/client/StageLights.luau`): a shadow-casting key light above the pair, a rim light behind each
  fighter in its team color, and a soft fill at the camera. They follow the fighters, so the lights are part of the fight
  rather than part of the building. Nothing in the building casts light.
- **Lighting** (`default.project.json`): Future technology, bloom, color correction, depth of field, atmosphere, and no
  sky texture. Rules learned the hard way:
  - Future lighting is physically based. Near-black surfaces never show, big bright Neon surfaces wash the robots out, and
    a light's strength falls with the square of the distance. The stands are therefore mid-dark blue Neon with near-black
    people on them, so the crowd reads as silhouettes.
  - Devices that cannot run Future fall back to ShadowMap, which needs about 40% of the light for the same look.
    A script cannot read `Lighting.Technology`, so the light strengths are a compromise: slightly dark in Future and
    slightly bright in the fallback.
  - A light that is created or changed at runtime takes several seconds to re-bake. Judge the look about 20 seconds after
    play starts, with the Studio window in the foreground: when another program took the foreground the frame rate fell
    to about 15 and the shadows and lights faded, and both came back when the window was focused again.
- **Venue animation** (`src/client/ArenaFx.luau`): two highlights chase along the LED ribbon on the front of the stands and
  the held-up lights twinkle, both faster when the crowd is excited (a heavy hit or a KO sets them off, then they settle
  over a few seconds). The server tags the parts (`FightConfig.RibbonTag`, `CrowdLightTag`), the client recolors them a few
  times a second.
- **Effects** (`src/client/Effects.luau`): flash, shock ring and sparks on hits, blocks and the KO, dust on dashes, strike
  trails on the limb that is actually throwing the move, a brief screen flash and a push-in of the camera on every hit,
  and a camera shake value. The shock ring is a circle outline that always faces the camera; a flat disc facing the
  attacker is edge-on to the broadside camera and showed up as a slab cutting through both robots. They are triggered by
  rendered state changes (a fighter's hitstop starting) with a short per-slot cooldown so a rollback cannot fire one
  twice, and they clean themselves up. A predicted hit that the server later retracts can still flash once. The opponent
  is drawn as a southpaw, so it throws each move with the other limb (`FighterView.limb`); `RobotSpec` checks that,
  because it once put the effects on an idle hand.
- **Colors**: the local fighter is always the left one, in blue and light steel; the opponent is red and dark gunmetal.
  Which slot you hold does not matter.
- **Camera** (`src/client/CameraRig.luau`): in the lobby a slow orbit behind the menu; at the start of a round a low sweep
  that settles into the fight camera as the bell rings; in the fight, broadside to the pair at a 48 degree field of view
  (54 on touch), close enough that the robots fill the frame, backing off when the window is narrow and never past the
  barricade; on a KO a gentle push-in on the fighter who went down, held through the freeze and the fall, then eased back
  out. Both robots always stay whole in the frame: when the barricade stops the camera backing off, the lens widens
  instead, and after a KO the aim rises to fit the winner with both arms up (higher still on touch, which has the bars
  across the top). When the result card appears the pair slides to the left, so the winner is not hidden behind it; that
  needs a view at least `FightConfig.ResultMinWidth` (740) pixels and `ResultMinAspect` (1.5) times wider than tall, which
  a phone in landscape meets. On touch the pair is framed lower during a round, clear of the bars at the top and the
  buttons in the corners.
- **Emotes**: the robots hang powered down from the winches until they are set down, flex before the bell, the winner
  pumps both arms and the loser slumps (`art/poses.py`: `Slump`, `IntroA/B`, `VictoryA/B`; the animator plays them only
  while a fighter stands free).
- **HUD** (`src/client/Hud.luau`): two health bars around a plate that shows the round clock (turning red for the last ten
  seconds) or VS outside a match, each bar with a gradient fill, tenth marks, a trailing damage bar and round pips; floating
  damage numbers; ROUND 1, FINAL ROUND, FIGHT!, K.O. and TIME banners with a PERFECT, ROUND WON or ROUND LOST line; soft
  shading along the top and bottom edges; red edges that pulse while the local fighter is under 30% health; and a small
  ping and frame rate readout in the corner. A card of controls shows for the first 14 seconds, and **H** (or a tap on the
  training line under the plate) brings it back and, in training, opens the frame data and meter. The Roblox player list
  and backpack are turned off so they cannot cover the opponent's bar.
- **Menu** (`src/client/Menu.luau`): a card over the orbiting arena with the three bot levels and training, and a result
  card (YOU WIN / YOU LOSE, the score and the bot's level) with REMATCH and CHANGE MODE. When the view is wide enough (the
  same rule as the camera's slide, so a phone in landscape counts) the result card rests on the right under a light shade,
  beside the winner; on a narrower view it stays centered. Mouse, touch, keyboard and gamepad all work, and on a phone the
  rows shrink and the one-line descriptions go away. The menu and the HUD's card of controls are plain frames that fade
  piece by piece: a CanvasGroup is drawn at the player's graphics quality, so it blurs on lower settings.
- **Sound** (`src/client/Sfx.luau`): punches, heavy hits, metal clanks on blocks, whooshes timed so their swell peaks as
  the strike lands, a boom and a crowd swell on a KO, a bell to start a round and to end it on time, and a crowd bed that
  rises with the action. Each sound is a free Creator Store asset (credits below); a variation and a slight pitch change are
  picked per play, and a sound that fails to load is skipped. I cannot listen, so the assets were chosen by their length
  and descriptions, and by measuring their loudness over time with an `AudioAnalyzer` (a hit has to start within a frame
  or two). Whether they sound good is for a human ear to judge.

### Audio credits

All from the Creator Store, free to use: Punch Impact 1, 2 and 3 (NickySergal), Heavy_punch_impact_#3 (MegaBloxxy), Boxing
Bell (scorp_ius), Large Arena Crowd Ambience (Extreme Action Wrestling), and Metal Drops Clanking Impacts On Concrete 11,
Electric Whoosh Bys Singles Low End Synth Buzz 1, Deep Hits Big Reverberant Booms Rumbling Tail 1 and Wrestling Crowd 3
(Pro Sound Effects). The ids are in `Sfx.luau`.

## The bot

`BotBrain.input(tick, me, foe, into, level, salt)` is a pure function: it reads the two fighters' states and the session's
frame counter, and fills in what the bot presses. It has no memory and nothing about it is replicated or rolled back; the
server and every predicting client compute the same inputs. Its "randomness" is a hash of the frame, so choices hold for a
few frames at a time instead of flickering. It plays by what a person could see:

- **Reading attacks.** It notices an attack only after a reaction delay, so it can block a slow straight or power kick
  but not a jab it has not had time to see. Easy never reads a straight in time.
- **Defending.** It blocks what it noticed, sometimes back-dashes out of a slow attack, sometimes interrupts one with a
  quicker jab, and sometimes holds its guard up on a hunch.
- **Punishing.** When the opponent is stuck in recovery from a miss or a block, it hits back with the strongest move that
  lands in time.
- **Hitting what walks in.** MEDIUM and HARD throw a jab at an opponent who is walking into range (a straight while it is
  still far), aimed at where the opponent will be when the attack lands rather than where it stands. EASY waits to be reached.
- **Hitting what cannot defend itself.** An opponent in hitstun, or recovering from a dash, gets the strongest move that
  lands before it is back on its feet, or a jab to keep it busy, and the bot walks in after an opponent that cannot hit back.
- **Keeping the guard up.** Coming out of a hit or a block with the opponent still on top of it, the bot has its guard up
  when the stun ends, so a follow-up timed for the gap is blocked, and it keeps a raised guard while the opponent keeps
  attacking.
- **Guard bars and throws.** Every level grabs an opponent who sits behind its guard close by, EASY rarely and HARD most,
  and walks in on one that guards just out of reach. MEDIUM and HARD also mind the bars: they stop guarding once a block
  would break their own guard (a hit costs less than a break), lean on an opponent whose bar runs low, and land their
  strongest move on a broken guard. Caught by a grab, MEDIUM breaks about a third of throws and HARD about 60%; EASY reacts
  too late to break any. Against an opponent who only ever guards, HARD takes a whole health bar off it in 20 seconds,
  throwing it several times on the way.
- **Offense and spacing.** It attacks on a timer with a chance per decision, weighted toward the moves that reach, holds a
  poking distance, strafes, dashes across a gap, and leans back toward the middle of the ring near the ropes.

| Level | Reaction | Decides every | Blocks what it sees | Punishes | Fires at a walker | Wastes an attack |
| --- | --- | --- | --- | --- | --- | --- |
| EASY | about 0.4 s | 0.53 s | 30% | 15% | never | 22% |
| MEDIUM | about 0.22 s | 0.43 s | 60% | 55% | 25% | 10% |
| HARD | about 0.18 s | 0.3 s | 75% | 70% | 35% | 8% |

Without the three tactical behaviors above, a player who walked in and mashed one button beat every level: the jab won 100
of 100 rounds against EASY, MEDIUM and HARD alike, and so did the straight. The levels were calibrated with a headless
harness (below), 100 rounds per matchup. Against each other MEDIUM beats EASY 97% of the time and HARD beats MEDIUM 82%.
Against scripted players that walk in and mash one attack, the share of rounds the bot wins is:

| Level | Jab | Straight | Dash in, then jab | Sidestep and straight |
| --- | --- | --- | --- | --- |
| EASY | 0% | 0% | 0% | 0% |
| MEDIUM | 21% | 31% | 19% | 28% |
| HARD | 77% | 84% | 57% | 72% |

The older stand-in humans (rookie, average, good), which only differ in how well they read and punish and do not play the
neutral game, lose to the new levels more than a person who walks in and jabs does: EASY beats the rookie 95% of the time
and loses to the average and the good one (22% and 5%); MEDIUM wins 100%, 90% and 69%; HARD wins 100%, 98% and 96%. So treat
the mashers as the better yardstick, and both as measurements against scripted stand-ins rather than people: they are the
start of tuning rather than the end. Play it and adjust the numbers in `BotBrain.Levels`.

## The Foundry

The lobby is a place, not a menu: a dark steel hall about 166 by 122 studs that players walk around in as their Roblox
avatars. Roblox's server authority keeps characters server-owned and predicted, so walking avatars live alongside the
fights' netcode. Three fights can run at once: the main ring and two practice pits.

- **The hall.** You spawn on a catwalk along the south wall that looks over everything; stairs at both ends lead down. The
  main ring stands in the middle on an island ringed by a loop of molten channel under grates, behind a rail with an LED
  line that runs with the crowd's excitement. An invisible wall behind the rail keeps characters out of the fight camera's
  way. Beside the ring are the two operators' booths, the pads face the catwalk in front of it (see below), a
  four-sided screen hangs over the ring, and the hall's name is on the north wall. `Foundry.luau` builds it and
  `FoundryLayout` has the numbers.
- **The pads.** Between the main ring and the catwalk stand six pads: the blue and red 1V1 pads facing each other across
  the walkway with VS painted between them, three amber bot pads to the west under one VS BOT sign, each with its level
  (EASY, MEDIUM, HARD) in the PLAY card's colors, and a teal TRAINING pad to the east. Standing on one asks for its
  fight, no menu needed. The 1V1 pads count down from 3 once a different player
  stands on each, then put the pair in line together: they fight each other, the blue pad's player in the first seat (the
  west booth). The bot and training pads start their player's fight after 2 seconds. Stepping off cancels; a countdown
  that has run out is done with its players, who can walk away while they wait, and the pads are free for the next. A pad
  belongs to whoever stepped on first, and the names and countdowns float over the pads for the whole hall to see.
  `PadRules` (shared, pure) decides who holds what and when, `Pads` on the server reads where every character stands ten
  times a second and starts the fights, and `PadView` on the client draws them.
- **The pits.** Along the east side, past the channel, are PIT 1 and PIT 2: the same canvas, ropes and size as the main
  ring (so a fight plays the same anywhere), in a smaller enclosure with a rail just outside the ropes, a work light, a
  small four-sided screen and a booth on each side. Spectators can stand close, so the fight camera, which reaches over
  the rail, hides any character it comes near, and the ropes and rails fade near it as in the main ring. A pit with
  nobody in it shows its two robots parked at their marks.
- **Garage bays.** Eight bays line the west wall. Every player who joins gets one with their name over it, and their robot
  stands on its lift in their own parts and paint, idling (`Bays` on the client draws them from the players' `Bay`,
  `GarageLoadout` and `GarageLook` attributes). Your own bay has a GARAGE prompt; the garage's close-up frames your robot
  there, and characters nearby are hidden on your screen while it is up. The robot wears every pick at once.
- **The line.** Players queue for a fight, not a ring (`RingQueue`), and the line hands every free ring to whoever should
  have it. Two players from the 1V1 pads are a pair already and go to the line together; other 1V1 players (from the PLAY
  card) pair up two by two, earliest first, and a lone 1V1 waiter holds up nobody. A 1v1 takes the main ring, or a pit
  while the main ring is busy. A bot match or training goes to the first free pit, or to the main ring when both pits are
  busy, in line order. Pairs are placed first, since practice can go elsewhere. When a ring is yours your robot goes in
  with your garage build and your character stands in one of its booths, held there, while the fight camera swoops over. A
  finished match stays up for 7 seconds when someone is waiting for that ring and 25 otherwise, which is the window for
  REMATCH (offered only while nobody waiting would get the ring). Training has no end of its own, but once someone
  waiting could take its ring it gets 45 more seconds; with several sessions in training, the ones that have run longest
  make room, one per player waiting. Holding P leaves a bot match or training; LEAVE THE RING on the result card leaves
  any match.
- **Never empty.** Four seconds after the main ring frees up with nobody waiting for it, two bots (MEDIUM or HARD, with
  random ready-made builds) fight an exhibition, named after their builds on the screen. Six seconds after it ends the
  winches hoist the pair away, and four seconds later the next pair is dropped in. Anyone who wants the ring cuts in at
  once.
- **What the clients are told.** Each ring's own commands stay on its predicted match core. Everything about the line
  lives elsewhere, so it never rolls the clients back: a `FoundryState` folder in ReplicatedStorage with a folder per ring
  (`Session`, `NextUp`, `RematchOpen`, `HandoverAt`), a `Pads` folder with a folder per pad (`Holder`, the UserId on
  it, and `Ends`, when its countdown runs out in the server's clock), and on itself `Waiting`, the title (`ChampionId`,
  `ChampionName`, `ChampionDefenses`) and the boards (`BoardVersus`, `BoardBots` as JSON, `BoardScope`); and attributes
  on each Player (`QueueMode`, `QueueLevel`, `QueueAhead`, `QueueAlone`, `QueueRival` for the player they asked to fight
  on the 1V1 pads, `InRing`, `Ring` for the number of the ring they are in, `Bay`, and `RecordWins`, `RecordLosses`,
  `RecordHardWins`).
- **Seeing it.** Every client draws every ring and predicts all of them (a ring is two fighters, so this is cheap).
  Spectators get the hall: no fight HUD, the screens over the rings (names, health bars, clock, round, next up) and each
  fight's sound fading with distance, the pits' sooner than the main ring's. From a seat, the other rings are only a
  murmur and their hits do not flash your screen. The player list shows in the hall and hides in a ring.
- **The winches.** Under every ring's screen hangs a winch over each fighter's mark. While a ring stands idle its robots
  hang from them, powered down and hoisted clear of the canvas, held by a hook on the head. Over the first round's intro
  they are lowered onto their marks, faster as they go, land with a thud and dust, power up and flex, and the hooks wind
  home before the bell. A robot new to its seat at the start of a match (the next pair of an exhibition, a 1V1 that takes
  the ring from the bots) comes in on the hook too; a rematch starts on the marks. Training lowers the robots straight
  away, and when the ring falls idle again each hook comes down for its robot and hoists it back up as it is: an idle
  ring keeps the robots of its last match until the next one. It is a sight only:
  the fighters stand on their marks in the simulation from the first frame. Where a robot should hang comes from the
  match's own phase and frame count, so every client sees the same drop, and robots and hooks only move toward it at
  capped speeds, so a change of mode or a rollback never makes them jump (`Hoist`, drawn by `Cranes` on the client).
- **Records and the champion.** Every finished bot match and 1V1 goes on its players' records (1V1 wins and losses, and
  wins and losses at each bot level), kept in a DataStore like the garage (`Records` on the server, rules in
  `Standings`). A match counts as soon as its last round is won, even if someone leaves during the knockout; walking out
  of an undecided 1V1 loses it, and so does dropping out of the game, once five seconds show it was not the server
  shutting down (the other player is still there and the server has not closed); a bot match left undecided counts for
  nothing. A server that shuts down reports the matches already won and nothing else, so nobody forfeits by being shut
  out. Records are saved as additions, so neither an outage nor two servers at once can replace a saved record with one
  session's, and a save whose reply was lost is never added twice, whatever other servers wrote meanwhile. The
  champion's title changes hands only in 1V1s, and only to a winner who is still in the server: while it is vacant
  the winner of any 1V1 claims it, the champion who wins defends it, the one who loses hands it over, and it falls vacant
  when the champion leaves. The champion stands on a pedestal north of the main ring as a gold statue of their own build
  in its victory pose (a stock robot in dull steel while the title is vacant), with their name and defenses on the
  plaque, and the whole hall hears when the title changes hands.
- **Leaderboards.** Two boards on the north wall, either side of the hall's name: 1V1 WINS and HARD BOT WINS, the best ten
  of all time from ordered DataStores, refreshed every minute, with your own line picked out. Where DataStores cannot be
  reached (Studio before the place is published) they rank the players in the server instead and say THIS SERVER. A
  player's scores go on the boards after each save of their record, again until they land, and once more when they join.

The plan is to grow the hall in phases. Done: the hall, the pits, then spectacle and status (the drop, the champion and
the leaderboards). Next comes the economy.

## The garage

**GARAGE** (on the PLAY card, or E at your bay) opens a panel beside your robot in its bay, which turns in a slow close-up
and wears every change at once. Everything that changes how a fight plays is a sidegrade, a gain with a cost, and open to
everyone, so a build is a choice and not a rank. What a robot looks like is the part that is earned or bought: the SHOP
sells premium bodies for Robux and crests for coins, which every match pays (see The shop below). Nothing for sale changes
a fight.

| Chassis | Role | Gives | Costs |
| --- | --- | --- | --- |
| ANVIL | all-rounder | the baseline | no trick |
| BULWARK | tank | +10% health, no chip damage, -25% guard drain | -14% walking speed, +2 frames dash recovery, -10% damage |
| LANCE | poker | +10% punch reach | punches start 1 frame later, -4% punch and -10% kick damage, -6% health, -3% walking speed |
| RAZOR | rushdown | +10% walking and dash speed, dash recovers 2 frames faster, jab starts 1 frame sooner | -8% health |
| MAUL | heavy hitter | +18% damage, +20% knockback, +8% health | every attack starts and recovers 1 frame later, -6% walking speed |

| Slot | Module | Gives | Costs |
| --- | --- | --- | --- |
| Arms | PISTON FISTS | +18% punch damage | the straight starts 1 frame later |
| Arms | SERVO WRISTS | punches start 1 frame sooner | -10% punch damage, +2 frames punch recovery |
| Core | PLATING | +5% health | -10% walking speed |
| Core | SHOCK DAMPERS | 2 frames less hitstun and blockstun | -2% health |
| Legs | HYDRAULIC BOOTS | +15% kick damage | +2 frames kick recovery |
| Legs | SPRING GREAVES | +8% walking speed, dash recovers 1 frame faster | -10% kick damage |

That is 5 x 3 x 3 x 3 = 135 builds, and ten ready-made ones, two per chassis, for a player who does not want to choose: STEEL
WALL, CLEAN HANDS, BREAKWATER, IRON CURTAIN, SKIRMISHER, SNIPER, SHREDDER, GHOST, WRECKER and BRAWLER. Paint is 16 armor
colors and 16 accent colors (the first of each is the side's own team color), four finishes (BRUSHED, MATTE, CHROME, GLOSS) and
seven head crests (none, FIN, ANTENNA, HORNS and HALO for everyone, CROWN and MOHAWK from the shop). The opponent never wears
colors too close to yours: `Looks.resolve` falls back to its team colors.

- **How a build travels.** `Loadout.encode` turns a choice into one integer (1 to 135) that the server sets on each fighter's
  `Core` as the attribute `Loadout`. `Simulation` derives `fighter.stats` from it (`Loadout.stats`, built once per code), and
  the sim, `FrameData`, the animator and the bot all read those stats instead of global constants, so the server and every
  predicting client play identical numbers and a rollback with different builds stays deterministic. A stock ANVIL plays
  exactly as it did before the garage existed. A look is one integer (1 to 14336) on the fighter's model, the attribute
  `Look`: the body, the paint, the finish and the crest. Saves keep each choice on its own, so the code may change as the
  lists grow.
- **The server.** `src/server/Garage.luau` owns the `Garage` remote. A client sends its whole garage (`"set"` and the nine
  choices); the server sanitizes every number, accepts one request per 0.1 s per player, publishes the result on the player
  (`GarageLoadout`, `GarageLook`), and saves it to the DataStore `RealSteelGarage1` (batched, at most every 15 s, and when the
  player leaves or the server shuts down). A pick of a shop item the player does not own is kept, so it goes on the moment
  they buy it, but what is published and what their fighter wears leave it off (`Looks.strip`). It loads the saved garage
  when the player joins. A change reaches the fighter
  when the player's next turn in the ring starts, so a match in progress keeps its robots. The bots take theirs from
  `Loadout.botChoice`: EASY the stock ANVIL, MEDIUM a random stock chassis, HARD a random ready-made build. Where DataStores
  are unreachable (an unpublished place without Studio API access) saving is off, with one warning, and the garage still
  works for the session.
- **The screen.** `GaragePanel` and `GarageWidgets` have four pages: BUILD (five rating bars, then the chassis and each
  module, with its gains as solid green dots and its costs as red rings), PRESETS, PAINT and SHOP. The panel is a column beside
  the robot on wide views, a sheet along the bottom on tall narrow ones, and tighter on touch. The robot wears each pick at
  once; the panel sends it at most every 0.2 s and keeps asking until the server's published copy matches, giving up after
  4 s. `CameraRig` has a garage mode that sways a little around the robot's front with a lens shift, so the robot stands in
  the middle of what the panel leaves free, and backs off or opens the lens when that is too small.
- **Frames and crests.** Each chassis is drawn as its own robot, a frame (see Robot art and animation), a little larger or
  smaller (`scale`; the hit circle does not change), and swaps in place when the chassis changes. Modules change numbers
  only and draw nothing for now. The crests are add-on kits, plain Parts fastened to the head joint, so they fit every
  frame: 6 kits and 32 pieces authored in `art/kits.py` (pure Python) and generated into `src/shared/RobotKits.luau` by
  `python art/kits.py --luau src/shared` or `.\scripts\art.ps1`. `.\scripts\art.ps1 -Previews kits` renders the crests and
  some paint jobs into `art\build\kits_*.png`.
- **Adding a part.** Add it to the end of `Loadout.Chassis` or `Loadout.Modules` (a mod is a table of multipliers and frame
  counts, see `Loadout.Mod`); a new chassis also needs a frame of its own (in `build_robot.FRAMES` and `Looks.Frames`).
  Then run `LoadoutSpec`, `RobotSpec`, the balance tournament and the preview renders. Choices are saved as positions in
  these lists, so inserting in the middle would change what a saved garage means.
- **Balance.** `.\scripts\balance.ps1 -Luau <path to luau.exe> -Mode all` (or `chassis`, `modules`, `presets`; `-Level 1` to
  `3`, `-Rounds`) plays the bot on both sides of every matchup headlessly. With the numbers as they are, the stock chassis win
  46-50% against each other at MEDIUM and 47-53% at HARD, every ready-made build wins 46-58% at MEDIUM and 47-55% at HARD, and
  each module moves the win rate by about 3 points either way, except SERVO WRISTS at HARD (about +8, because the bot reads
  fast attacks poorly). That only rules out a dominant or hopeless build against the bots, and a bot is not a person: HARD
  reacts in about 11 frames, and slow heavy builds look worse against something that reads than against people who do not.
  Real balance needs playtests; `Loadout` is where to adjust.

### The shop

Everything for sale is cosmetic and sold directly, never as a loot box. A premium body draws a chassis as another robot
with the same size, reach and stats; a crest only sits on the head.

| Item | What | Price |
| --- | --- | --- |
| HAYMAKER | a premium body for ANVIL: a retro prizefighter with a padded headguard, a chest dial and huge padded gloves | 499 Robux |
| BASTION | a premium body for BULWARK: a rounded fortress with turret-dome shoulders and tower-shield forearms | 499 Robux |
| SPECTRE | a premium body for LANCE: a sleek stealth fencer with an egg head, one glowing slit and lance-tipped fists | 499 Robux |
| RONIN | a premium body for RAZOR: a samurai with a horned kabuto helmet, a face mask and stacked shoulder plates | 499 Robux |
| MONARCH | a premium body for MAUL: smooth rounded champion's armor, swept pauldrons, a gold V and title belt | 499 Robux |
| CROWN | a crest: five gold points with a gem on each | 600 coins |
| MOHAWK | a crest: four swept blades with a glowing edge | 350 coins |

Coins come from matches: a 1v1 pays 40 for a win and 15 for a loss, a bot match 10, 20 or 35 for a win (EASY to HARD) and
5 for a loss; training pays nothing. The SHOP page shows the coins and a card per item: tapping a card tries the item on
(a body also picks its chassis) without changing the garage, and its button buys it (with coins, or through Roblox's
purchase prompt) or, once owned, equips and unequips it. A bought item goes on as soon as the server says it is owned. A
crest on the PAINT page that is not owned yet carries an amber mark, and picking it opens the shop wearing it.

- **The catalog.** `src/shared/Shop.luau` lists the items (an id, which wallets keep and so never changes once shipped; a
  kind; a price in coins or Robux) and the coin rewards. `Looks.Bodies` and `Looks.CrestItems` say which body or crest an
  item unlocks. A Robux item is a developer product: `.\scripts\products.ps1` creates the product for every Robux item that
  has none (`product = 0`), at its `robux` price, and writes the product ID into `Shop.luau`; it reuses a product with the
  same name, so it can be run again. It needs the key's "developer-product" API with Read and Write. An item without a
  product shows SOON and cannot be bought.
- **The wallet.** `src/server/Wallet.luau` keeps each player's coins and owned items in the DataStore `RealSteelWallet1`
  and publishes them on the player (`Coins`; `Owned`, the ids comma separated; and `WalletReady`, whether the stored wallet
  has been read). Like a record, coins are saved as additions in one `UpdateAsync`, batch-numbered per server, so a retry
  is never added twice and two servers never write over each other. A Robux purchase arrives through
  `MarketplaceService.ProcessReceipt`: it is granted inside one `UpdateAsync` that also records its PurchaseId, and Roblox
  is told the purchase went through only once that write has landed, so a receipt tried again (after a lost reply, or on
  another server) is not granted twice, a failed write is retried by Roblox later (the buyer has the item for the session
  meanwhile), and a buyer who left gets the item when they come back. Coin purchases go through the `Shop` remote (`"buy"`
  and an item id, one request per 0.5 s) and are written at once. Until the stored wallet has been read nothing is sold
  (the player might own it already): the shop shows LOADING and the read is tried again every 15 s; a Robux item paid for
  shows PENDING until its grant arrives, so it is never offered twice. The garage asks the wallet what a player owns and
  dresses them again whenever that changes. Ids the shop no longer sells stay in a wallet. Where DataStores are
  unreachable (an unpublished place, or Studio without access to API services), coins and purchases last for the session;
  test purchases in Studio are free.
- **Adding an item.** A crest: its kit in `art/kits.py`, its name and kit at the end of `Looks.Crests`, `Looks.CrestKits`
  and `Looks.CrestItems`, and the item in `Shop.Items`. A body: a frame module in `art/` (on the shared skeleton, keeping the
  chassis' reach, built from the shells in `art/shells.py`; see `art/monarch.py`) listed in `build_robot.PREMIUM`, exported
  and uploaded like the free frames (its model with `upload-robot.ps1`, its textures into `RobotWear.model.json`), then an
  entry at the end of `Looks.Bodies` and the item in `Shop.Items`, then `.\scripts\products.ps1`. `RobotSpec` checks the
  body's frame, that its strikes reach at its chassis' size, and that it is uploaded with textures for every finish;
  `LoadoutSpec` checks the catalog.

## Robot art and animation

Each chassis is drawn as its own original robot, a frame, modeled in Blender on one shared skeleton (ANVIL's joints, in
`art/skeleton.py`), so all five play the same animations, wear the same crests and are posed alike by the game.

| Frame | Chassis | Look | Meshes | Triangles |
| --- | --- | --- | --- | --- |
| ANVIL | all-rounder | a classic boxer: rounded headgear with cheek guards, a ring emblem, glove-like fists, a waistband like trunks | 56 | 10.8k |
| BULWARK | tank | a monolith: stacked slab pauldrons, a visor slit sunk in a raised collar, flared gauntlets, exhaust stacks | 62 | 14.4k |
| LANCE | poker | a lean racer: a V torso around a reactor, a single-lens wedge head, cable tendons, spear-tipped fists | 61 | 9.8k |
| RAZOR | rushdown | a sharp prize-fighter: a wedge helmet with V eye slits, blade shoulders, razor-edged forearms, heel spurs | 56 | 10.9k |
| MAUL | heavy hitter | an ex-industrial loader: a cab head with beacons and a roll bar, a grille chest, hammer fists, tread feet | 60 | 12.0k |

The premium bodies are frames too, each for one chassis and sold in the shop. They keep the chassis' size and reach, so
they play exactly like it:

| Body | For | Look | Meshes | Triangles |
| --- | --- | --- | --- | --- |
| HAYMAKER | ANVIL | a retro prizefighter: a rounded helmet in a padded headguard, round eyes over a grilled mouth, a barrel chest with a big dial, trunks with a buckled waistband, huge padded gloves with laced cuffs, high-top boots | 55 | 15.5k |
| BASTION | BULWARK | a rounded fortress: turret-dome shoulders with gun slits, a turtle-shell collar the helmet sinks into, a wide visor, rounded tower shields down the forearms, steel knuckle plates, elephant feet | 56 | 16.9k |
| SPECTRE | LANCE | a sleek stealth fencer in pearl-like armor: an egg head with one vertical glowing slit, a hard V torso around a glowing core, finned shoulders and back, forearm blades, lance-tipped fists, runner's feet | 56 | 15.6k |
| RONIN | RAZOR | a samurai in lacquered armor: a domed kabuto with a gold crescent, a dark mask with angry eye slits, a gold sash over a skirt of plates, three flared plates on each shoulder, gold-banded bracers | 47 | 16.3k |
| MONARCH | MAUL | a champion heavyweight in smooth rounded armor: domed pauldrons, a chest narrowing to the waist, a gold V around a glowing core, an angry visor, a title belt | 59 | 18.6k |

The premium bodies are built from `pod` shells (`robotlib.PartBuilder.pod`, a superellipsoid that can flare; the shared
shapes and mesh densities are in `art/shells.py`), which give the rounded look the free frames' bevelled boxes do not.

A frame has one mesh per joint per material role: Armor and Trim take the player's paint, Glow (Neon) the accent color,
Dark is the frame between the plates (so the gaps read as panel lines) and Steel is bare metal (pistons, rivets, cables,
knuckle plates). The designs are original: robot boxers in general are fair game, a film's characters are not.

```powershell
.\scripts\art.ps1                                  # every frame's textures, FBX and rig data, and the generated Luau
.\scripts\art.ps1 -Frames BULWARK                  # only BULWARK's textures and FBX (every frame still goes into RobotRigs)
.\scripts\art.ps1 -Previews frames -Engine EEVEE   # lineups and a hero shot of every frame into art\build
.\scripts\art.ps1 -Previews premium -Engine EEVEE  # each premium body beside its chassis' frame, and a hero shot
.\scripts\art.ps1 -Previews worn -Engine EEVEE     # bake the textures and render every frame wearing them
.\scripts\art.ps1 -Previews poses                  # contact sheets of the key poses
.\scripts\upload-robot.ps1 -Name Bulwark           # upload art\build\Bulwark.fbx and record the asset ID
```

- **Source:** `art/anvil.py`, `bulwark.py`, `lance.py`, `razor.py` and `maul.py` (a frame each), `haymaker.py`,
  `bastion.py`, `spectre.py`, `ronin.py` and `monarch.py` (the premium bodies) with `shells.py` (their shell shapes),
  `skeleton.py` (the shared
  joints), `greebles.py` (pistons, cables, rivets, vents), `poses.py` (poses and clips), `wear.py` (the textures),
  `kits.py` (the crests), `robotlib.py`, `exporters.py`, the `preview*.py` renderers and `build_robot.py`. Everything is
  authored in Roblox axes and studs (the robot faces -Z, right is +X).
- **Outputs:** `art/build/` (FBX, rig JSON, textures, preview PNGs; not tracked) and `src/shared/RobotRigs.luau` (every
  frame), `RobotClips.luau` and `RobotKits.luau` (generated and tracked, do not edit by hand). The FBX is exported at 0.01
  scale so one Blender unit is one stud, and the build prints each strike's reach so it can be compared with the hit range.
- **Worn metal:** `art/wear.py` unwraps each frame onto one UV atlas, bakes a beveled-edge normal map and raw signals with
  Cycles (edges and the band along them, seams, noise, how exposed each joint is), and numpy turns those into 1024 maps:
  a color map whose alpha is the paint, and a metalness and a roughness map for each finish. Paint holds on the panels and
  wears through along the edges, chipped where they take hits (most on the fists and feet), with darker steel showing
  through and grime in the seams. Wear is all or nothing (SurfaceAppearance `AlphaMode` TintMask blends the paint toward
  the near-white map wherever alpha falls short of 1, so a half-worn scuff on dark paint would read as a pale streak), and
  edges are ranked within each joint, so a rounded fist wears like a slab-sided forearm. Glow parts stay Neon.
- **Textures in the game:** `src/shared/RobotWear.model.json` holds a SurfaceAppearance per frame and finish, which
  `RobotRig` clones onto every textured part and tints with the paint. Scripts cannot set a SurfaceAppearance's maps, so
  they live in that file as image IDs: per frame one ColorMap and NormalMap shared by the four finishes, and a
  MetalnessMap and RoughnessMap per finish. After a rebuild, upload the PNGs in `art\build\textures` as images (Studio's
  Asset Manager can bulk import them) and put the new IDs in the file. The UV layout comes out the same on every build,
  so new textures fit the uploaded meshes as long as the geometry has not changed; when it has, upload the FBX again too.
- **Animation:** `RobotSkeleton` poses the rig by forward kinematics from the same joint data, and `RobotAnimator` picks a
  clip from the simulation state every render frame. Attack clips are sampled by phase (startup 0-1, active 1-2,
  recovery 2-3), so their timing follows `FightConfig` with no separate animation timing. Hits, blocks, dashes and
  knockouts are sampled by stun or frame progress, and walking blends four directional cycles by velocity relative to the
  opponent. An attack turns the robot toward the aim it locked in. The opponent is drawn mirrored (southpaw) so both chests
  turn toward the camera.
- **Upload:** `scripts/upload-robot.ps1 -Name <Frame>` sends the frame's FBX through Open Cloud and writes its asset ID
  into `src/shared/RobotAssets.luau` (a frame that has an ID gets a new version of the same asset). It needs a key with the
  Assets API (Read and Write), read like `publish.ps1` does (`$env:ROBLOX_API_KEY` or the stored key), and uploads under
  the key owner's account. Roblox loads a model only for experiences owned by the uploader or a group it is shared with.
  An ID of 0, or a model that fails to load, gives blockout robots built from the rig's part sizes, so a missing asset
  never breaks the game.
- **Loading:** the server builds the hall before anything that waits, then loads every frame's model once, all at the
  same time (`RobotLibrary`), and shares them as `ReplicatedStorage.Robots`. Players can join while the models download,
  and a character that spawned before the hall existed would fall out of the world. The folder can reach a client before
  the meshes in it, so the server marks how many frames it holds and how many meshes each has, and `RobotFrames` waits
  (up to two minutes) until they have all arrived. It then gathers each frame's rig, meshes and textures on the client,
  which clones the meshes into its own parts and moves them with `BulkMoveTo`. `RobotRig.setFrame` swaps a robot to
  another frame in place, keeping its size, crest, paint and finish. The robots are client-only visuals, so nothing about
  them replicates. Script cost on desktop Studio: about 3 microseconds to animate and 180 to solve and place one robot
  per frame.

## Tests

- **Unit checks:** `FightSimSpec` covers the fight rules, the stick mapping, all four attacks and their frame data, the
  guard bar (draining, refilling, breaking from a block or from holding, the break's length and what ends it, BULWARK's
  slower drain) and the throw (both punches and the grab button, the late second punch, catching a guard, the slam's
  damage and the frame advantage, the whiff, breaking free in time and not after, strikes beating grabs, who can and
  cannot be caught, grabs catching each other, knockouts and training) (135 checks).
  `RobotSpec` covers every frame's rig data (known roles, the shared skeleton, the rest pose, mirrored joints and left and
  right twin parts, the armor the effects aim at), a frame for every chassis, the clips, the animator (including the guard
  break, grab, throw, thrown and broken-throw clips, a robot thrown out staying down, and the grab reaching out with both
  hands), the crests (their data, symmetry and where they sit at each chassis' size) and, for every move, that the limb the
  move names reaches the hit range during the active frames on every chassis' own frame and every premium body at the
  chassis' size, that the other limb does it when the robot is drawn as a southpaw, and that every frame is uploaded and
  has its worn textures for every paint finish (152 checks).
  `BotSpec` covers the round flow (intro, clock, KO, time-up, draws, best of three, rematch, and who has won a match that
  is torn down during its last knockout), that the bot is a pure function of its inputs, that each level reads and
  punishes the way it should, that the stronger levels fire at a walker, guard coming out of a stun and punish a dash,
  that they break throws (EASY never), take apart an opponent who only guards, punish a broken guard and stop blocking
  when a block would break them, that a jab masher loses to EASY and not to HARD, that a whole bot-vs-bot match
  finishes, and that the levels are ordered (73 checks).
  `LoadoutSpec` covers the garage's data: the catalog, the codes (all 135 loadouts and every paint code survive a round
  trip, nonsense reads as the stock ANVIL), the stats each part derives, the plain-language gain and cost lines, build names,
  that the simulation, the frame data and the bot play each fighter by its own stats, that a timed-out round goes to the
  fuller health bar, the paint rules, which frame and crest a build and a look are drawn with, premium bodies (one for every
  chassis, each a frame of its own sold for Robux) and what a look keeps of the shop items its wearer does not own, and the
  shop's catalog, prices and coin rewards (156 checks).
  `QueueSpec` covers the line for the rings, on one ring and on the hall's three: a bot match starting at once, a 1v1
  pairing the two earliest 1v1 players in order, a lone 1v1 waiter not holding up the line, changing what you wait for
  keeping your place, leaving the game ending the session in your ring and no other, practice filling the pits before the
  main ring, a pair taking the main ring before earlier practice, places in line counted per kind of fight, when each
  ring's rematch is open, which training sessions get a deadline, pairs from the 1V1 pads fighting each other in seat
  order and taking their place where the later of the two stands, a partner leaving or asking for something else
  leaving the other waiting for anyone, a pair stepping onto the other pads keeping its place in the new seats, and, with
  every ring hosting 1v1s, a pair taking the main ring and the next one a pit (96 checks).
  `LayoutSpec` covers where things stand in the hall (`FoundryLayout`): the main ring is numbered first and hosts the
  exhibitions, every ring hosts 1v1s and practice (1v1s going to the main ring first), every ring's fight camera stays
  inside the walls and clear of the columns, booths stand outside their ring's rail, inside the hall and clear of the
  columns, facing their ring, pits stay clear of the molten channel, rings keep a walkway between their rails, pads, bays
  and the spawn stay out of the fights' way, the pads (a 1V1 pad for each seat, the first seat's on the west like its
  booth, a bot pad for every level and one for training) neither touch nor reach the channel, the champion's statue and
  the leaderboards stand clear of the fights, the channel, the columns and the hall's name, and every ring's winches
  leave room to lower the tallest build (134 checks).
  `PadSpec` covers the pads (`PadRules`): a pad taken by stepping on its edge, its countdown running down and cancelled by
  stepping off, a bot pad asking for its level and a training pad for training once, the pad then free for the next
  player while the first still stands there, stepping off and on counting again, the first one on keeping it, players in
  a ring holding none and players who leave forgotten, and the 1V1 pads counting down only with a different player on
  each, starting over for a new challenger and asking for a 1v1 in seat order (28 checks).
  `StandingsSpec` covers records (counting, saving, reading damaged saves, adding what was won while a save loaded), what
  a save keeps of the batches added to it (each server's latest, so a retried batch is recognized however many others
  were written since, with only so many servers kept), the champion's title (claimed, defended, taken, left alone by
  other 1v1s, vacated) and leaderboard order (47 checks).
  `HoistSpec` covers the winches (`Hoist`): how high a robot hangs and that the hook holds it by the head, that idle rings
  hang their robots, that the first round's intro drops them in time with the match in every ring and build without the
  drop outrunning the winch, landing once on the landing frame with the hooks home by the bell, that a rematch stays on
  the marks while a new robot at the start of a match is dropped in, that training lowers at once and a ring gone idle
  sends the hook down before hoisting (back up again, without a jump, for a taller robot swapped in meanwhile), and that
  a called-off drop, a match starting mid-hoist, a rollback or a long frame never makes anything jump or land twice (48
  checks).
  `FightSimSpec`, `BotSpec`, `LoadoutSpec`, `QueueSpec`, `LayoutSpec`, `PadSpec`, `StandingsSpec` and `HoistSpec` need no
  Studio, so `.\scripts\run-specs.ps1 -Luau <path to luau.exe>` runs them with the standalone interpreter (it stands in a
  small Vector3, CFrame and Vector2 for the layout). Run any of them in Studio's command bar with
  `require(game.ReplicatedStorage.Tests.BotSpec)()` (or `RobotSpec`, `FightSimSpec`, `LoadoutSpec`, `QueueSpec`,
  `LayoutSpec`, `PadSpec`, `StandingsSpec`, `HoistSpec`); it returns the pass count and failures. Clone the module first
  to avoid a cached result after edits.
- **Garage screen:** `GarageSpec` needs Studio in Edit mode, because it lays real UI out. It checks what each button does, that
  the panel sends a pick once and again until the server agrees, that quick picks go as one, that a pick the server never
  confirms is given up and a saved garage that arrives late is followed, and, on a desktop view, a phone and a tall narrow
  window, that the panel fits the view, every row of chips and swatches stays on its row, no text is cut off, every gain
  and cost of the chosen parts is listed, and the equipped preset is marked. The SHOP page: a card for every item, trying
  an item on (a body with its chassis) without sending anything, buying with Robux only when the item has a product,
  buying with coins only when there are enough, putting a bought item on once the server says it is owned, equipping and
  unequipping, the marks on the crests not owned yet and picking one opening the shop, nothing sold before the wallet is
  known, and a Robux item never prompted twice in a row or while its purchase is on its way (126 checks).
  Run `require(game.ReplicatedStorage.Tests.GarageSpec:Clone())()`; it builds its own copies of what it tests and cleans up.
- **Garage server:** `GarageServerSpec` (Studio, Edit mode, 37 checks) runs `src/server/Garage.luau` against a stand-in
  DataStore and stand-in players. It checks that a request is cleaned (out-of-range numbers, NaN, infinity, words, other
  actions, players nobody added), that one request per 0.1 s is taken, that fields a request leaves out keep their value, that
  the codes are published and every change reported, that a changed garage is saved whole, once, again after a failed write
  and when the player leaves, that a saved garage (even a damaged one) is loaded, that a pick made while the save is being
  read wins, and that a player wears only the shop items they own, and wears a kept pick as soon as they buy it. Run it
  like `GarageSpec`.
- **Wallets:** `WalletSpec` (Studio, Edit mode, 65 checks) runs `src/server/Wallet.luau` against a stand-in store that can
  fail a read or a write, or lose a reply. It checks that a stored wallet is read and cleaned, that matches pay by mode and
  level and nothing for practice, that coins are saved as additions alongside another server's, never twice after a lost
  reply and never lost after a failed write, that a payout never cancels the price of a coin purchase still waiting to be
  written, that a player paid just after leaving is saved, buying with coins (price, ownership, never below zero, never
  twice, the remote's checks and cooldown), that a Robux purchase is granted once however often its receipt comes back,
  only after its write has landed (the buyer having it for the session meanwhile), for a buyer who is not in the server
  too, and for the session without a store, and that a wallet that cannot be read sells nothing until a later read works
  (or, in Studio, lasts for the session). Run it like `GarageSpec`.
- **Records server:** `RecordsSpec` (Studio, Edit mode, 62 checks) runs `src/server/Records.luau` against stand-in record
  and board stores and stand-in players. It checks that a saved record arrives with what was won while it loaded, that
  1v1s and bot matches count (from either seat, by level) and training and exhibitions do not, that the title moves as
  the rules say and falls vacant when the champion leaves, that a record and both boards are written when a player
  leaves, a failed write is tried again and an unchanged record is not written, that a write whose reply was lost is not
  added again even after another server has written twenty times, that a result that comes in just after a player left
  still counts but gives no title to a winner who has left, that a board write that failed is tried again and a joining
  player's stored scores are put on the boards once, that a record still loading, or one that could never be read, is
  never written over the save, that the boards come from the stores or, when those cannot be read, from the server's
  players, and that reporting a result never waits on a slow store. Run it like `GarageSpec`.
- **Multiplayer checks:** open `build\REALSTEEL-checks.rbxlx`, which adds `tests/StudioChecks.*.luau` to the game, and run
  this in the command bar in Edit mode. At the end every client reports every ring: a ring that holds still by then (the
  scenario's own rings once their fights settle, and idle rings) has to match the server's in full, and a ring that is
  still fighting (the main ring's exhibition) in the commands the server gave it. Log errors from the game are counted
  apart from the engine's own.

  ```lua
  local test = game:GetService("StudioTestService")
  -- Two players queue for a 1v1 and trade a seeded mix of every action in the main ring.
  test:ExecuteMultiplayerTestAsync(2, { scenario = "pvp", duration = 20 })
  -- Two players queue for a 1v1; one takes the other through a whole match to the result screen, then asks for a rematch.
  test:ExecuteMultiplayerTestAsync(2, { scenario = "match", duration = 100 })
  -- One player sets a MAUL build in the garage, picks a bot level on the PLAY card and fights it in the first pit while the
  -- main ring's exhibition goes on, then leaves and comes back to train. The build must reach the fighter, so this match
  -- is predicted with other stats and another frame than the stock ANVIL.
  test:ExecuteMultiplayerTestAsync(1, { scenario = "bot", duration = 25, level = 2 })
  -- Two players queue for training at once and land in a pit each, while the main ring's bots fight on. Each client
  -- predicts the other player's pit from that player's inputs.
  test:ExecuteMultiplayerTestAsync(2, { scenario = "pits", duration = 20 })
  ```

- **Bot calibration:** `.\scripts\calibrate-bot.ps1 -Luau <path to luau.exe>` plays the levels against each other and against
  scripted stand-ins for a beginner, an average and a good player, and against scripted players that mash one attack, with
  the standalone Luau interpreter (100 rounds each by default, a few seconds). It needs no Studio. The interpreter is not in
  `rokit.toml`; download `luau-windows.zip` from the Luau releases page.

- **Touch layout:** `StudioDeviceSimulatorService:SetDeviceAsync("iphone_7")` (or `iphone_14`, `samsung_galaxy_a06`) in Edit
  mode, then Play. Mouse input acts as touch. Studio remembers the last device in the registry value
  `HKCU\Software\Roblox\RobloxStudio\emulationDevices\preferredDeviceId`, and `StopSimulationAsync()` alone did not reset it
  when Studio was closed abruptly, so set it back to `default` afterwards. Every touch button (attacks, guard, dash and
  the training column) was confirmed this way.
- **Network simulation:** `settings().Network` has `Inbound/OutboundNetworkMinDelayMs`, `...JitterMs` and `...LossPercent`.
  They apply to the multiplayer test too. Reset them to 0 afterwards; they are Studio settings, not per place.
- The Studio MCP key injection can lag several seconds when the Studio window is in the background, so precise scenarios
  drive the Scriptable bindings instead. Real key and mouse injection was confirmed for every binding.

## Netcode results

Single player against a server-fed bot that changes input every 0.25-0.6 s as a stand-in for a remote player, 30 s
windows driving every action. Pop counts are replayed offline at a steady 60 FPS.

| Condition | Rollbacks/s | Resim steps per rollback | Opponent pops over 1 stud (raw, smoothed) | Largest opponent pop (raw, smoothed) |
| --- | --- | --- | --- | --- |
| 160 ms round trip, predictable opponent | 0 | | | |
| 160 ms round trip | 3.5 | 11.3 | 24, 0 | 3.0, 0.8 |
| 320 ms round trip, 0.5% loss | 3.4 | 22.2 | 41, 0 | 4.0, 1.0 |

Two real clients (`StudioTestService`, 20 s of play plus settling, both players acting constantly):

| Condition | Rollbacks per client | Resim steps per rollback | Result |
| --- | --- | --- | --- |
| About 0 ms | 167 and 251 | 5.1 and 3.8 | passed, both clients matched the server |
| 160 ms round trip | 213 and 247 | 14.0 and 12.3 | passed, both clients matched the server |
| About 0 ms, with the articulated robots | 154 and 241 | 4.4 and 2.6 | passed, both clients matched the server |
| 160 ms round trip, with the articulated robots | 226 and 256 | 13.5 and 13.4 | passed, both clients matched the server |
| About 0 ms, all four attacks | 148 and 208 | 4.9 and 4.3 | passed, every attack thrown, both clients matched the server |
| 160 ms round trip, all four attacks | 118 and 149 | 15.0 and 15.1 | passed, every attack thrown, both clients matched the server |
| About 0 ms, with the arena, stage lights, effects and HUD | 149 and 214 | 3.0 and 3.1 | passed, every attack thrown, both clients matched the server |
| 160 ms round trip, with the arena, stage lights, effects and HUD | 183 and 218 | 14.0 and 14.0 | passed, every attack thrown, both clients matched the server |
| About 0 ms, with rounds, the bot code and the faster timings | 164 and 240 | 3.2 and 3.1 | passed, every attack thrown, both clients matched the server |
| 160 ms round trip, same build | 185 and 227 | 12.9 and 13.4 | passed, every attack thrown, both clients matched the server |
| 160 ms round trip, a whole match to the result screen and a rematch | 5 and 123 | 13.8 and 13.0 | passed, two rounds, a KO, the result screen, the rematch started clean |
| 160 ms round trip, one player against the MEDIUM bot | 6 | 14.0 | passed, no log errors, the client matched the server |

The bot is the predictable opponent in practice: it is a pure function of the fighters' states, computed inside the simulation by
every peer, so at 160 ms a bot match rolled back 6 times in 25 seconds, where a human opponent caused about 200 in 20 seconds.
That makes it the smoothest mode for a player with a high ping. With a predictable opponent your own actions never visibly correct. After each run, with everyone idle, every state
attribute on both fighters and the match core was identical on the server and on each client, and there were no log
errors from the game. Roblox's own scripts (the CoreGui player list and the start-up script) sometimes log errors in
unpublished test places (for example `Invalid value for enum CreatorType`) on one of the clients. The check reports every
message with a `[Roblox][` prefix apart as `engineErrors` instead of failing on them.

Not covered yet: touching the stick and a button at the same time (mouse injection is a single pointer), gamepad
(Studio's key injection sends the gamepad buttons as keyboard events, which the gamepad bindings ignore, so it needs a
real controller), real-device performance, and the one or two predicted hits per 30 seconds that the server later retracts.

## Next steps

1. Play it. The bot levels were calibrated against scripted stand-ins, the sounds were chosen without being heard, and the
   timings were tightened by feel from the numbers; all of that needs a human. Adjust `BotBrain.Levels`, the `Sfx` volumes
   and `FightConfig` as it feels.
2. Try it on a phone and with a friend on the published test place. Check that the robots read well on a small screen and run
   well on a real device (about 100 anchored mesh parts move every frame in each ring, three rings' robots are drawn at
   once, up to eight robots idle in the bays, and the hall is about 1,700 parts and 33 lights under Future lighting). If a
   phone struggles, the bay robots are the first thing to thin out (`ANIMATE_RADIUS` and `OTHERS_PER_FRAME` in
   `Bays.luau`), then the robots in rings the player is far from.
3. Decide the roster theme and the game's original name (do not use Tekken or Real Steel names, characters or moves). The
   five chassis (ANVIL, BULWARK, LANCE, RAZOR, MAUL), the modules and the presets are original names and placeholders until
   then. Look at the garage on a real screen first: the panel has only been checked by measurement (`GarageSpec`), not by
   eye.
4. Progression, which is what brings people back. The garage is built for it: gameplay parts are sidegrades open to
   everyone. The shop and its coins exist now (see The shop): a premium body for every chassis and two coin crests. Next:
   more premium bodies, liveries and finishes, hit effects and victory emotes for Robux and for coins,
   mastery with a chassis, ranked play with ratings, and a daily challenge that hands out a limited look. Robux items stay
   cosmetic and are sold directly, never as loot boxes. Try a test purchase in Studio on the published place (free there):
   the local checks place is not tied to the experience, so Roblox will not prompt a purchase in it.
5. Add a launcher and juggle rules, wall interactions, and crouching or airborne states (the sim has no hit height yet, so
   there are no lows or overheads; the guard bar and the throw are what keep a guard honest for now). Tune the guard bar
   and the throw by playing: `FightConfig.Guard` and `FightConfig.Throw`. Each new move needs a clip in `art/poses.py`;
   `RobotSpec` fails until the clip exists and its striking hand reaches the hit range.
6. Try the pads with two people on the published place: the 1V1 countdown, the pair going to a pit while the main ring
   is busy, and walking away from a pad once its countdown has run out. The multiplayer checks in `StudioChecks` still
   queue through the PLAY card, not the pads.
7. Art: a hand-polished animation pass (the five frames share ANVIL's clips), module visuals designed for each frame, and
   custom sound design in place of the stock effects.