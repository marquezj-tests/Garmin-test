# ESS Public OPI for Garmin Forerunner 265

A Connect IQ **device app** that pulls the European Spallation Source public
operations screen (<https://pos.ess.eu/>) onto a Garmin Forerunner 265 and
shows it across six pages: beam current, beam power, permits, plant status,
operating modes and the control room's message of the day.

The feasibility study behind it — what the web page actually is, what its data
interface looks like, and why the app is built this way — is in
[`docs/STUDY.md`](docs/STUDY.md). **Read the "Verification status" section
there before trusting this code: it has not been compiled.**

## Layout

| Path | Purpose |
| --- | --- |
| `manifest.xml` | App type, target products (`fr265`, `fr265s`), permissions |
| `monkey.jungle` | Build configuration |
| `source/EssConfig.mc` | Endpoints and the EPICS PV names behind each reading |
| `source/EssPv.mc` | Decoders for the gateway's pvAccess-flavoured JSON |
| `source/EssApi.mc` | `makeWebRequest` wrapper and error mapping |
| `source/EssModel.mc` | One snapshot plus the dashboard's derived quantities |
| `source/EssCache.mc` | Storage key shared between app and glance |
| `source/EssDraw.mc` | Round-screen drawing helpers |
| `source/EssPageView.mc` | The six-page foreground view |
| `source/EssPageDelegate.mc` | Button and swipe handling |
| `source/EssGlanceView.mc` | Glance tile |
| `source/EssOpiApp.mc` | `AppBase` entry points |
| `tools/make_icon.py` | Regenerates the 60x60 launcher icon |

## Controls

| Input | Action |
| --- | --- |
| Up / Down, or swipe up / down | Previous / next page |
| START (or tap) | Refresh now |
| BACK | Exit |

The foreground view also re-polls every 30 s on a timer.

## Building

You need the Connect IQ SDK (9.3.0 was used for this study), a JRE 17+, and the
`fr265` device files. The SDK Manager installs the device files; the SDK zip
alone does **not** contain them.

```sh
# 1. Point the SDK at itself (once per machine)
mkdir -p ~/.Garmin/ConnectIQ
echo /path/to/connectiq-sdk-lin-9.3.0 > ~/.Garmin/ConnectIQ/current-sdk.cfg
export PATH="/path/to/connectiq-sdk-lin-9.3.0/bin:$PATH"

# 2. Generate a developer key (once)
openssl genrsa -out developer_key.pem 4096
openssl pkcs8 -topk8 -inform PEM -outform DER \
    -in developer_key.pem -out developer_key.der -nocrypt

# 3. Build for the Forerunner 265
monkeyc -f monkey.jungle -d fr265 -y developer_key.der -o bin/EssOpi.prg -l 2
```

`-l 2` is the "informative" Monkey Types level. Start there; `-l 3` (strict)
is the goal but has not been exercised — see the study.

## Running in the simulator

```sh
connectiq &                 # start the simulator
monkeydo bin/EssOpi.prg fr265
```

The simulator's **Settings → Bluetooth → Phone connected** toggle has to be on,
or every web request fails with `BLE_CONNECTION_UNAVAILABLE`.

## Sideloading onto a watch

Build an unsigned-for-store `.prg` as above, connect the watch over USB, and
copy it into `GARMIN/APPS/` on the mass-storage volume. Eject and restart the
watch; the app appears in the activity/app list.

## Attribution

All data belongs to the European Spallation Source ERIC and comes from their
public operations gateway. This project is unaffiliated with ESS and with
Garmin. See the "Legal and etiquette" section of the study before publishing
anything built from it.
