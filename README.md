# Dribble Coach

An iPhone app that coaches a kid through a 30-second dribbling drill. It counts bounces from the sound of the ball, speaks short cues, and ends with a score out of 100. Everything runs on the phone; nothing is sent anywhere. This is a family app for now, run from Xcode.

The full design is in the "Dribble coach v1 spec" doc; the plan below is its summary. This branch covers milestones M0 and M1.

## The plan

Dribble Coach is a family app for now, built and run from Xcode. v1 coaches one kid, about 6 to 12, through a 30-second stationary crossover drill. The phone stands upright on the floor 2.5 to 3 m away, and the kid never touches the screen.

### Goals for v1

- A kid sets the phone down, steps back and finishes a drill without an adult's help.
- The bounce count is within 5 percent of the truth on a hard floor at home.
- Fewer than 1 wrong spoken cue per drill.
- The score rewards form (even beat, switching hands, staying low, eyes up) more than raw speed.

Not in v1: other moves, ball tracking from video, shooting or moving drills, accounts, cloud sync, leaderboards, Android, iPad and the App Store.

### How it works

Three inputs meet on one clock, the phone's host time:

1. **Sound:** the microphone at 48 kHz, checked every 5 ms. A sharp, low thump (about 60 to 500 Hz) louder than 5 times the last second's median becomes a candidate bounce. Sounds that are mostly above 1 kHz are tagged as voice.
2. **Body:** the front camera at 60 fps (30 on older phones) through Apple Vision body pose, smoothed with a One Euro filter and scaled by torso length.
3. **Fusion:** each bounce is matched to the wrist that pushed down in the 250 ms before it. That gives the hand and how high the hand rose. At the gym, a bounce only counts with a wrist push, which filters out other balls.

Eyes up comes from the nose's position against the line between the ears, compared with a baseline taken during "Look at me" in the countdown.

### Score

| Part | Weight | How it's scored |
| --- | --- | --- |
| Rhythm | 35% | Spread of the gaps between bounces: 100 when perfectly even, 0 at a spread of 0.35 |
| Switching (crossover) or correct hand (pound) | 25% | Share of bounces where the hand switched, or used the target hand |
| Low | 25% | Full credit at half hip height or below, falling to 0 well above the hip |
| Eyes up | 15% | 100 when eyes are up 90 percent of the time, 0 at 20 percent |

Each lost ball (a gap over 1.5 s) takes 3 points off, up to 15. Stars come at 85, 65 and 40. A drill with fewer than 10 bounces gets "Let's try that again" and no score. A part without enough data is dropped and its weight shared among the rest. All of these numbers are in the config file.

### Coach

Every second the coach looks at the last 5 seconds and says at most one short cue, such as "Keep dribbling!", "Lower!", "Switch hands!" or "Eyes up!". It stays quiet for the first 4 seconds, waits at least 4 seconds between cues, and gives praise when nothing needs fixing.

### Milestones

| Milestone | What it adds | Exit check | Status |
| --- | --- | --- | --- |
| M0, skeleton app | Xcode project, all screens, config loading | Every screen reachable | Done on this branch, needs a first build on a Mac |
| M1, bounce counter | Microphone onset detector, live count and rhythm | Count within 5 percent on concrete and wood across 5 home drills | Done on this branch, needs the home check |
| M2, body tracking | Camera, body pose, debug skeleton, frame-rate fallback, placement check with spoken fixes | Placement passes within 10 s for two kids; 60 fps holds on iPhone 13 Pro or later | Next |
| M3, fusion and metrics | Wrist matching, eyes up, switching, low, full score | Hand and low targets met on home clips | Planned |
| M4, drill and coach | Live cues, interruptions, comparing the two audio modes | Fewer than 1 wrong cue per drill | Planned |
| M5, debug recorder and replay | Recordings, file replay, Python matcher, replay tests | All 15 clips labeled and in the test suite | Planned |
| M6, kid test | Two weeks of real use at home, rewording and tuning | Kids finish without help and ask to go again | Planned |

### Testing

Unit tests cover the onset detector, fusion, every metric, the score, the coach rules and the streak. For field testing, about 15 drills of 30 seconds (5 each in a garage, a driveway and a gym, with at least two kids) are filmed in 240 fps slow motion on a second iPhone, labeled bounce by bounce, and replayed through the app. v1 targets:

| Measure | Target |
| --- | --- |
| Bounce count error per drill, home | 5 percent or less |
| Bounces found within 50 ms, home | 95 percent or more |
| False bounces per drill, gym | 2 or fewer |
| Hand correct, among bounces given a hand | 90 percent or more |
| Bounces given a hand at all | 80 percent or more |
| Low call agrees with label | 85 percent or more |
| Wrong cues per drill | Fewer than 1 |

