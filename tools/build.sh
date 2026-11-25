#!/usr/bin/env bash
# Build ESS Public OPI for the Forerunner 265.
#
# Locates the Connect IQ SDK and device files the way the SDK Manager installs
# them on Linux and macOS, generates a developer key on first run, then
# compiles. Pass a device id as $1 to build for something other than fr265.
set -u

DEVICE="${1:-fr265}"
TYPECHECK="${TYPECHECK:-2}"
OUT="bin/EssOpi-${DEVICE}.prg"

die() { printf '\n%s\n' "$*" >&2; exit 1; }

# ---- Where the SDK Manager keeps things on each platform -------------------
case "$(uname -s)" in
    Darwin) CIQ_HOME="$HOME/Library/Application Support/Garmin/ConnectIQ" ;;
    *)      CIQ_HOME="$HOME/.Garmin/ConnectIQ" ;;
esac

# ---- Find the SDK ---------------------------------------------------------
SDK="${CIQ_SDK:-}"
if [ -z "$SDK" ] && [ -f "$CIQ_HOME/current-sdk.cfg" ]; then
    SDK="$(tr -d '\r\n' < "$CIQ_HOME/current-sdk.cfg")"
fi
if [ -z "$SDK" ]; then
    # Fall back to the newest SDK the manager has unpacked.
    SDK="$(ls -d "$CIQ_HOME"/Sdks/*/ 2>/dev/null | sort -V | tail -1)"
fi
[ -n "$SDK" ] || die "No Connect IQ SDK found.
Looked at \$CIQ_SDK, $CIQ_HOME/current-sdk.cfg and $CIQ_HOME/Sdks/.
Install one with the SDK Manager, or set CIQ_SDK=/path/to/sdk."

SDK="${SDK%/}"
MONKEYC="$SDK/bin/monkeyc"
[ -x "$MONKEYC" ] || die "No monkeyc at $MONKEYC (is \$CIQ_SDK pointing at the SDK root?)"

# ---- Check the device files exist -----------------------------------------
DEVDIR="$CIQ_HOME/Devices/$DEVICE"
if [ ! -d "$DEVDIR" ]; then
    die "No device files for '$DEVICE' at $DEVDIR.
These do NOT ship in the SDK zip. Open the GUI SDK Manager, sign in to your
Garmin developer account, and install the device - then re-run this script.
Devices currently installed:
$(ls "$CIQ_HOME/Devices" 2>/dev/null | sed 's/^/  /' || echo '  (none)')"
fi

# ---- Developer key --------------------------------------------------------
KEY="${CIQ_KEY:-developer_key.der}"
if [ ! -f "$KEY" ]; then
    echo "==> Generating a developer key at $KEY (keep it; .gitignore excludes it)"
    command -v openssl >/dev/null || die "openssl not found; cannot generate a developer key."
    openssl genrsa -out developer_key.pem 4096 2>/dev/null \
        && openssl pkcs8 -topk8 -inform PEM -outform DER \
               -in developer_key.pem -out "$KEY" -nocrypt \
        || die "Key generation failed."
fi

# ---- Build ----------------------------------------------------------------
mkdir -p bin
echo "==> SDK      $SDK ($(cat "$SDK/bin/version.txt" 2>/dev/null || echo 'unknown version'))"
echo "==> Device   $DEVICE"
echo "==> Typecheck -l $TYPECHECK"
echo

set -x
"$MONKEYC" -f monkey.jungle -d "$DEVICE" -y "$KEY" -o "$OUT" -l "$TYPECHECK" -w
status=$?
set +x

echo
if [ $status -eq 0 ]; then
    echo "==> Built $OUT"
    echo "    Run it with:  $SDK/bin/monkeydo $OUT $DEVICE"
    echo "    (start the simulator first: $SDK/bin/connectiq &"
    echo "     and enable Settings > Bluetooth > Phone connected, or every"
    echo "     web request returns BLE_CONNECTION_UNAVAILABLE)"
else
    echo "==> Build failed (exit $status)"
fi
exit $status
