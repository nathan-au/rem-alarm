# Engineering log

Chronological record of problems hit, what caused them, and what fixed them —
plus the design decisions made along the way and the reasoning behind them.
Earliest first. Append new entries at the end.

Format for each entry: **Symptom → Cause → Fix**, or a plain note for decisions
that weren't triggered by a failure.

---

## Phase 1 — Getting a real alarm to ring

### 1. The deployment target decided the architecture

The template came with an iOS 26.5 deployment target, which puts **AlarmKit** on
the table. That's the deciding factor for this whole app: it's the only way a
third-party app can ring through the ringer switch, silent mode, Do Not Disturb,
and Focus with a system full-screen alert.

The alternative — `UNUserNotificationCenter` with a custom sound — is silenced by
Focus and gives up after ~30 seconds. Fine for a reminder, useless for a
wake-up alarm. Everything downstream (the iOS 26.5 floor, the permission prompt,
the widget extension) follows from choosing AlarmKit.

### 2. Read the API from the SDK, not from memory

Before writing any AlarmKit code, dumped the real API surface:

```sh
SDK=$(xcrun --sdk iphoneos --show-sdk-path)
find "$SDK/System/Library/Frameworks/AlarmKit.framework" -name "*.swiftinterface"
```

Worth doing for any framework this new. It confirmed the exact shapes of
`AlarmConfiguration`, `Alarm.Schedule`, `AlarmPresentation`, and
`AlarmManager.AuthorizationState` rather than guessing at them.

### 3. `stopButton` is deprecated as of iOS 26.1

**Symptom:** build warning on `AlarmPresentation.Alert(title:stopButton:…)`.

**Cause:** since iOS 26.1 the system renders its own stop button; the parameter
is ignored.

**Fix:** use the initializer without `stopButton`. Left a comment at the call
site so nobody "helpfully" adds one back.

### 4. No way to tap the simulator from the shell

**Symptom:** needed to drive a tap to test the arming flow. `idb` isn't
installed, and AppleScript failed with `osascript is not allowed assistive
access`.

**Fix:** drove the interaction with an XCUITest instead. This turned out better
than a one-off script — it left a durable test behind, and XCUITest can handle
the system permission alert, which a coordinate-based tap can't.

### 5. `INFOPLIST_KEY_NSAlarmKitUsageDescription` silently does nothing

The one that cost the most time.

**Symptom:** app built clean with no warnings, then appeared to completely ignore
taps on a cycle row. No alert, no permission prompt, no error — just nothing.

**Cause:** Xcode 26 generates the Info.plist from build settings, and the normal
move is `INFOPLIST_KEY_<SomeKey>`. That prefix only expands for keys on Xcode's
**known-key list**, and AlarmKit's usage description isn't one. The key never
reached the bundle. Verified with:

```sh
plutil -p …/rem-alarm.app/Info.plist   # no NSAlarmKitUsageDescription
```

The actual giveaway was in the simulator log:

```
mobiletimerd: [com.apple.AlarmKitCore:authorizationServer]
  Client has not provided an NSAlarmKitUsageDescription value
```

**Fix:** a real `rem-alarm/Info.plist` with `INFOPLIST_FILE` pointing at it.
`GENERATE_INFOPLIST_FILE` stays `YES`, so Xcode merges its generated keys into
that file and only the extras need listing.

**Lesson:** when a permission-gated API does nothing at all, check the bundle's
built Info.plist before debugging the code. A silently missing key produces no
build warning and no runtime error.

### 6. Synchronized folders try to copy Info.plist as a resource

**Symptom:**

```
error: Multiple commands produce '.../rem-alarm.app/Info.plist'
warning: The Copy Bundle Resources build phase contains this target's Info.plist
```

**Cause:** `rem-alarm/` is a `PBXFileSystemSynchronizedRootGroup` — Xcode
automatically includes *everything* in the folder. Great for source files, but it
grabbed the new Info.plist as a resource too, colliding with the processed one.

**Fix:** a `PBXFileSystemSynchronizedBuildFileExceptionSet` on the group with
`membershipExceptions = (Info.plist)`. This is exactly what Xcode itself
generates; it just has to be written by hand when editing the project outside the
IDE.

### 7. UI tests run on a *clone* of the simulator

**Symptom:** `log stream` attached to the target simulator produced nothing while
a UI test ran. Test output mentioned `Clone 1 of iPhone 17 Pro`.

**Cause:** Xcode clones the device for UI test parallelisation.

**Fix:** `-parallel-testing-enabled NO`. Necessary any time you want to correlate
logs with a UI test run.

### 8. `.constant()` alert bindings can't be dismissed

**Symptom:** found by reading, not by failing — the permission alert used
`isPresented: .constant(scheduler.authorizationDenied)`.

**Cause:** a constant binding can't be written back to. Tapping "Not now" would
set it false, SwiftUI would discard that, and the alert would immediately
re-present — an un-dismissable loop.

