# REM Alarm

An alarm clock where you can't set the time.

You pick a number of sleep cycles, not a clock time. The app lists your cycle
options — 1 cycle from now, 2 cycles from now, and so on — and you tap one before
you go to sleep. The premise is that waking at the end of a cycle beats waking in
the middle of one, so the wake time is a consequence of the cycle count rather
than something you choose directly.

> **Hit something strange?** Check [LOG.md](LOG.md) before debugging. It records
> every non-obvious failure this project has already run into — several of which
> produce no build warning and no runtime error — along with the reasoning behind
> the design decisions.

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

Keep `-parallel-testing-enabled NO` if you intend to read simulator logs during a
test run (LOG.md §7).

Bundle identifiers:

| Target | Identifier |
| --- | --- |
| App | `com.chickengrass.rem-alarm` |
| Widget extension | `com.chickengrass.rem-alarm.REMAlarmWidget` |

## Settings

Everything the user can tune lives behind the control on the picker screen. All
three are persisted in `UserDefaults` and clamped on read.

| Setting | Default | Range | Notes |
| --- | --- | --- | --- |
| Cycle length | 100 min | 60–140, step 5 | Real cycles vary by person; 100 is only an average. |
| Time to fall asleep | None (0 min) | 0–60, step 1 | Added **once**, before the first cycle. |
| Options shown | 10 | 3–12 | How many rows the picker lists. |

The wake time is:

```
wakeTime = now + sleepLatency + (cycles × cycleLength)
```

The default buffer is `None` so that turning it on is the user's decision rather
than a silent shift of every alarm. When it's non-zero the picker subtitle spells
it out — otherwise the offset times just look broken.

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

Permission is requested lazily, on the first tap, rather than at launch.

### The Live Activity

Scheduling an alarm whose attributes are `AlarmAttributes<REMAlarmMetadata>` is
what makes the system look for a matching `ActivityConfiguration` in the widget
extension. The app never starts or stops the activity itself; AlarmKit drives it.

Four things all have to be true, and none of them fail loudly:

1. The widget extension declares
   `ActivityConfiguration(for: AlarmAttributes<REMAlarmMetadata>.self)`.
2. `REMAlarmMetadata` is *the same type* in both targets — hence `Shared/`.
3. The app's Info.plist has `NSSupportsLiveActivities`.
4. The alarm is moved into `.countdown` state after scheduling, or no activity is
   ever created (LOG.md §14 — this one is genuinely surprising).

## Testing

`rem-alarmTests` covers the parts where a bug is both likely and invisible:

- Cycle math — option count, spacing, custom cycle lengths, and specifically that
  latency is applied exactly once and never counted as sleep.
- Duration formatting at the `5h` / `5h 20m` / `45m` boundaries.
- Settings persistence, clamping of out-of-range stored values, and reset.
- `AlarmFiringTests` schedules a real 15-second alarm and waits for it to reach
  `.alerting`, because a configuration that is *accepted* is not necessarily one
  that *rings*. It skips itself when AlarmKit authorization hasn't been granted.

`rem-alarmUITests` covers the arming flow (including the permission alert) and
the settings round-trip.

Two conventions worth keeping:

- Address elements by accessibility identifier, never by index.
- Any test that touches persisted settings must establish its own starting state.

## Design rules

Hard constraints. The reasoning is in [LOG.md](LOG.md#design-rules-established).

- **No gradients anywhere.** Flat fills only.
- **No purple tones at all** — nothing violet, indigo, or magenta.
- All colour comes from `Shared/Palette.swift`, including
  `AlarmAttributes.tintColor`.
- Latency is added **once**, not per cycle, and is never counted as sleep.
- `REMCycle` stays pure and parameterised.
- Settings changes never rewrite an already-armed alarm.
- No snooze, and no pause button on the Live Activity.

## Next steps

Ordered by what I'd tackle first. Open questions still to be answered are in
[LOG.md](LOG.md#open-questions).

### Product

**1. Wake-time-first mode.** The inverse question, and arguably the more common
one: *"I have to be up at 7am — when should I go to bed?"* Same math solved for
start time, producing a list of bedtimes. Doesn't dilute the premise: the user
still picks a cycle count, not an arbitrary time.

**2. Morning feedback loop.** After an alarm fires, ask one question — *how did
that wake-up feel?* — and record it against the cycle count and length used.
After a couple of weeks that's real evidence for whether 100 minutes is right for
this person. This is the cheapest path to a personalised cycle length and needs no
entitlements at all, which makes it a better first move than HealthKit.

**3. Personalised cycle length from HealthKit.** The rigorous version of the
above. Apple Watch sleep-stage data gives measured REM-to-REM intervals instead
of a typed-in guess. Bigger lift: entitlement, permission flow, enough recorded
nights to average over, and a fallback for users with no watch.

**4. Bedtime nudge.** The inverse of the alarm: *"to get 5 cycles you need to be
asleep by 11:20."* A notification earlier in the evening, when there's still time
to act on it.

**5. Recurring alarms.** `Alarm.Schedule.relative` supports weekly recurrence.
"Same 4 cycles every weeknight" is a real use case, though it partly conflicts
with the sleep-now framing — worth designing carefully rather than bolting on.

### Platform surfaces

**6. App Intents + Siri.** *"Hey Siri, wake me in 4 cycles."* Arming without
unlocking the phone is exactly right for something you do with the lights already
off. Also unlocks Shortcuts automation.

**7. Control Center control.** A `ControlWidget` for one-tap arming of your usual
cycle count.

**8. Home Screen / Lock Screen widget.** Distinct from the Live Activity: a
persistent widget showing tonight's options, tappable straight into arming.

**9. Apple Watch app.** The watch is already on your wrist at bedtime, and a
haptic wake-up is gentler than a phone alarm for anyone sharing a bed.

### Robustness

**10. Alarm sound selection, and a gentler default.** AlarmKit takes an
`AlertConfiguration.AlertSound`, so custom sounds are available. A jarring tone
undoes some of the benefit of waking at a cycle boundary.

**11. Handle `AlarmError.maximumLimitReached`.** Currently it surfaces as a
generic error string. Unlikely with a one-alarm-at-a-time model, but the case
exists in the API for a reason.

**12. DST and timezone changes while armed.** A `.fixed` schedule is an absolute
`Date`, so the alarm fires at the correct instant — but the *displayed* wake time
could shift out from under the user. Decide what should happen and test it.

**13. Accessibility pass.** Dynamic Type (the picker rows use fixed spacing and
will crowd at large sizes), VoiceOver ordering, and Reduce Motion.

**14. iPad and landscape.** `TARGETED_DEVICE_FAMILY` is `1,2` and landscape is
enabled, so both are shipping today without ever having been designed. Either
support them properly or restrict the orientation.

**15. Localization.** All user-facing strings are hardcoded English. The alarm
title already flows through `LocalizedStringResource`, so the AlarmKit side is
ready.

### Shipping

**16. CI.** GitHub Actions running the test suite on every push. The unit tests
are fast; the UI tests need a booted simulator and are the slow part.

**17. Privacy manifest.** `PrivacyInfo.xcprivacy` is required for App Store
submission and doesn't exist yet.

**18. App icon and accent colour.** `Assets.xcassets` is still the empty
template.

**19. First-run explanation.** The premise — that you don't get to choose the
time — is unusual enough to be worth one screen of explanation, or the app reads
as broken.

**20. `.gitignore`.** `rem-alarm.xcodeproj/xcuserdata/` is currently untracked
and will otherwise get committed.
