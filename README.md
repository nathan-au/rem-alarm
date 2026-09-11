# REM Alarm

An alarm clock where you can't set the time.

You pick a number of sleep cycles, not a clock time. The app lists your cycle
options — 1 cycle from now, 2 cycles from now, and so on — and you tap one before
you go to sleep. The premise is that waking at the end of a cycle beats waking in
the middle of one, so the wake time is a consequence of the cycle count rather
than something you choose directly.

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
tests run — otherwise Xcode runs the UI tests on a *clone* of the device and your
`log stream` is pointed at the wrong simulator.

Bundle identifiers:

| Target | Identifier |
| --- | --- |
| App | `com.chickengrass.rem-alarm` |
| Widget extension | `com.chickengrass.rem-alarm.REMAlarmWidget` |

## Settings

Everything the user can tune lives behind the control on the picker screen.
All three are persisted in `UserDefaults` and clamped on read, so a stale or
hand-edited preference can't produce a nonsensical list of alarms.

| Setting | Default | Range | Notes |
| --- | --- | --- | --- |
| Cycle length | 100 min | 60–140, step 5 | Real cycles vary by person; 100 is only an average. |
| Time to fall asleep | None (0 min) | 0–60, step 1 | Added **once**, before the first cycle. |
| Options shown | 10 | 3–12 | How many rows the picker lists. |

The wake time is:

```
wakeTime = now + sleepLatency + (cycles × cycleLength)
```

Two deliberate decisions in that formula:

- **Latency is added once, not per cycle.** It models the time spent lying awake
  before the first cycle begins. There are unit tests pinning this, because
  getting it wrong is invisible on screen and wrecks every alarm.
- **Latency is not counted as sleep.** The "6h 40m of sleep" label reflects time
  actually asleep, so it doesn't move when you change the buffer.

The default buffer is `None` so that turning the feature on is the user's
decision rather than a silent shift of every alarm. When it's non-zero the
picker subtitle spells it out — otherwise the offset times just look broken.

Changing a setting never rewrites an already-armed alarm. It's scheduled at an
absolute time and the user has gone to sleep expecting it; the armed screen keeps
its original numbers.

## How it works

The app is built on **AlarmKit**, Apple's iOS 26 framework for third-party
alarms. This is the reason for the iOS 26.5 floor. It's the only way to get an
alarm that behaves like the built-in Clock app: it rings through the ringer
switch, silent mode, Do Not Disturb, and Focus, and presents a system full-screen
alert. Local notifications can't do any of that — they're silenced by Focus and
give up after ~30 seconds, which makes them useless as a wake-up alarm.

The tradeoff is that AlarmKit requires an explicit user permission grant and is
awkward to verify in the simulator.

### Targets

| Target | Contents |
| --- | --- |
| `rem-alarm` | The app. |
| `REMAlarmWidget` | Widget extension; renders the Live Activity. |
| `Shared` | Not a target — a folder compiled into **both** of the above. |
| `rem-alarmTests` | Cycle math, settings, and one end-to-end firing check. |
| `rem-alarmUITests` | Arming flow and the settings round-trip. |

### Files

| File | Role |
| --- | --- |
| `Shared/Palette.swift` | The colour tokens. Compiled into both targets. |
| `Shared/REMAlarmMetadata.swift` | The alarm metadata type. Must be identical in both targets. |
| `rem-alarm/REMCycle.swift` | Cycle math. Pure and parameterised — no dependency on settings. |
| `rem-alarm/SleepSettings.swift` | The three user settings, persisted and clamped. |
| `rem-alarm/AlarmScheduler.swift` | AlarmKit wrapper. Permissions, scheduling, cancelling, persistence. |
| `rem-alarm/ContentView.swift` | Picker screen and armed confirmation card. |
| `rem-alarm/SettingsView.swift` | The settings sheet. |
| `rem-alarm/Info.plist` | `NSAlarmKitUsageDescription` and `NSSupportsLiveActivities`. |
| `REMAlarmWidget/REMAlarmLiveActivity.swift` | Lock Screen and Dynamic Island presentation. |

`Shared/` is a `PBXFileSystemSynchronizedRootGroup` listed in the
`fileSystemSynchronizedGroups` of both targets, which is how one folder compiles
into two products without duplicating file references.

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

### The Live Activity

Scheduling an alarm whose attributes are `AlarmAttributes<REMAlarmMetadata>` is
what makes the system look for a matching `ActivityConfiguration` in the widget
extension. The app never starts or stops the activity itself; AlarmKit drives it.

Three things all have to be true or you get no Live Activity and no error
explaining why:

1. The widget extension declares
   `ActivityConfiguration(for: AlarmAttributes<REMAlarmMetadata>.self)`.
2. `REMAlarmMetadata` is *the same type* in both targets — hence `Shared/`.
3. The app's Info.plist has `NSSupportsLiveActivities`.

Plus a fourth, which is the one that actually costs you an afternoon — see below.

## Gotchas

**A scheduled alarm gets no Live Activity until you call `countdown(id:)`.**
An alarm that has just been scheduled sits in `.scheduled` state, and AlarmKit
creates no activity for it at all. The Lock Screen stays empty for the entire
night and only lights up when the alarm finally rings, which is precisely
backwards. Moving the alarm into `.countdown` state is what triggers activity
creation. Confirmed from the logs, with and without the call:

```
# with manager.countdown(id:)
AlarmKitCore:activityManager] Creating activity for alarm with state countdown
AlarmKitCore:activityManager] Created activity 2B4165FC-…

# without it — nothing, and then on cancel:
AlarmKitCore:alarmManager] Failed to cancel activity for alarm: unknownAlarm
```

