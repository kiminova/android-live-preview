#!/bin/zsh
# android-live-preview: puts the latest build of an Android app in front of you, in three places at once:
#
#   <Name> Light   an emulator in light mode
#   <Name> Dark    an emulator in dark mode
#   your phone     the app, over wireless debugging or a cable
#
# Run it from the project's folder. It reads `.android-preview` there (shell variables, below), creates the two
# emulators if they are missing, boots them, builds the app from the working tree, installs and launches it in both,
# then installs it on the first Android phone connected. A phone that can't be reached is a note at the end, never a
# failure: the emulators are refreshed all the same.
#
#   refresh.sh             build, install and launch everywhere
#   refresh.sh --no-build  reinstall the last build (the phone skipped)
#   refresh.sh --no-phone  the emulators only
#
# `.android-preview`:
#   NAME="MyApp"                    the emulators' names: "<NAME> Light", "<NAME> Dark" (required)
#   MODULE="app"                    the app's Gradle module (default: app)
#   VARIANT="debug"                 the build variant, e.g. "demoDebug" (default: debug)
#   LAUNCH_ARGS=(--ez demo true)    intent extras the app is launched with in the emulators (optional)
#   DEVICE="medium_phone"           the hardware profile, or "pixel_9" etc. (default: medium_phone)
#   IMAGE="system-images;android-36;google_apis_playstore;arm64-v8a"   (default: the newest installed)
#   PHONE="<serial>"                which phone, with more than one connected (default: the first)
set -euo pipefail

config=".android-preview"
[[ -f "$config" ]] || { echo "no $config here: run from the project's folder, or create one (see the top of $0)" >&2; exit 2; }
NAME="" MODULE="" VARIANT="" DEVICE="" IMAGE="" PHONE=""
LAUNCH_ARGS=()
source "./$config"
[[ -n "$NAME" ]] || { echo "$config sets no NAME" >&2; exit 2; }
MODULE="${MODULE:-app}" VARIANT="${VARIANT:-debug}" DEVICE="${DEVICE:-medium_phone}"

sdk="${ANDROID_HOME:-${ANDROID_SDK_ROOT:-$HOME/Library/Android/sdk}}"
[[ -d "$sdk" ]] || { echo "no Android SDK at $sdk (install Android Studio, or set ANDROID_HOME)" >&2; exit 1; }
export ANDROID_HOME="$sdk"
studio_jbr="/Applications/Android Studio.app/Contents/jbr/Contents/Home"
[[ -z "${JAVA_HOME:-}" && -d "$studio_jbr" ]] && export JAVA_HOME="$studio_jbr"
adb="$sdk/platform-tools/adb"
emulator="$sdk/emulator/emulator"
avd_home="${ANDROID_AVD_HOME:-$HOME/.android/avd}"

build=1 phone=1
for arg in "$@"; do
    case "$arg" in
        --no-build) build=0; phone=0 ;;
        --no-phone) phone=0 ;;
        *) echo "unknown option: $arg" >&2; exit 2 ;;
    esac
done

