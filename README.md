# Dribble Coach

An iPhone app that coaches a kid through a 30-second dribbling drill. It counts bounces from the sound of the ball, speaks short cues, and ends with a score out of 100. Everything runs on the phone; nothing is sent anywhere. This is a family app for now, run from Xcode.

The full design is in [docs/v1-spec.md](docs/v1-spec.md); the plan below is its summary. This branch covers milestones M0, M1 and M2.

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
| M2, body tracking | Camera, body pose, debug skeleton, frame-rate fallback, placement check with spoken fixes | Placement passes within 10 s for two kids; 60 fps holds on iPhone 13 Pro or later | Done on this branch, needs a build on a Mac and the kid check |
| M3, fusion and metrics | Wrist matching, eyes up, switching, low, full score | Hand and low targets met on home clips | Next |
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

- **M0, skeleton app:** Home (streak, last drill, Start), drill picker (crossover, right-hand pound, left-hand pound), drill screen, summary, history, and settings (player name, Home or Gym, coach voice, delete all data, hidden debug mode). Tuning numbers load from `DribbleCoach/Resources/DribbleConfig.json` over the defaults in code.
- **M1, bounce counter:** the microphone feeds an onset detector that finds ball thumps in 5 ms steps. The drill screen shows the live count, a beat light that flashes on each bounce, and the time left. Drills of 10 or more bounces are saved and feed the streak.
- **M2, body tracking:** the front camera runs at 1080p and 60 fps where the phone allows. Apple Vision finds bodies in each frame. The app keeps the largest one and follows it by the hips, drops joints below 0.3 confidence, and smooths each joint with a One Euro filter. Distances are measured in torso lengths. If Vision averages more than 16 ms a frame for 2 seconds, the camera drops to 30 fps for the rest of the session. Camera frames and sound are timed on the same host clock, ready for M3 to match bounces to wrists.
- **Placement check:** before each drill, the camera picture fills the screen with an outline to stand in and a checklist (body, distance, center, feet, sound). The app speaks one fix at a time, in the spec's order: "Step back", "Come closer", "Move left", "Move right", "I can't see your feet", plus "Stand in front of me" when nobody is in view. Left and right are the kid's own. Once every check holds for a second, it locks exposure and white balance and asks for 3 bounces. If the kid walks off during the sound check, it goes back to placing them.
- **Spoken lines:** "Bounce the ball 3 times", the countdown, "Ten seconds!", "Keep dribbling!" after 3 quiet seconds, and the score at the end. Sound heard while the coach is talking is ignored.

## Not in this branch yet

- Dribble height and eyes up (M3), and with them the 0 to 100 score. Until then the summary does not show a score: it leads with the bounce count, stars for beating your own last drill (one for finishing, two for matching or beating last time, three for a new best), hand switches (or target-hand bounces on the pound drills), lost balls and one tip. The old rhythm-based score is still computed and saved, and shown in Debug mode as the internal score.
- The live coach cues such as "Lower!" and "Switch hands!", and pausing when the kid leaves the frame (M4). Debug video recordings and the replay harness (M5).

## Build and run

You need a Mac with Xcode 15 or later, an iPhone 12 or later on iOS 17 or later, and XcodeGen.

```bash
brew install xcodegen
./Scripts/bootstrap.sh
```

That generates `DribbleCoach.xcodeproj` and opens it. In Xcode, pick your team under Signing & Capabilities for the DribbleCoach target, plug in the iPhone, choose it as the run destination, and press Run. The first run asks for the microphone and the camera.

The project file is generated, so it isn't committed. Run `xcodegen generate` again after adding or moving files.

## Run the tests

The counting and scoring logic lives in a Swift package with its own tests, so it runs without a phone:

```bash
cd Packages/DribbleCore
swift test
```

The tests cover:

- the onset detector on made-up signals: steady thumps, fast dribbling, close double thumps, a shout, a quiet room
- rhythm and lost balls, the score and stars, the streak, and config overrides
- for body tracking: the One Euro filter, choosing and following the player, torso scale, the 60 to 30 fps fallback, and every placement fix with its timing

The package builds on Linux too, with the Swift toolchain from swift.org.

## Try it

