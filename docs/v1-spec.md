# Dribble coach v1 spec

> Copied from the "Dribble coach v1 spec" Claude Doc on 2026-11-19. The README's plan section is a summary of this file.

2026-11-14 · Ankit Tyagi

v1 is an iPhone app that coaches one kid through a 30-second stationary crossover drill. It counts bounces from sound, reads hands, dribble height and head position from Apple Vision body tracking, speaks one cue at a time, and ends with a score out of 100. Everything runs on the phone, with no account and no network. This spec builds on the Dribble coach first prototype plan, and every number marked tunable lives in one config file so it can be set from real clips.

## Goals and non-goals

**Goals**

- A kid aged about 6 to 12 can set the phone down, step back and finish a drill without an adult touching the screen.
- Bounce count within 5 percent of the truth on a hard floor at home.
- Spoken cues that are right often enough that kids follow them: fewer than 1 wrong cue per drill.
- A score that rewards form (even beat, switching hands, staying low, eyes up) more than raw speed.

**Non-goals for v1**

- Moves other than crossover and one-hand pound dribbles.
- Ball tracking from video, shooting, or moving drills.
- Accounts, cloud sync, leaderboards, multiple players on one phone, Android, iPad layout.
- App Store release. v1 is for testing at home through Xcode or TestFlight.

## Users and setup

- **Player:** a kid of about 6 to 12 with basic dribbling. Reads little, so everything they need is spoken or shown as a big number or picture.
- **Parent:** opens the app, picks the drill, places the phone, and looks at scores afterwards.
- **Device:** iPhone 12 or later on iOS 17 or later. 60 fps tracking on iPhone 13 Pro or later; other phones drop to 30 fps automatically.
- **Placement:** phone upright (portrait) on a stand or leaning against a wall at about chest height of a seated adult, front camera facing the kid, 2.5 to 3 m away, hard floor, kid facing the camera straight on.

## Screens

