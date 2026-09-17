# Android Native Implementation Plan

This plan is for building the Android version of AI News as a native Android app with a real Android home-screen widget. It is written so another model can pick it up and implement directly on a Pixel 9 or another Android phone using an on-device CLI workflow.

## Non-Negotiables

- Build a native Android app, not a web wrapper.
- The Android widget must be an actual Android home-screen widget, not an in-app panel.
- The app must have a normal news-reading screen that feels light and consumer-facing, not an admin console.
- The widget must expose the same important controls as the Mac floating widget: power, layout/mode where applicable, refresh, hide story, and story actions.
- Power state and fetch state must be visible as text/status, not hidden behind a button whose effect is unclear.
- The app and widget must show the same story state rules: hidden stories disappear immediately, refresh clears `NEW` labels when the feed did not change, and topic labels are meaningful.
- The implementation must be possible to build and test on the Pixel 9 itself, without relying on another machine.

## Pixel 9 On-Device Workflow

Use Termux from F-Droid as the development shell on the Pixel 9.

Required setup:

- Install Termux from F-Droid.
- Install Git, OpenJDK 21, Gradle or the repo Gradle wrapper dependencies, Android SDK command-line tools, and platform tools.
- Set `ANDROID_HOME` or `ANDROID_SDK_ROOT` to the SDK installed inside Termux storage.
- Enable Android Developer Options and Wireless Debugging on the Pixel 9.
- Pair Termux `adb` with the same phone over Wireless Debugging, then use `adb install`, `adb shell`, and `adb logcat` from Termux.

Expected workflow:

```bash
git clone <repo>
cd <repo>/android
./gradlew test
./gradlew assembleDebug
adb install -r app/build/outputs/apk/debug/app-debug.apk
adb logcat
```

Testing happens on the actual Pixel 9:

- Launch the app.
- Add the Android widget to the Pixel launcher.
- Resize the widget through launcher controls.
- Verify background refresh, power off/on, AI off/on, hide story, and refresh behavior from both app and widget.

If Android SDK setup in Termux is blocked, document the exact blocker. Do not silently switch to a desktop workflow unless the user explicitly agrees.

## Product Surfaces

### App

The main app should open directly to news, not setup/admin pages.

Primary app screens:

- News feed: story list, source, time, title, summary, image, topic labels, `NEW` marker, hide action, share action, open source action.
- Story detail: title, source link, summary, translation, research, neutral title, AI enrichment status, and related actions.
- Filters: feed/category/topic selection, hidden story management, saved views if needed.
- Runtime settings: backend/provider/account configuration, AI budget, fetch cadence, power timeout.

Runtime settings must stay secondary. The first experience should be reading news.

### Android Home-Screen Widget

Implement a real Android AppWidget. Use Jetpack Glance if it supports all required interactions cleanly; otherwise use standard `RemoteViews`.

Widget sizes:

- Small: one story, status row, power, refresh.
- Medium: two to three stories, status row, power, refresh, hide.
- Large: scroll-style list if supported, otherwise several fixed story rows.

The widget must show:

- Feed/category title.
- Runtime status text, for example `Runtime on · Fetching`, `Runtime off · Fetch off`, or `Runtime on · Fetch paused`.
- Power button with immediate visual feedback.
- Refresh button with visible fetching state.
- Each story title, source, time, summary when space allows, meaningful topic labels, `NEW` marker, share action, and hide action.

Do not rely on icon-only state. If pressing power changes something, the status text must change immediately.

## Android Architecture

Recommended stack:

- Kotlin.
- Jetpack Compose for the app UI.
- Glance or `RemoteViews` for the home-screen widget.
- Room for local story storage.
- DataStore for preferences and runtime settings.
- WorkManager for scheduled fetch and AI enrichment jobs.
- OkHttp/Retrofit for HTTP.
- Android Keystore plus EncryptedSharedPreferences or equivalent for provider keys.

Do not port the Mac Node supervisor into the Android app. Android should use a native runtime:

- `Runtime on` means WorkManager fetch and AI work are allowed.
- `Runtime off` means scheduled fetch and AI work are canceled or paused.
- `Fetch on/off/fetching` is tracked separately from AI state.
- AI jobs only run when runtime and AI are both enabled.

If compatibility with the existing Mac backend is needed, add it as an optional API mode:

- `Native runtime` mode: Android fetches feeds, stores stories locally, and runs AI enrichment through provider APIs.
- `Remote backend` mode: Android reads from an existing AI News backend URL and sends control commands to it.

Native runtime should be the default for a phone-only implementation.

## Power And Timeout Behavior

Add a runtime power model with these fields:

- `runtimeEnabled`: master on/off.
- `fetchEnabled`: whether feed fetching is allowed.
- `aiEnabled`: whether AI enrichment is allowed.
- `autoPowerOffAt`: optional timestamp for turning runtime and AI off after X hours.
- `lastFetchStartedAt`, `lastFetchFinishedAt`, and `lastFetchStatus`.
- `lastAiJobAt` and `aiQueueStatus`.

Controls:

- App header/status strip: power button plus visible `Runtime` and `Fetch` state.
- Widget header: power button plus visible `Runtime` and `Fetch` state.
- Settings: duration selector for “turn off after X hours”.

Button behavior:

- Power off immediately cancels scheduled fetch and AI work.
- Power on immediately schedules the next fetch and enables AI if AI was enabled before shutdown.
- Auto power-off updates app and widget state without requiring the app to be open.
- Refresh while powered off should either do nothing with clear disabled styling or ask the user to power on first.

## News State Rules

Story fields:

- `id`
- `source`
- `sourceUrl`
- `publishedAt`
- `fetchedAt`
- `title`
- `summary`
- `imageUrl`
- `topicLabels`
- `aiFieldsAvailable`
- `isNew`
- `isHidden`
- `hiddenAt`

Rules:

- `NEW` means the story was not present in the previous widget snapshot.
- Manual refresh clears `NEW` labels when the resulting story set is the same.
- Hidden stories must disappear immediately from both app and widget using optimistic local state.
- Hide must persist locally and sync to backend/API mode if configured.
- Topic labels must be generated from the story topic, not generic AI markers.
- `AI` can remain as a secondary marker only if needed, but topic labels should carry the useful meaning.

## AI Matching And Alerts

Support user-defined monitors written as natural language sentences, for example:

> when flu vaccinations will be available to the public in Bulgaria

End-of-day scanner behavior:

- Scan only story titles and summaries.
- Do not scan full article bodies.
- Use AI to decide whether each story matches the monitor sentence.
- Store match decision, confidence, explanation, matched monitor, and story ID.
- Raise an in-app alert and update the widget when a match is found.
- Stay quiet when no match is found.

Implementation:

- WorkManager daily job runs near the user-configured end-of-day time.
- Candidate filter first uses cheap keyword/source/time matching.
- AI matcher runs only on candidate title and summary pairs.
- Matched stories are pinned into an `Alerts` section in the app and surfaced at the top of the widget.

## Widget Interaction Requirements

Every widget action must provide immediate feedback:

- Power: update visible status text immediately.
- Refresh: show `Fetching` immediately, then success/failure.
- Hide: remove the story immediately.
- Share: open Android share sheet.
- Open story: open story detail or browser.

Android widgets do not have a desktop cursor, so use Android feedback instead:

- Ripple or pressed state where supported.
- Haptic feedback for destructive/lightweight actions if appropriate.
- Disabled styling when a control is unavailable.
- Toast or small app-side confirmation only when the result is not obvious.

## Implementation Phases

1. Create Android project skeleton under `android/`.
2. Add Room schema, DataStore preferences, repository layer, and fake feed data.
3. Build Compose news feed screen and story detail screen.
4. Add real RSS/API fetching through WorkManager.
5. Add runtime power model, visible app status, and auto power-off.
6. Add Android AppWidget with visible runtime/fetch status, story rows, refresh, power, and hide.
7. Add `NEW` state and refresh-clears-new behavior.
8. Add topic label generation with high-budget AI mode for labels only.
9. Add AI enrichment markers and story detail fields.
10. Add natural-language monitor configuration and end-of-day AI matching over titles and summaries.
11. Add alerts in app and widget.
12. Add Pixel 9 on-device build, install, logcat, and manual widget verification script/checklist.

## Acceptance Criteria

- The app builds on the Pixel 9 using Termux and Gradle.
- The debug APK installs on the same Pixel 9.
- The app opens to a news feed, not an admin dashboard.
- The Android home-screen widget can be added, resized, refreshed, and powered on/off.
- Pressing power changes visible `Runtime` status in the widget and app immediately.
- Pressing refresh changes visible `Fetch` status and clears stale `NEW` labels when stories did not change.
- Pressing hide removes the story immediately from the widget and app.
- Topic labels are meaningful news-topic labels.
- End-of-day monitor scans titles and summaries only, then raises an app/widget alert when a natural-language requirement matches.
- Runtime off stops fetch and AI work, including after an auto power-off timeout.

## Risks To Watch

- Android background limits can delay WorkManager jobs; use exact alarms only if absolutely necessary and justified.
- Glance may not support every desired interaction or layout; fall back to `RemoteViews` if needed.
- Running full Android builds in Termux can be fragile because SDK setup is manual.
- Local provider keys must be protected with Android Keystore-backed storage.
- A phone-only native runtime is not the same as the Mac Node backend, so API compatibility should be explicit rather than accidental.