If the hand target is missed, a small Core ML ball detector trained on these clips is the fallback. If the gym target is missed, a Create ML sound classifier is.

### Open questions

- Portrait or landscape, decided after M2.
- Built-in voice or recorded clips for the coach.
- Whether the pound drills ship in v1 or stay as test drills.

## What works in this branch

- **M0, skeleton app:** Home (streak, last score, Start), drill picker (crossover, right-hand pound, left-hand pound), drill screen, summary, history, and settings (player name, Home or Gym, coach voice, delete all data, hidden debug mode). Tuning numbers load from `DribbleCoach/Resources/DribbleConfig.json` over the defaults in code.
- **M1, bounce counter:** the microphone feeds an onset detector that finds ball thumps in 5 ms steps. The drill screen shows the live count, a beat light that flashes on each bounce, and the time left. The summary shows bounces, speed, lost balls and a rhythm score. Drills with a score are saved and feed the streak.
- **Spoken lines:** "Bounce the ball 3 times", the countdown, "Ten seconds!", "Keep dribbling!" after 3 quiet seconds, and the score at the end. Sound heard while the coach is talking is ignored.

## Not in this branch yet

- Camera, body tracking and the placement check (M2). For now the drill starts with a sound check: bounce 3 times.
- Hand switching, dribble height and eyes up (M3). Until then the score is the rhythm score minus lost-ball points, and the other three bars say "Coming with body tracking".
- The live coach cues such as "Lower!" and "Switch hands!" (M4), debug recordings and the replay harness (M5).

## Build and run

You need a Mac with Xcode 15 or later, an iPhone 12 or later on iOS 17 or later, and XcodeGen.

```bash
brew install xcodegen
./Scripts/bootstrap.sh
```

That generates `DribbleCoach.xcodeproj` and opens it. In Xcode, pick your team under Signing & Capabilities for the DribbleCoach target, plug in the iPhone, choose it as the run destination, and press Run. The first run asks for the microphone.

The project file is generated, so it isn't committed. Run `xcodegen generate` again after adding or moving files.

## Run the tests

The counting and scoring logic lives in a Swift package with its own tests, so it runs without a phone:

```bash
cd Packages/DribbleCore
swift test
```

The tests cover the onset detector on made-up signals (steady thumps, fast dribbling, close double thumps, a shout, a quiet room), rhythm and lost balls, the score and stars, the streak, and config overrides.

## Try it

1. Put the phone upright on a stand or against a wall, screen facing you, on a hard floor.
2. Start, pick Crossover, bounce 3 times, and dribble when it says go.
3. To see what the detector hears, open Settings and tap the version number 5 times to turn on Debug mode. The drill screen then shows the mic level, live speed and rhythm, how many sounds were ignored, and the energy of the last onset.

## Tuning

Change values in `DribbleCoach/Resources/DribbleConfig.json` and rebuild. Any key from `DribbleConfig.swift` can go there; keys you leave out keep their defaults. The ones most likely to need adjusting on real floors:

| Key | Default | Raise it if | Lower it if |
| --- | --- | --- | --- |
| `thresholdFactor` | 5 | Background noise counts as bounces | Real bounces are missed in a noisy room |
| `absoluteFloor` | 0.00001 | Quiet taps count | Soft bounces (wood, far from the phone) are missed |
| `refractorySeconds` | 0.12 | One bounce counts twice | Very fast dribbles are merged |
| `voiceRatio` | 1.0 | Bounces get ignored as voice | Shouts still count as bounces |

## M1 exit check

From the spec: the bounce count is within 5 percent of the truth on concrete and wood across 5 home drills. Count the bounces by hand from a slow-motion video of each drill and compare with the app's number.

## Layout

```
project.yml                         XcodeGen spec for the app
DribbleCoach/                       The iOS app (SwiftUI, SwiftData)
  DribbleCoachApp.swift
  Model/Models.swift                Drill, Place, DrillResult, SessionRecord
  Services/AudioService.swift       Microphone tap and onset detection
  Services/SpeechService.swift      Spoken lines
  Services/SessionController.swift  The drill state machine
  Views/                            Home, drill flow, summary, history, settings
  Resources/DribbleConfig.json      Tuning overrides
Packages/DribbleCore/               Pure Swift logic and its tests
  Sources/DribbleCore/              OnsetDetector, Rhythm, Scoring, BounceCounter, Streak, DribbleConfig
Scripts/bootstrap.sh                Generates and opens the Xcode project
```
