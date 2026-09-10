# REM Alarm

An alarm clock where you can't set the time.

You pick a number of sleep cycles, not a clock time. The app shows ten options —
1 through 10 cycles from right now — and you tap one before you go to sleep. The
premise is that waking at the end of a cycle beats waking in the middle of one,
so the wake time is a consequence of the cycle count rather than something you
choose directly.

A cycle is currently **100 minutes**, hardcoded.

## Requirements

- Xcode 26+ (built and tested against 26.6)
- iOS 26.5 deployment target — non-negotiable, see AlarmKit below
- A physical device to *properly* test the alarm firing

## Build and run

```sh
# Build
xcodebuild -project rem-alarm.xcodeproj -scheme rem-alarm \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro,OS=26.5' build

# Test
xcodebuild test -project rem-alarm.xcodeproj -scheme rem-alarm \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro,OS=26.5' \
  -parallel-testing-enabled NO
```

`-parallel-testing-enabled NO` matters if you want to read simulator logs while
tests run — otherwise Xcode runs the UI tests on a *clone* of the device and
your `log stream` is pointed at the wrong simulator.

Bundle identifier: `com.chickengrass.rem-alarm`

## How it works

The app is built on **AlarmKit**, Apple's iOS 26 framework for third-party
alarms. This is the reason for the iOS 26.5 floor. It's the only way to get an
alarm that behaves like the built-in Clock app: it rings through the ringer
switch, silent mode, Do Not Disturb, and Focus, and presents a system full-screen
alert. Local notifications can't do any of that — they're silenced by Focus and
give up after ~30 seconds, which makes them useless as a wake-up alarm.

The tradeoff is that AlarmKit requires an explicit user permission grant and is
awkward to verify in the simulator.

### Files

| File | Role |
| --- | --- |
| `rem-alarm/REMCycle.swift` | Cycle math. The 100-minute constant lives here. |
| `rem-alarm/AlarmScheduler.swift` | AlarmKit wrapper. Permissions, scheduling, cancelling, persistence. |
| `rem-alarm/ContentView.swift` | The picker screen and the armed confirmation card. |
| `rem-alarm/Info.plist` | Exists solely to carry `NSAlarmKitUsageDescription`. See the gotcha below. |
| `rem-alarmUITests/ArmAlarmUITests.swift` | Drives tap → permission → armed → cancel. |

### State model

Only one alarm is ever armed at a time — you only fall asleep once per night.
`AlarmScheduler` holds an optional `ArmedAlarm` and the UI is a straight function
of whether that's nil.

AlarmKit owns the truth, not us. The scheduler subscribes to
`AlarmManager.shared.alarmUpdates`, so if you dismiss the alarm from the system
alert, or it fires while the app is closed, the alarm disappears from the
system's list and the UI falls back to the picker on its own. The copy in
`UserDefaults` is only there so the armed screen survives an app kill; it's
reconciled against the system on the next update and discarded if its wake time
is in the past.

Permission is requested lazily, on the first tap, rather than at launch — the
prompt makes more sense when the user has just asked for an alarm.

## Gotchas

**`INFOPLIST_KEY_NSAlarmKitUsageDescription` does not work.** Xcode 26 generates
the Info.plist from build settings, and the usual move is to add
`INFOPLIST_KEY_<SomeKey>` to the target. That prefix only expands for keys on
Xcode's known-key list, and AlarmKit's usage description isn't one of them. It
builds clean, produces no warning, and the key silently never reaches the bundle
— at which point authorization fails and the app appears to do nothing when you
tap a row. If you're debugging that symptom, the giveaway is in the simulator log:

```
mobiletimerd: [com.apple.AlarmKitCore:authorizationServer]
  Client has not provided an NSAlarmKitUsageDescription value
```

The fix in place is a real `rem-alarm/Info.plist` with `INFOPLIST_FILE` pointing
at it. `GENERATE_INFOPLIST_FILE` stays on, so Xcode merges its generated keys
into that file — you only need to list the extras.

**The Info.plist needs a membership exception.** `rem-alarm/` is a
`PBXFileSystemSynchronizedRootGroup`, meaning Xcode automatically includes
everything in the folder. That's convenient for source files (drop in a `.swift`
and it's in the target, no project edit needed) but it also tried to copy
`Info.plist` in as a *resource*, colliding with the real one:

```
error: Multiple commands produce '.../rem-alarm.app/Info.plist'
```

The project carries a `PBXFileSystemSynchronizedBuildFileExceptionSet` excluding
`Info.plist` from the app target's resources. Don't delete it.

**The simulator can't fully validate an alarm.** It will show you the permission
prompt, schedule the alarm, and render the UI, but it cannot demonstrate that the
alarm actually rings through silent mode and Focus. Test that on hardware before
trusting it with an actual night's sleep.

## Known gaps