**Fix:** real bindings. `authorizationDenied` became a settable property so
`$scheduler.authorizationDenied` works directly; the error alert uses an explicit
`Binding(get:set:)` that clears `errorMessage`.

### 9. First sign that the Live Activity was missing

Noticed in the logs on cancel:

```
AlarmKitCore:alarmManager] Failed to cancel activity for alarm:
  ActivityManagerError.unknownAlarm
```

Read correctly at the time as "no Live Activity exists" and attributed to the
missing widget extension. That was only half the story — see entry 14.

---

## Phase 2 — Settings, widget extension, palette

### 10. Use the `xcodeproj` gem, not a text editor, to add a target

Adding a widget extension means a new `PBXNativeTarget`, a build configuration
list, a synchronized group, an embed-extensions copy phase, a target dependency,
and a product reference. Hand-editing that much pbxproj is a good way to corrupt
a project.

`gem list` showed `xcodeproj (1.27.0)` already installed. Used that instead.

**API note:** `file_system_synchronized_groups` (on a target) and `exceptions`
(on a group) are read-only accessors returning object lists. Use `<<` to append;
assigning with `=` fails with `undefined method 'file_system_synchronized_groups='`.

### 11. One folder, two targets

The app and the widget must compile *the same* `REMAlarmMetadata` type — if the
types diverge, the system silently never renders the Live Activity.

**Approach:** a `Shared/` `PBXFileSystemSynchronizedRootGroup` listed in the
`fileSystemSynchronizedGroups` of **both** targets. One folder compiles into two
products with no duplicated file references. Holds `REMAlarmMetadata.swift` and
`Palette.swift`.

### 12. `NSSupportsLiveActivities` was missing

**Symptom:** caught by inspecting the built Info.plist rather than by a failure.

**Cause:** it's simply required for any app using Live Activities, and nothing
adds it automatically.

**Fix:** added alongside `NSAlarmKitUsageDescription` in `rem-alarm/Info.plist`.

### 13. The widget extension needs its own Info.plist exception too

Same issue as entry 6, now for `REMAlarmWidget/`. The extension carries a real
Info.plist for the `NSExtension` / `NSExtensionPointIdentifier` dictionary, so it
needs its own `PBXFileSystemSynchronizedBuildFileExceptionSet`.

### 14. A scheduled alarm gets **no Live Activity** until `countdown(id:)`

The most important finding in the project.

**Symptom:** with the widget extension built, embedded, and correctly registered,
still no Live Activity. Cancel still logged `unknownAlarm`.

**Cause:** a freshly scheduled alarm sits in `.scheduled` state, and AlarmKit
creates no activity for that state at all. The Lock Screen would have stayed
empty for the entire night and only lit up when the alarm finally rang — exactly
backwards for a sleep app.

**Diagnosis:** ran the arming flow with and without an explicit
`manager.countdown(id:)` call and diffed the logs.

```
# WITH manager.countdown(id:)
AlarmKitCore:activityManager] Creating activity for alarm with state countdown
AlarmKitCore:activityManager] Created activity 2B4165FC-…
AlarmKitCore:activityManager] Cancelled activity          # clean teardown

# WITHOUT it
AlarmKitCore:alarmManager]    Scheduled alarm
…nothing…
AlarmKitCore:alarmManager]    Failed to cancel activity: unknownAlarm
```

The successful run also confirmed the activity routes to *our* widget:

```
attributesType: AlarmAttributes<REMAlarmMetadata>
sceneTargets: [lockscreen: widget(containingProcess: com.chickengrass.rem-alarm),
               ambient:    widget(containingProcess: com.chickengrass.rem-alarm),
               systemAperture: widget(…)]
```

**Fix:** `arm()` schedules with both a `.fixed` schedule *and* a
`countdownDuration` whose `preAlert` is the time until the wake time, then calls
`countdown(id:)`.

**Follow-up:** that combination raised a fair question — does an alarm in
countdown state still actually *ring*? Verified rather than assumed; see entry 15.

### 15. Proving the alarm actually fires

A configuration that is *accepted* is not a configuration that *rings*. Wrote
`AlarmFiringTests`: arms a real 15-second alarm through the production
`AlarmScheduler.arm()` path and polls `AlarmManager.shared.alarms` until the
state changes.

Result: observed `.countdown` while pending and `.alerting` at the wake time.
The schedule-plus-countdown combination fires correctly.

The test skips itself when authorization hasn't been granted — a unit test can't
tap the system permission prompt, so on a freshly reset simulator it would
otherwise report a misleading failure.

**API note:** `AlarmManager.shared.alarms` is a *throwing property*; it needs
`try`.

### 16. Swift Testing: tuple arguments blew up the type checker

**Symptom:**

```
error: the compiler is unable to type-check this expression in reasonable time
  @__swiftmacro_…durationFormatting…
```

**Cause:** `@Test(arguments: [(300.0 * 60, "5h"), …])` — inferring tuple types
across a literal array with arithmetic in it.

