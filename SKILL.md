---
name: android-live-preview
description: Keep two Android emulators (one in light mode, one in dark) and the developer's Android phone on the latest build of the app, refreshed after every change, so they can look at the work at any moment. Use at the start of a session in an Android project and after every change you build, when the user wants to see the app on their emulators or phone, or asks to set up a live preview.
---

# Claude Android preview

The developer wants to see your work at any moment, in three places, always on the latest build:

- **`<Name> Light`**: an emulator in light mode.
- **`<Name> Dark`**: an emulator in dark mode.
- **Their Android phone**: the app, over wireless debugging or a cable.

`scripts/refresh.sh` in this skill's folder does all of it. Run it from the project's root folder (the one with `gradlew`).

## First time in a project

The script reads `.android-preview` in the project's folder. If there is none:

1. Find the app module: the one whose `build.gradle(.kts)` applies `com.android.application` (usually `app`).
2. Pick the variant: `debug`, or with product flavors something like `demoDebug`. If it's not obvious, ask the user which.
3. Write `.android-preview`:

   ```bash
   NAME="MyApp"                    # the emulators: "MyApp Light", "MyApp Dark"
   # MODULE="app"
   # VARIANT="debug"
   # LAUNCH_ARGS=(--ez demo true)  # intent extras, e.g. to run against made-up data
   ```

4. Ask the user whether to commit it, so their team gets the same setup, or keep it to themselves (add it to `.gitignore`).

## Every session

1. **At the start**, before anything else, run `scripts/refresh.sh` (from this skill's folder, in the project's folder). It creates the two emulators if they're missing, boots them, builds the app from the working tree, and installs and launches it in both. Then it installs the app on the first Android phone connected.
2. **After every change you build**, run it again. Tell the user which commit the devices run: the script's last lines say so.
3. **If a line starts with `NOTE phone:`**, the phone wasn't updated. Pass the note on as it is, and don't retry in a loop. The emulators are refreshed all the same.

## Rules

- Use these two emulators and no others. Don't create or boot another emulator for a test, a recording or a check. If another one is running, shut it down (`adb -s <serial> emu kill`). Never delete an emulator.
- Don't switch an emulator's appearance by hand: the script sets light and dark on every run.
- Options: `--no-phone` (the emulators only), `--no-build` (reinstall the last build, the phone skipped).

## If the phone isn't updated

- **"no Android phone connected":** the phone has never been paired with this Mac, or it's off the Mac's network. Pair it once for wireless debugging (see the README). After that adb finds it again on the same network. A cable always works.
- **Installing failed:** the log path is in the note. `INSTALL_FAILED_UPDATE_INCOMPATIBLE` means a copy signed with another key is on the phone (from another Mac, or the store); ask the user before uninstalling it, because that deletes the app's data.