So `arm()` schedules with both a `.fixed` schedule *and* a `countdownDuration`
whose `preAlert` is the time until the wake time, then calls `countdown(id:)`.
`AlarmFiringTests` verifies the result really does reach `.alerting`.

**`INFOPLIST_KEY_NSAlarmKitUsageDescription` does not work.** Xcode 26 generates
the Info.plist from build settings, and the usual move is to add
`INFOPLIST_KEY_<SomeKey>` to the target. That prefix only expands for keys on
Xcode's known-key list, and AlarmKit's usage description isn't one of them. It
builds clean, produces no warning, and the key silently never reaches the bundle
— at which point authorization fails and the app appears to do nothing when you
tap a row. The giveaway is in the simulator log:

```
mobiletimerd: [com.apple.AlarmKitCore:authorizationServer]
  Client has not provided an NSAlarmKitUsageDescription value
```

The fix in place is a real `rem-alarm/Info.plist` with `INFOPLIST_FILE` pointing
at it. `GENERATE_INFOPLIST_FILE` stays on, so Xcode merges its generated keys
into that file — you only need to list the extras.

**Both Info.plists need a membership exception.** `rem-alarm/` and
`REMAlarmWidget/` are `PBXFileSystemSynchronizedRootGroup`s, meaning Xcode
automatically includes everything in the folder. That's convenient for source
files (drop in a `.swift` and it's in the target, no project edit needed) but it
also tries to copy `Info.plist` in as a *resource*, colliding with the real one:

```
error: Multiple commands produce '.../rem-alarm.app/Info.plist'
```

Each synchronized group carries a
`PBXFileSystemSynchronizedBuildFileExceptionSet` excluding `Info.plist` from its
target's resources. Don't delete them.

**The simulator can't fully validate an alarm.** It will show you the permission
prompt, schedule the alarm, create the Live Activity, and reach the alerting
state, but it cannot demonstrate that the alarm rings *through silent mode and
Focus*. Test that on hardware before trusting it with an actual night's sleep.

**UI tests leave the simulator rotated.** If your screenshots come out in
landscape, shut the simulator down and boot it again rather than hunting for a
layout bug.

## Design rules

Two hard constraints on the visual design:

- **No gradients anywhere.** Flat fills only.
- **No purple tones at all** — nothing in the violet, indigo, or magenta family.

The palette is a warm amber accent on a neutral near-black. The background is
deliberately *not* blue-tinted, because a blue-black drifts towards purple as
soon as it sits next to a cool accent. All of it lives in `Shared/Palette.swift`;
the widget and the app read the same tokens, and `AlarmAttributes.tintColor`
is set from the same accent so the system alert matches.

## Testing

`rem-alarmTests` covers the parts where a bug is both likely and invisible:

- Cycle math — option count, spacing, custom cycle lengths, and specifically that
  latency is applied exactly once and never counted as sleep.
- Duration formatting at the `5h` / `5h 20m` / `45m` boundaries.
- Settings persistence, clamping of out-of-range stored values, and reset.
- `AlarmFiringTests` schedules a real 15-second alarm and waits for it to reach
  `.alerting`. It's slow by nature and it skips itself when AlarmKit
  authorization hasn't been granted, because a unit test can't tap the system
  permission prompt.

`rem-alarmUITests` covers the arming flow (including the permission alert) and
the settings round-trip. The settings test normalises state through the reset
button at both ends — settings persist across launches, so a test that assumes a
starting value passes once and then fails forever after.

## Known gaps

- **Long alarms may outlive the Live Activity.** Ten cycles is over 16 hours, and
  Live Activities go stale well before that. The alarm itself is unaffected — it's
  a real scheduled alarm, not a Live Activity — but the Lock Screen countdown may
  disappear on the longest options. Not yet measured.
- **The Live Activity has not been verified visually.** The logs confirm it's
  created and routed to our widget for the Lock Screen, Dynamic Island, and
  ambient destinations, but the rendering itself needs eyes on a device.
- **Cycle length is still a number the user types, not a number we measure.**

## Next steps

Roughly in the order I'd tackle them.

### 1. Wake-time-first mode

The inverse question, and arguably the more common one: *"I have to be up at 7am
— when should I go to bed?"* Same math, solved for start time instead, producing
a list of bedtimes rather than wake times.

This doesn't dilute the core premise — the user still never picks an arbitrary
alarm time, they pick a cycle count. It just runs the calculation from the other
end.

### 2. Personalized cycle length from HealthKit

The honest version of the cycle-length setting. If the user has an Apple Watch,
HealthKit exposes sleep stage data, and observed REM-to-REM intervals give a
measured cycle length instead of a typed-in guess. This is the feature that would
make the app meaningfully better than arithmetic anyone could do in their head.

Bigger lift: HealthKit entitlement, a permission flow, enough recorded nights to
average over, and a fallback for users with no watch.

### 3. Measure the Live Activity staleness ceiling

Find out where the Lock Screen countdown actually gives up, and decide what to
show past that point. Possibly nothing — but it should be a decision rather than
a surprise.

### Smaller loose ends

- **App icon and accent color.** `Assets.xcassets` is still the empty template.
- **`.gitignore`.** `rem-alarm.xcodeproj/xcuserdata/` is currently untracked and
  will otherwise get committed.
- **Dynamic Type.** The picker rows use fixed spacing and will crowd at large
  accessibility text sizes.
- **Decide about snooze.** Deliberately omitted: AlarmKit offers a secondary
  button, but a snooze that isn't a full cycle wakes you mid-cycle, which is the
  exact thing the app exists to avoid. The Live Activity likewise ships without a
  pause button, on the same reasoning — pausing an alarm you're asleep behind is
  a footgun. If either gets added it should be a considered decision, not a
  default.