1. Put the phone upright on a stand or against a wall, screen facing you, on a hard floor, about 2.5 to 3 m from where you'll dribble.
2. Start and pick Crossover. Follow the spoken fixes until the outline turns faint, bounce 3 times, and dribble when it says go.
3. To see what the app sees and hears, open Settings and tap the version number 5 times to turn on Debug mode. Then:
   - The placement screen draws the tracked skeleton, with the left wrist blue and the right wrist red. It shows the camera and tracking frame rates, Vision time per frame, body height and how far off center you are, plus buttons to skip either check.
   - The drill screen adds a small camera view with the skeleton, the mic level, live speed and rhythm, ignored sounds and the last onset.
   - Every raw pose frame is written to `Documents/PoseLogs` as JSON lines. Copy the files off with the Files app or Finder.

### First run on a phone

Things only a real phone can show; check these first:

- **Orientation and mirroring:** with Debug mode on, stand facing the phone and raise your left hand. The blue dot should be on your raised hand and on the left of the screen, and the debug text should say "Orientation: OK". If not, change `PoseService.uprightOrientation`.
- **Bounces still count with the camera on:** the camera is set not to touch the audio session. If counting gets worse than in M1, that's the first place to look.
- **Frame rate:** on an iPhone 13 Pro or later, the debug text should show about 60 fps tracking with Vision under 16 ms.

## Tuning

Change values in `DribbleCoach/Resources/DribbleConfig.json` and rebuild. Any key from `DribbleConfig.swift` can go there; keys you leave out keep their defaults. The ones most likely to need adjusting on real floors:

| Key | Default | Raise it if | Lower it if |
| --- | --- | --- | --- |
| `thresholdFactor` | 5 | Background noise counts as bounces | Real bounces are missed in a noisy room |
| `absoluteFloor` | 0.00001 | Quiet taps count | Soft bounces (wood, far from the phone) are missed |
| `refractorySeconds` | 0.12 | One bounce counts twice | Very fast dribbles are merged |
| `voiceRatio` | 1.0 | Bounces get ignored as voice | Shouts still count as bounces |
| `pose.minConfidence` | 0.3 | Joints jump around or land on the wrong spot | Joints keep dropping out (`pose.jointMinConfidence` sets it per joint, such as `{"leftWrist": 0.2}`) |
| `pose.smoothingMinCutoff` | 1.7 | The skeleton lags a still kid | A still kid's joints shake |
| `pose.smoothingBeta` | 3.0 | Wrists lag behind fast dribbles | Fast-moving joints shake |
| `pose.fallbackAverageSeconds` | 0.016 | A phone drops to 30 fps when it doesn't need to | A phone stays at 60 fps but skips frames |
| `placement.minBodyHeightFraction` | 0.45 | Kids standing too far away still pass | Kids get told "Come closer" at the right spot |
| `placement.maxBodyHeightFraction` | 0.85 | Kids get told "Step back" at the right spot | Kids too close still pass |
| `placement.centerTolerance` | 0.15 | Kids get told to move when nearly centered | Kids off to one side still pass |

Nested keys go inside their group in the JSON, for example `"placement": {"centerTolerance": 0.2}`.

The spec's fallback rule is 25 ms a frame, but 60 fps only leaves 16.7 ms. A phone averaging 20 ms would skip frames and never fall back, so the default is 16 ms.

## M2 exit check

From the spec: placement passes within 10 seconds for two kids who follow the spoken fixes, and 60 fps holds on an iPhone 13 Pro or later. Time each kid from the first spoken fix to "Bounce the ball 3 times", and watch the tracking frame rate in Debug mode through a whole drill.

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
  Services/CaptureService.swift     Front camera, frame times on the host clock, exposure lock
  Services/PoseService.swift        Vision body pose, tracking, frame-rate fallback
  Services/PoseLogger.swift         Debug-mode pose log
  Services/SessionController.swift  The drill state machine
  Views/                            Home, placement and drill flow, camera preview and skeleton, summary, history, settings
  Resources/DribbleConfig.json      Tuning overrides
Packages/DribbleCore/               Pure Swift logic and its tests
  Sources/DribbleCore/              OnsetDetector, Rhythm, Scoring, BounceCounter, Streak, DribbleConfig,
                                    Pose, OneEuroFilter, BodyTracker, FrameRateGovernor, Placement
Scripts/bootstrap.sh                Generates and opens the Xcode project
docs/v1-spec.md                     The full v1 spec
```