# The newest installed system image, preferring Google Play, then Google APIs, for this Mac's architecture.
if [[ -z "$IMAGE" ]]; then
    abi=$([[ "$(uname -m)" == arm64 ]] && echo arm64-v8a || echo x86_64)
    IMAGE=$(/usr/bin/python3 -c '
import os, re, sys
root, abi = sys.argv[1], sys.argv[2]
rank = {"google_apis_playstore": 2, "google_apis": 1}
found = []
base = os.path.join(root, "system-images")
for api in os.listdir(base) if os.path.isdir(base) else []:
    m = re.fullmatch(r"android-(\d+)(?:\.(\d+))?", api)
    if not m: continue
    for tag in os.listdir(os.path.join(base, api)):
        if os.path.isdir(os.path.join(base, api, tag, abi)):
            found.append(((int(m.group(1)), int(m.group(2) or 0), rank.get(tag, 0)), f"system-images;{api};{tag};{abi}"))
print(max(found)[1] if found else "")
' "$sdk" "$abi")
    [[ -n "$IMAGE" ]] || { echo "no $abi system image installed (Android Studio › Settings › Android SDK › SDK Platforms, Show Package Details)" >&2; exit 1; }
fi

# The emulator with this name, created if there is none. AVD ids can't hold spaces, so "MyApp Light" is MyApp_Light.
avd_for() {
    local display="$1" id="${1//[^A-Za-z0-9._-]/_}"
    if [[ ! -f "$avd_home/$id.ini" ]]; then
        local parts=("${(@s:;:)IMAGE}") dir="$avd_home/$id.avd"
        local api="${parts[2]}" tag="${parts[3]}" image_abi="${parts[4]}"
        [[ -d "$sdk/${IMAGE//;//}" ]] || { echo "system image $IMAGE is not installed" >&2; exit 1; }
        mkdir -p "$dir"
        print -l "avd.ini.encoding=UTF-8" "path=$dir" "path.rel=avd/$id.avd" "target=$api" > "$avd_home/$id.ini"
        # The same hardware as Android Studio's Medium Phone; the emulator fills in the rest on first boot.
        print -l \
            "AvdId=$id" "avd.ini.displayname=$display" "avd.ini.encoding=UTF-8" \
            "abi.type=$image_abi" "hw.cpu.arch=${image_abi%%-*}" "hw.cpu.ncore=4" \
            "image.sysdir.1=${IMAGE//;//}/" "tag.id=$tag" "target=$api" \
            "PlayStore.enabled=$([[ $tag == google_apis_playstore ]] && echo true || echo false)" \
            "hw.device.name=$DEVICE" "hw.device.manufacturer=Generic" \
            "hw.lcd.width=1080" "hw.lcd.height=2400" "hw.lcd.density=420" \
            "skin.name=1080x2400" "skin.path=1080x2400" "skin.dynamic=yes" "showDeviceFrame=yes" \
            "hw.ramSize=2048" "vm.heapSize=336" "disk.dataPartition.size=6G" \
            "hw.keyboard=yes" "hw.mainKeys=no" "hw.gpu.enabled=yes" "hw.gpu.mode=auto" \
            "hw.initialOrientation=portrait" "fastboot.forceFastBoot=yes" > "$dir/config.ini"
        echo "created $display ($id, $IMAGE)" >&2
    fi
    echo "$id"
}

# The serial (emulator-5554) of a running emulator, by its AVD id; empty if it isn't running.
serial_of() {
    local s
    for s in ${(f)"$("$adb" devices | awk '$1 ~ /^emulator-/ { print $1 }')"}; do
        [[ "$("$adb" -s "$s" emu avd name 2> /dev/null | head -1 | tr -d '\r')" == "$1" ]] && { echo "$s"; return; }
    done
    return 0
}

# Starts an emulator in its own window, unless it's running, and waits for it to finish booting.
boot() {
    local id="$1" serial port
    serial=$(serial_of "$id")
    if [[ -z "$serial" ]]; then
        local used="$("$adb" devices | awk '$1 ~ /^emulator-/ { print $1 }')"
        for port in {5554..5584..2}; do
            [[ "$used" == *"emulator-$port"* ]] || break
        done
        echo "booting $id" >&2
        nohup "$emulator" -avd "$id" -port "$port" > "$avd_home/$id.avd/live-preview.log" 2>&1 &!
        serial="emulator-$port"
    fi
    local waited=0
    "$adb" -s "$serial" wait-for-device
    until [[ "$("$adb" -s "$serial" shell getprop sys.boot_completed 2> /dev/null | tr -d '\r')" == 1 ]]; do
        (( waited += 2 ))
        (( waited > 300 )) && { echo "$id did not boot in 5 minutes (see $avd_home/$id.avd/live-preview.log)" >&2; exit 1; }
        sleep 2
    done
    echo "$serial"
}

light_id=$(avd_for "$NAME Light")
dark_id=$(avd_for "$NAME Dark")
light=$(boot "$light_id")
dark=$(boot "$dark_id")
"$adb" -s "$light" shell cmd uimode night no > /dev/null
"$adb" -s "$dark" shell cmd uimode night yes > /dev/null

# The APK of the variant, found through the output metadata Gradle writes next to it.
apk_path() {
    /usr/bin/python3 -c '
import glob, json, os, sys
module, variant = sys.argv[1], sys.argv[2]
for meta in glob.glob(os.path.join(module, "build/outputs/apk/**/output-metadata.json"), recursive=True):
    data = json.load(open(meta))
    if data.get("variantName") == variant and data.get("elements"):
        print(os.path.join(os.path.dirname(meta), data["elements"][0]["outputFile"])); break
' "$MODULE" "$VARIANT"
}

if (( build )); then
    [[ -x ./gradlew ]] || { echo "no ./gradlew here: run from the project's root folder" >&2; exit 2; }
    echo "building $MODULE ($VARIANT)" >&2
    ./gradlew -q ":${MODULE}:assemble${VARIANT[1]:u}${VARIANT[2,-1]}"
fi
apk=$(apk_path)
[[ -n "$apk" && -f "$apk" ]] || { echo "no $VARIANT build of $MODULE found; run without --no-build" >&2; exit 1; }
aapt2=$(ls -d "$sdk"/build-tools/*/aapt2 | sort -V | tail -1)
package=$("$aapt2" dump packagename "$apk")

for serial in $light $dark; do
    "$adb" -s "$serial" shell am force-stop "$package" 2> /dev/null || true
    "$adb" -s "$serial" install -r -t "$apk" > /dev/null
    activity=$("$adb" -s "$serial" shell cmd package resolve-activity --brief \
        -a android.intent.action.MAIN -c android.intent.category.LAUNCHER "$package" | tail -1 | tr -d '\r')
    "$adb" -s "$serial" shell am start -W -n "$activity" "${LAUNCH_ARGS[@]}" > /dev/null
done

commit="$(git rev-parse --short HEAD 2> /dev/null || echo 'no git')$(git diff --quiet 2> /dev/null || echo ' with uncommitted changes')"
echo "$NAME Light $light, $NAME Dark $dark: running $commit"

# The phone. Any failure here is a note, not an error.
(( phone )) || exit 0
first_phone() { "$adb" devices | awk 'NR > 1 && $2 == "device" && $1 !~ /^emulator-/ { print $1; exit }'; }
device="$PHONE"
if [[ -z "$device" ]]; then
    device=$(first_phone)
    if [[ -z "$device" ]]; then
        # A phone paired for wireless debugging advertises itself; connect to it if adb hasn't on its own.
        for address in ${(f)"$("$adb" mdns services 2> /dev/null | awk '/_adb-tls-connect/ { print $NF }')"}; do
            "$adb" connect "$address" > /dev/null 2>&1 || true
        done
        device=$(first_phone)
    fi
fi
[[ -n "$device" ]] || { echo "NOTE phone: no Android phone connected (pair it once for wireless debugging, or plug it in); the phone was not updated"; exit 0; }

log="$avd_home/live-preview-phone.log"
"$adb" -s "$device" install -r -t "$apk" > "$log" 2>&1 \
    || { echo "NOTE phone: installing on $device failed (see $log; keep the phone on the same network or a cable, and run it again)"; exit 0; }
model=$("$adb" -s "$device" shell getprop ro.product.model 2> /dev/null | tr -d '\r')
echo "Your phone (${model:-$device}): $package running $commit"