| Screen | What it shows | Actions |
|---|---|---|
| Home | Today's streak, last score, big Start button | Start, History, Settings |
| Drill picker | Crossover (main), Right-hand pound, Left-hand pound, each with a short looping demo animation | Pick a drill |
| Placement check | Live camera with a body outline to stand in, a checklist (whole body visible, centered, right distance, sound check) | Auto-advances when all checks pass; Back |
| Countdown | "Look at me" prompt, then 3, 2, 1, go, spoken and shown big | Cancel |
| Drill | Big bounce count, a timer ring, a beat light that flashes on each bounce, the current cue as large text | Stop (top corner, small, so kids don't hit it) |
| Summary | Score out of 100, 1 to 3 stars, four bars (Rhythm, Switching, Low, Eyes up), bounce count and speed, one tip for next time, streak | Again, Done |
| History | List of past drills by day with score and drill name; tap for that summary | Back |
| Settings | Player first name (optional, used in cues), Place (Home or Gym), Coach voice on or off, Delete all data, hidden Debug mode (tap the version number 5 times) | Toggle, Delete |
| Debug overlay | Skeleton on the video, sound level with onset marks, live event log, current fps and processing time, Record toggle | Record, Share last recording |

## Flow

1. Home, then Start, then the drill picker.
2. Placement check runs until every check holds for 1 second. The app speaks fixes in order: "Step back", "Come closer", "Move left", "Move right", "I can't see your feet". Then "Bounce the ball 3 times" for the sound check.
3. Countdown. During "Look at me" the app records the kid's head-up position as their baseline.
4. Drill runs 30 seconds (tunable). Spoken "Ten seconds!" at 20 seconds and "Stop!" at 30.
5. Summary appears and the score is spoken: "78! Three stars. Next time, stay lower."
6. Again goes straight back to the countdown, skipping placement if the kid is still in place.

**Interruptions**

- Kid out of frame for more than 2 seconds: pause, speak "Come back to your spot", resume on return with the timer held. Out for more than 15 seconds: end the drill without a score.
- No bounce heard for 3 seconds during the drill: speak "Keep dribbling!" once.
- Phone call, app sent to the background, or the phone gets hot (thermal state serious): end the drill without a score and show why.

## User stories and acceptance criteria

1. **As a parent, I can start a drill in 3 taps.** Home to the drill running takes at most 3 taps plus the automatic placement check.
2. **As a kid, I'm told how to stand without reading.** Placement problems are spoken; the check passes within 10 seconds when the kid follows the cues.
3. **As a kid, I hear what to fix while I dribble.** One cue at a time, at least 4 seconds apart, never the same cue twice within 10 seconds.
4. **As a kid, I see my count go up with every bounce.** The count updates within 150 ms of the bounce.
5. **As a kid, I get a score and stars at the end.** The summary appears within 1 second of "Stop!".
6. **As a parent, I can see progress over days.** History lists every scored drill; the streak counts consecutive local days with at least one scored drill.
7. **As the builder, I can record a drill and check accuracy offline.** Debug mode saves video, audio and every detected event, and shares them to Files or AirDrop.
8. **As a parent, I know nothing leaves the phone.** The app makes no network calls; video is kept only in Debug mode; Delete all data removes sessions and recordings.

## Detection pipeline

Three inputs run in parallel and meet on one clock (the phone's host time, in seconds).

1. **Sound:** microphone at 48 kHz, analysed in 5 ms steps. Each loud, sharp onset becomes a candidate bounce with its time.
2. **Body:** front camera frames, 1080p, 60 fps (30 on older phones), run through Apple Vision body pose. Each frame gives smoothed positions for the 13 joints v1 uses.
3. **Fusion:** each candidate bounce is matched to the wrist that pushed the ball down just before it. A matched candidate becomes a bounce event with a hand and a height.

### Sound: bounce onsets

- **Audio session:** play-and-record, sound to the main speaker, I/O buffer about 5 ms. Two modes to compare in testing: echo cancellation on with automatic gain off, or plain measurement mode with bounces ignored while the coach is speaking. Ship the one that scores better on the test clips.
- **Detector:** per 5 ms step, compute energy in a low band (about 60 to 500 Hz, tunable) where a ball thump sits. A step is an onset when its energy exceeds both an absolute floor and a rolling median of the last 1 second times a factor k (start k = 5, tunable).
- **Refractory gap:** ignore onsets within 120 ms of the previous one (tunable). That allows up to about 8 bounces a second, well above a kid's pace.
- **Voice rejection:** kids shout and cues talk. An onset whose energy above 1 kHz outweighs its low band (ratio tunable) is tagged likely voice and needs a wrist match to count.
- **Output:** an onset with time, low-band energy and the voice ratio.

### Body: joints and smoothing

- **Request:** Vision body pose on each frame, on a processing queue that drops late frames so the UI never stalls.
- **Joints used:** nose, both eyes, both ears, neck, both shoulders, root (hip center), both hips, both knees, both ankles, both wrists. A joint below 0.3 confidence (tunable per joint; wrists may need lower) counts as missing.
- **Smoothing:** a One Euro filter per joint, which smooths jitter while keeping fast wrist moves sharp.
- **Body scale:** every distance is divided by torso length (neck to root), so the numbers mean the same for a small kid far away and a tall kid up close. Vision's y axis points up; v1 keeps that convention throughout.
- **Subject:** if several bodies show up, track the largest and follow it by its root position.
- **Frame-rate fallback:** if average processing time per frame passes 25 ms over 2 seconds, switch to 30 fps for the rest of the session.

### Fusion: turning sounds into bounces

- For each onset at time t, look at both wrists in the window from t minus 250 ms to t (tunable). That's the stretch where the hand pushes and the ball falls.
- Each wrist's push strength is its fastest downward speed in that window, in torso lengths per second.
- **Hand:** the wrist with the stronger push, if it beats the other by a ratio of at least 1.3 (tunable). Otherwise the hand is unknown.
- **Accept rule, Home place:** accept every onset that isn't likely voice; attach a hand when one is found.
- **Accept rule, Gym place:** accept an onset only if a wrist push of at least a minimum speed (tunable) is found. This rejects other balls on the court.
- **While the coach speaks** (plus 150 ms after), accept onsets only with a wrist match.
- **Lost ball:** a gap of more than 1.5 seconds between accepted bounces counts as a lost ball, breaks the current streak, and is left out of rhythm.

### Bounce event

| Field | Meaning |
|---|---|
| time | Host time of the onset, seconds |
| hand | left, right or unknown |
| pushSpeed | Winning wrist's downward speed, torso lengths per second |
| heightRatio | How high that wrist rose before the push: 0 at knee height, 1 at hip height, from the wrist's highest point since the previous bounce |
| source | sound plus wrist, or sound only |
| voiceLikely | true or false |

### Head: eyes up

- **Measure:** how far the nose sits above or below the line between the ears, divided by the distance between the ears. If an ear is missing, use the eyes instead.
- **Baseline:** the average of that measure during "Look at me" in the countdown.
- **Eyes up:** a frame counts as eyes up when the measure is within a margin of the baseline (tunable). Looking down at the ball drops the nose below the ear line.
- Frames where the head joints are missing don't count either way.

## Metrics and score

All metrics are computed for the full drill at the end, and over a rolling 5-second window every second for the coach.

| Metric | Definition | Part score, 0 to 100 |
|---|---|---|
| Count | Accepted bounces | Shown, not scored |
| Speed | Bounces per second of active time | Shown, not scored |
| Rhythm | Spread of the gaps between bounces: standard deviation divided by mean (lost-ball gaps left out) | 100 at a spread of 0, falling in a straight line to 0 at a spread of 0.35 (tunable) |
| Switching, crossover drill | Share of back-to-back bounces with known hands where the hand changed | That share times 100 |
| Correct hand, pound drills | Share of bounces with a known hand that used the target hand | That share times 100 |
| Low | Per bounce: 1 at heightRatio 0.5 or below, falling to 0.6 at 1.0 (hip), to 0 at 1.4 or above; averaged | That average times 100 |
| Eyes up | Share of drill frames counted as eyes up | 100 at 90 percent or more, falling in a straight line to 0 at 20 percent |
| Lost balls | Gaps over 1.5 seconds | Shown; each one takes 3 points off the total, at most 15 |

**Total score** = 35% Rhythm + 25% Switching (or Correct hand) + 25% Low + 15% Eyes up, minus the lost-ball penalty, rounded and kept between 0 and 100. Weights are in the config.

**Stars:** 3 at 85 or more, 2 at 65 or more, 1 at 40 or more, otherwise 0 with "Good try!".

**Too little data:** fewer than 10 accepted bounces ends with "Let's try that again" and no score. A part with too few samples (fewer than 6 bounces with a known hand, or under 30 percent of frames with head joints) is dropped and its weight shared among the others.

**Tip for next time:** the part with the lowest score, phrased as in the cue table.

## Coach

Every second the coach looks at the last 5 seconds and picks at most one cue.

**Rules**

- Silent for the first 4 seconds of the drill.
- At least 4 seconds between any two cues, and 10 seconds before the same cue repeats.
- Pick the cue whose metric is furthest below its threshold. Ties go by the order in the table.
- If nothing is below threshold and no cue has played for 8 seconds, play praise.
- Timer calls ("Ten seconds!", "Stop!") always play and reset the gap.
- Keep every phrase to 1 to 4 words. If a player name is set, use it in praise only.

| Order | When (last 5 seconds) | Cue | Tip on the summary |
|---|---|---|---|
| 1 | No bounce for 3 seconds | Keep dribbling! | Keep the ball moving the whole time. |
| 2 | Low under 50 | Lower! | Stay low, below your waist. |
| 3 | Switching under 60 (crossover) | Switch hands! | Cross it over every bounce. |
| 4 | Correct hand under 70 (pound) | Use your right hand! / Use your left hand! | Stick with one hand. |
| 5 | Rhythm under 55 | Keep the beat! | Keep an even beat, like a drum. |
| 6 | Eyes up under 50 | Eyes up! | Look up, not at the ball. |
| 7 | All fine for 8 seconds | Nice! / Great job, (player name)! | — |

Thresholds are in the config. Speech uses the phone's built-in voice at a slightly slow rate; recorded clips can replace it later without changing the rules.

## Architecture

One SwiftUI app, Swift on iOS 17 or later, no third-party packages in v1.

| Module | Job |
|---|---|
| SessionController | The state machine (idle, placement, countdown, drill, paused, summary, ended early). Observable by the UI. |
| CaptureService | Front camera, 1080p, 60 fps where supported, portrait, mirrored for display. Locks exposure and white balance once placement passes. Has a live source and a file source so recorded clips can be replayed through the same pipeline. |
| AudioService | Microphone tap, the onset detector, and the audio session modes. Hands onsets from the real-time audio thread to an analysis queue through a small lock-free buffer. |
| PoseService | Vision body pose per frame, joint smoothing, body scale, subject choice, frame-rate fallback. |
| Clock | Converts camera frame times and audio buffer times to host seconds, with a fixed offset measured once from a sync clip. |
| FusionEngine | Onsets plus joints into bounce events, using the accept rules for Home or Gym. |
| HeadTracker | Baseline and eyes-up per frame. |
| MetricsEngine | Rolling 5-second and full-drill metrics and the score. Pure functions, easy to unit test. |
| CoachEngine | Picks cues by the rules above. Pure logic with an injected clock. |
| SpeechService | Speaks cues and tells AudioService when speech starts and ends. |
| PlacementChecker | The placement checks and their spoken fixes. |
| Store | Saved sessions, using SwiftData. |
| DebugRecorder | Writes the video with sound plus an event log and the config used. |
| Config | One JSON file of tunables, loaded at start, editable in Debug mode. |

**Threads:** camera on its own queue; Vision on one serial processing queue; audio analysis on another; fusion, metrics and coach on a single engine queue; UI on the main thread, updated at most 30 times a second.

**Performance budgets**

| Item | Budget |
|---|---|
| Vision per frame, iPhone 13 Pro and later | 16 ms or less (60 fps) |
| Vision per frame, iPhone 12 and 13 | 33 ms or less (30 fps) |
| Bounce to count on screen | 150 ms or less |
| Problem seen to cue spoken | 1.5 seconds or less |
| App start to Home | 1 second or less |

## Data

**Session**, saved after every drill that reaches the summary: id, start time, drill (crossover, right pound, left pound), place (Home or Gym), duration, total score, the four part scores, stars, count, speed, lost balls, frame rate used, device model, app version, config version.

**Bounce events** are kept for the session in memory and saved only in Debug mode.

**Streak** is worked out from saved sessions by local calendar day, not stored.

**Debug recording**, one folder per drill:

- video with sound, as recorded by the phone;
- an events file with one line per item: onsets (time, energy, voice ratio), joints for each frame (time, the 13 joints with confidence), bounce events, head state per frame, cues spoken, state changes;
- the config used;
- a summary file with the computed metrics.

**Privacy:** camera and microphone permission text says video and sound stay on the phone. No network code in v1. Delete all data removes sessions and recordings. If the app ever goes beyond family testing, kids' privacy rules (COPPA in the US) need a review first.

## Testing

**Unit tests**

- Onset detector on made-up signals: clean thumps at known times, thumps under noise, speech, two balls at once.
- Fusion on hand-written joint tracks with known pushes.
- Every metric and the score against worked examples, including too-little-data cases.
- Coach rules: silence at start, gaps, no repeats, tie order, praise.
- Streak across days and time zones.

**Replay tests:** every labeled clip runs through the file source in CI on a Mac, and the results must stay within the targets below. A change to the config that breaks a target fails the build.

**Field clips:** about 15 drills of 30 seconds, 5 each in a garage, a driveway and a gym, mixing good and sloppy dribbling and at least two kids. A second iPhone films each in 240 fps slow-motion. Start every clip with one clap so the two recordings can be lined up.

**Labels:** for each bounce, its time, its hand, and whether the hand was above the waist, marked from the slow-motion video and the sound wave. A small Python script matches app events to labels within 50 ms and prints the numbers below.

| Measure | v1 target |
|---|---|
| Bounce count error per drill, home | 5 percent or less |
| Bounces found within 50 ms, home | 95 percent or more |
| False bounces per drill, gym with other balls | 2 or fewer |
| Hand correct, among bounces given a hand | 90 percent or more |
| Bounces given a hand at all | 80 percent or more |
| Low call agrees with label | 85 percent or more |
| Wrong cues per drill, judged from video | fewer than 1 |

A missed hand target triggers the fallback: a small ball detector converted to Core ML, trained on frames from these clips. A missed gym target triggers a sound classifier built with Create ML.

## Milestones

Each milestone ends when its exit check passes.

1. **M0, skeleton app:** Xcode project, SwiftUI screens with placeholder data, config file loads. Exit: all screens reachable.
2. **M1, bounce counter:** AudioService and the onset detector with a live count and rhythm on screen. Exit: count within 5 percent on concrete and wood across 5 home clips.
3. **M2, body tracking:** CaptureService, PoseService, debug skeleton overlay, frame-rate fallback, placement check with spoken fixes. Exit: placement passes within 10 seconds for two kids; 60 fps holds on an iPhone 13 Pro or later.
4. **M3, fusion and metrics:** FusionEngine, HeadTracker, MetricsEngine, summary screen. Exit: hand and low targets met on home clips.
5. **M4, drill and coach:** countdown, timer, interruptions, CoachEngine, SpeechService, both audio-session modes compared. Exit: the better mode chosen from clips; wrong cues under 1 per drill.
6. **M5, debug recorder and replay harness:** recordings, file source, Python matcher, replay tests. Exit: all 15 clips labeled and in the test suite.
7. **M6, kid test:** two weeks of real use at home; reword cues the kids ignore; tune thresholds. Exit: kids finish a drill without help and ask to go again.

## Open questions

- Portrait or landscape. Portrait fits a standing kid better; landscape shows more of the floor. Decide after M2.
- Built-in voice or recorded clips for the coach.
- Whether the pound drills ship in v1 or stay as test drills.
- Whether v1 stays a family app or heads toward the App Store, which brings in kids' privacy review, onboarding and pricing.

## Sources

Apple's Vision documentation on detecting body poses; Apple's documentation for AVFoundation capture, AVAudioEngine and speech synthesis; a May 2026 dev.to post by the developer of SportsReflector on on-device pose in production (frame times, angle and lighting pitfalls); the Dribble coach first prototype plan and the competitor scan in this task.
