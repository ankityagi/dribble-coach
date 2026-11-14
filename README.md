# Dribble Coach

An iPhone app that coaches a kid through a 30-second dribbling drill. It counts bounces from the sound of the ball, speaks short cues, and ends with a score out of 100. Everything runs on the phone; nothing is sent anywhere. This is a family app for now, run from Xcode.

The full design is in the "Dribble coach v1 spec" doc. This branch covers milestones M0 and M1.

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
