# Android live preview

**See every change your coding agent makes, on a light emulator, a dark one and your own Android phone, without asking.**

A skill for [Claude Code](https://claude.com/claude-code), and the Android sibling of [ios-live-preview](https://github.com/kiminova/ios-live-preview). Install it, and in any Android project your agent keeps three devices on the latest build of your working tree:

- **An emulator in light mode** and **one in dark mode**, each in its own window, so you check both appearances at a glance.
- **Your Android phone**, updated over Wi-Fi with wireless debugging, or over a cable.

It does this at the start of every session and again after every change it builds. You look up from the conversation and the change is already running. No "can you run it so I can see?", and no Run button in Android Studio.

## What you get

- **Always the latest build:** the agent rebuilds and reinstalls after every change, and tells you which commit the devices run.
- **Light and dark at once:** two named emulators, `<Name> Light` and `<Name> Dark`, created the first time and reused after that. The agent is told not to clutter your Mac with others.
- **Your phone too:** the app on the first Android phone connected. If the phone can't be reached, you get a one-line note instead of a failed session, and the emulators are updated anyway.
- **Made-up data, if you want it:** intent extras of your choice, for example to run against a demo or fixture mode so nothing reaches a server.
- **Shared with the team in one file:** a small `.android-preview` in your project names the app. Commit it and everyone's agent sets up the same thing.

## Install

```bash
git clone https://github.com/kiminova/android-live-preview ~/.claude/skills/android-live-preview
```

That's it. Claude Code picks the skill up in your next session. To set it up for one project only, clone it into that project's `.claude/skills/` folder instead.

## First run

Open Claude Code in your Android project and say something like *"Set up the live preview"*. The agent finds your app module and variant, asks if it isn't sure, and writes `.android-preview`:

```bash
NAME="MyApp"                  # the emulators: "MyApp Light" and "MyApp Dark"
MODULE="app"                  # optional: the app's Gradle module (default: app)
VARIANT="demoDebug"           # optional: the build variant (default: debug)
LAUNCH_ARGS=(--ez demo true)  # optional: intent extras the app is launched with in the emulators
```

Optional too: `DEVICE` for another hardware profile than Android Studio's Medium Phone, `IMAGE` for another system image than the newest one installed (for example `"system-images;android-35;google_apis;arm64-v8a"`), and `PHONE` (a serial from `adb devices`) when more than one phone is connected.

The app reads the extras in its launch activity, for example `intent.getBooleanExtra("demo", false)`.

From then on it runs by itself. You can also run it yourself:

```bash
~/.claude/skills/android-live-preview/scripts/refresh.sh             # everything
~/.claude/skills/android-live-preview/scripts/refresh.sh --no-phone  # the emulators only
~/.claude/skills/android-live-preview/scripts/refresh.sh --no-build  # reinstall the last build
```

## Your phone

Once per phone:

1. Turn on **Developer options**: Settings › About phone, tap **Build number** seven times.
2. In Settings › System › Developer options, turn on **Wireless debugging**.
3. Pair it: in Android Studio, open **Device Manager › Pair Devices Using Wi-Fi** and scan the QR code with the phone. Or, on the phone, tap **Pair device with pairing code** and run `adb pair <ip>:<port>` with the code it shows.

After that it updates over Wi-Fi, as long as the phone and the Mac are on the same network and Wireless debugging is on. The script reconnects a paired phone that adb hasn't found by itself. Android turns Wireless debugging off when the phone changes network, so turn it on again after that. A cable always works: plug it in, unlock the phone, and allow USB debugging.

## Requirements

- macOS with [Android Studio](https://developer.android.com/studio), and an Android system image for your Mac (Settings › Languages & Frameworks › Android SDK). The emulators are created without Android Studio's command-line tools.
- A project with a Gradle wrapper (`gradlew`) and an app module.
- About 4–6 GB of free memory for the two emulators.
- [Claude Code](https://claude.com/claude-code). The script itself is plain zsh, so it works without it too.

## Differences from the iOS version

- **No App Clip.** Android's closest match, Instant Apps, was retired by Google in 2025.
- **One build for everything.** The debug APK runs on the emulators and the phone alike, so the phone isn't built separately.
- **Launch arguments are intent extras** (`--ez`, `--es`, `--ei` and the rest of `am start`), not process arguments.