**Fix:** a single `@Test` iterating an explicitly typed
`[(minutes: Int, expected: String)]` array. Also more readable, since the cases
can carry comments.

### 17. Adding UI broke a UI test by shifting button order

**Symptom:** `testArmingFirstCycleShowsConfirmation` started failing the moment
the settings gear was added.

**Cause:** the test used `app.buttons.element(boundBy: 0)`, which had been the
first cycle row and was now the gear. It was opening settings.

**Fix:** accessibility identifiers on everything the tests touch —
`cycleOption.<n>`, `openSettings`, `optionCountStepper`, `resetSettings`.
Positional element lookups are a latent failure waiting for the next UI change.

### 18. A test that passed once and then failed forever

**Symptom:** `testOptionCountControlsListLength` passed on its first run, then
failed on every subsequent run with "ten options by default".

**Cause:** the test decremented the option count and the setting *persists*. The
second run started from 9, not 10. A self-inflicted flaw — the test asserted an
absolute starting value while mutating that same value.

**Fix:** normalise through the "Reset to defaults" button at both the start and
end of the test.

**Lesson:** any UI test touching persisted settings has to establish its own
starting state. Passing once proves nothing.

### 19. SwiftUI `Form` renders lazily

**Symptom:** `app.buttons["resetSettings"].waitForExistence` returned false even
though the button was definitely in the view.

**Cause:** it was below the fold, and `Form` doesn't materialise off-screen rows —
so it wasn't merely un-hittable, it wasn't in the accessibility hierarchy at all.

**Fix:** `swipeUp()` fallback before asserting existence.

### 20. UI tests leave the simulator rotated

**Symptom:** screenshots came back in landscape with a stretched-looking layout.

**Cause:** device orientation persists after a UI test run. Nothing to do with
the app.

**Fix:** `simctl shutdown` + `boot` to reset orientation before screenshotting.
Worth knowing before hunting for a layout bug that isn't there.

---

## Design rules established

Collected here because they're decisions rather than incidents. These are
constraints on future work, not history.

### Visual

- **No gradients anywhere.** Flat fills only.
- **No purple tones at all** — nothing violet, indigo, or magenta.
- The background is deliberately **neutral** near-black, not blue-tinted. A
  blue-black drifts towards purple the moment it sits next to a cool accent.
- All colour lives in `Shared/Palette.swift`. The widget and app read the same
  tokens, and `AlarmAttributes.tintColor` uses the same accent so the system
  alert matches the app.

### Cycle math

- **Latency is added once, not per cycle.** It models time spent lying awake
  before the first cycle begins. Pinned by a unit test, because getting it wrong
  is invisible on screen and wrecks every alarm by a compounding amount.
- **Latency is not counted as sleep.** The "6h 40m of sleep" label reflects time
  actually asleep, so it doesn't move when the buffer changes.
- **`REMCycle` stays pure and parameterised.** It takes cycle length and latency
  as arguments rather than reading `SleepSettings` itself. The arithmetic is the
  whole product; keeping it dependency-free is what makes it cheap to test.

### Alarm behaviour

- **Settings never rewrite an armed alarm.** It's scheduled at an absolute time
  and the user has gone to sleep expecting it. `ArmedAlarm` carries its own
  `sleepDuration` rather than recomputing from current settings.
- **AlarmKit owns the truth.** The app subscribes to `alarmUpdates` and derives
  its UI from that. The `UserDefaults` copy exists only so the armed screen
  survives an app kill, and is reconciled against the system on the next update.
- **One armed alarm at a time.** You only fall asleep once per night.
- **Permission is requested lazily**, on the first tap rather than at launch —
  the prompt makes more sense once the user has actually asked for an alarm.
- **Stored settings are clamped on read**, so a stale or hand-edited preference
  can't produce a nonsensical picker.

### Deliberate omissions

- **No snooze.** AlarmKit offers a secondary button, but a snooze that isn't a
  full cycle wakes you mid-cycle — the exact thing the app exists to prevent.
- **No pause button on the Live Activity.** Same reasoning: pausing an alarm
  you're asleep behind is a footgun. Omitting the button from
  `AlarmPresentation.Countdown` is what keeps it off the UI.

---

## Open questions

Carried forward — not yet answered.

- **Live Activity staleness ceiling.** Ten cycles is over 16 hours and Live
  Activities go stale well before that. The alarm itself is unaffected (it's a
  real scheduled alarm, not a Live Activity), but the Lock Screen countdown may
  vanish on the longest options. Not yet measured.
- **The Live Activity has never been seen.** Logs confirm it's created and routed
  to our widget for lockscreen, Dynamic Island, and ambient destinations, but the
  rendering itself needs eyes on a physical device.
- **Ringing through silent mode and Focus is unverified.** The simulator will show
  the permission prompt, schedule the alarm, create the activity, and reach
  `.alerting` — but it cannot prove the alarm breaks through Focus. That needs
  hardware before trusting it with an actual night's sleep.