- **No Live Activity.** AlarmKit's Lock Screen / Dynamic Island countdown needs a
  widget extension target, which doesn't exist yet. Scheduling and the wake alert
  work fine without it, but there's no glanceable countdown while you fall
  asleep. The symptom in the logs is a harmless
  `Failed to cancel activity for alarm: unknownAlarm` on cancel.
- **No sleep-latency buffer.** The wake time is `now + cycles × 100 min`, with no
  allowance for the time it takes to actually fall asleep. Real usage may show
  this wakes you late; the usual assumption is ~14 minutes.
- **Cycle length is hardcoded.** 100 minutes for everyone. Real cycles vary by
  person and are commonly closer to 90.

## Changing the cycle length

One constant, in `rem-alarm/REMCycle.swift`:

```swift
static let length: TimeInterval = 100 * 60
```

Everything else — the ten wake times, the "Xh Ym of sleep" labels, the subtitle
on the picker — derives from it. Making it user-adjustable means turning it into
stored state (`@AppStorage`) and adding a control; nothing else has to change.

## Next steps

Roughly in the order I'd tackle them.

### 1. User-configurable cycle length

100 minutes is a guess applied to everyone. Real cycles vary meaningfully by
person and are commonly closer to 90, so this is the setting most likely to be
wrong for any given user.

Turn `REMCycle.length` into stored state (`@AppStorage("cycleLength")`) and feed
it through `REMCycle.options(from:)` rather than reading the constant directly.
Keep 100 as the default so nothing changes for a user who never opens settings.
Sensible bounds are about 60–140 minutes in 5-minute steps — outside that the
premise stops being credible.

### 2. User-configurable time to fall asleep

Right now the wake time is `now + cycles × length`, which quietly assumes you
fall asleep the instant you tap. You don't. That error is systematic and always
in the same direction: every alarm fires slightly *early* relative to your actual
cycle boundaries, and it compounds across the night.

The math becomes:

```
wakeTime = now + sleepLatency + (cycles × cycleLength)
```

Two things to get right beyond the arithmetic:

- **Show the assumption in the UI.** If the user taps at 11:00pm with a 14-minute
  buffer, the first option reads 12:54am, not 12:40am. Without an explanation on
  screen, that just looks broken.
- **Don't retroactively move an armed alarm.** Changing either setting while an
  alarm is armed should leave that alarm alone — it's already scheduled at an
  absolute time and the user has gone to sleep expecting it.

These two settings are the same shape and both change the signature of the cycle
math, so they're worth doing together in one pass rather than twice.

### 3. Widget extension for the Live Activity

The largest gap in the app as it stands. AlarmKit renders a Lock Screen and
Dynamic Island presentation for a scheduled alarm, but only if the app ships a
widget extension with an `ActivityConfiguration` for
`AlarmAttributes<REMAlarmMetadata>`. Without it you get no countdown on the Lock
Screen — which is exactly where you'd want it, since the phone is face-down on a
nightstand and the app isn't open.

This is a new target rather than a code change, and `REMAlarmMetadata` has to be
shared between the app and the extension.

### 4. Unit tests for the cycle math

`rem-alarmTests` is still the untouched template. `REMCycle` is pure, synchronous,
and has no dependencies — it's the cheapest thing in the project to test and it's
where a real bug would do the most damage (a wrong wake time is the whole
product). Worth covering: option count and ordering, duration formatting at the
`5h` / `5h 20m` boundary, and once latency lands, that the offset is applied
exactly once.

### 5. Wake-time-first mode

The inverse question, and arguably the more common one: *"I have to be up at 7am
— when should I go to bed?"* Same math, solved for start time instead, producing
a list of bedtimes rather than wake times.

This doesn't dilute the core premise — the user still never picks an arbitrary
alarm time, they pick a cycle count. It just runs the calculation from the other
end.

### 6. Personalized cycle length from HealthKit

The honest version of setting 1. If the user has an Apple Watch, HealthKit
exposes sleep stage data, and observed REM-to-REM intervals give a measured cycle
length instead of a typed-in guess. This is the feature that would make the app
meaningfully better than arithmetic anyone could do in their head.

Bigger lift: HealthKit entitlement, a permission flow, enough recorded nights to
average over, and a fallback for users with no watch.

### Smaller loose ends

- **App icon and accent color.** `Assets.xcassets` is still the empty template.
- **`.gitignore`.** `rem-alarm.xcodeproj/xcuserdata/` is currently untracked and
  will otherwise get committed.
- **Dynamic Type.** The picker rows use fixed spacing and will crowd at large
  accessibility text sizes.
- **Decide about snooze.** Deliberately omitted: AlarmKit offers a secondary
  button, but a snooze that isn't a full cycle wakes you mid-cycle, which is the
  exact thing the app exists to avoid. If snooze ever gets added it should be a
  considered decision, not a default.
