# Building a Garmin Forerunner 265 app that displays pos.ess.eu

A feasibility study and design record. Everything below was measured or read
from primary sources (the live site, the Connect IQ SDK 9.3.0, and Garmin's
device reference) on 2026-11-25, not recalled.

---

## 1. What pos.ess.eu actually is

`https://pos.ess.eu/` is the **Public OPI** (operator interface) of the
**European Spallation Source ERIC** in Lund, Sweden — "realtime operations
information directly from the Control Room", per its own `og:description`.

It is **not** a hand-written page. It is an instance of the open-source
[Freeboard](https://github.com/Freeboard/freeboard) dashboard framework:
Knockout + jQuery + gridster, loading a dashboard definition and polling a
backend. That matters enormously, because it means **the page is a thin client
over a clean JSON API, and the watch app can talk to that API directly instead
of scraping HTML.**

The dashboard definition is public at `https://pos.ess.eu/dashboard.json`
(35 KB). It declares the datasources, the widgets, and — critically — the exact
JavaScript expressions that turn raw control-system values into the figures the
page shows. The watch app reproduces those expressions.

`https://pos.ess.eu/menu/available-screens.html` lists the sibling screens:
Access Status, PSS and Permits, Beam Diagnostics, FBIS, SCL Temperatures and
Levels, Test Stand 2, Oxygen Deficiency Hazard, RFQ, Vacuum System, Cooling
Water System. Each has its own `dashboard.json` with its own PV sets, so the
app can be extended to any of them without new plumbing. Two entries
("Contacts", "PV Search Engine") are marked local-network only.

### Backend

A FastAPI service behind nginx and Cloudflare, exposing an EPICS pvAccess
gateway. Three endpoints are used by the public screens:

| Endpoint | Purpose |
| --- | --- |
| `GET /data/api/v2/pvget/<pv>[,<pv>...]` | Live values for one or more process variables |
| `GET /data/api/v1/archiver/<pvs>/<seconds>/<points>/freeboard` | Historical series for the trend plots |
| `GET /data/-/gwhealth/NSO:Ops:SID` | Gateway health: `{"gwstatus":"OK"}` |

**No authentication, no API key, no cookie.** `/data/docs` serves a Swagger UI
shell, but it points at `/openapi.json`, which nginx does not expose, so there
is no machine-readable schema — the shapes below were derived by probing.

---

## 2. The data interface in detail

### Request

PV names go in the **path**, comma-separated, unencoded. They contain colons
and sometimes double colons (`FBIS::beam_permit_ok`). This is why the app
appends them to the URL itself rather than passing a `parameters` dictionary to
`makeWebRequest`, which would percent-encode the separators.

Suffix modifiers exist and are used by the other screens:

| Modifier | Meaning |
| --- | --- |
| `.[start:step:end]` | Array slice, e.g. `...ArrayData.[0:800:-1]` |
| `.{"dec":{"n":30}}` | Decimate to every nth element |
| `.{dbnd:{rel:1.0}}` | Relative deadband |

**Field projection is not supported.** `pv.value`, `pv.field(value)` and
`pv.{"fields":["value"]}` all fail (502, or echo back as a bogus PV name), so
the response cannot be slimmed server-side. Payload size is fixed at roughly
**500–770 bytes per PV**, which drives the memory design in §5.

### Response

A JSON object keyed by PV name. `Content-Type: application/json`, which is what
Connect IQ needs in order to parse it automatically.

`value` takes **three different shapes**, and each needs its own decoder:

```jsonc
// numeric
"NSO-BProd::BFreqMeas": {
  "value": 0.3333333333333333,
  "alarm":     { "severity": 0, "status": 0, "message": "" },
  "timeStamp": { "secondsPastEpoch": 1795602599, "nanoseconds": 191395834 },
  "display":   { "units": "Hz", "precision": 3, "description": "Beam Frequency measured" },
  "control": { ... }, "valueAlarm": { ... }
}

// enum: an index into a choice list
"FBIS::beam_permit_ok": {
  "value": { "index": 0, "choices": ["NOK", "OK"] },
  "alarm": { "severity": 2, "status": 1, "message": "STATE" },
  "timeStamp": { ... }
}

// string: an EPICS char array, NOT a JSON string
"NSO:Ops:Msg": {
  "value": [76,111,110,103,32,80,117,108,115,101,32,111,110,32,116,104,101,32,68,117,109,112],
  ...                      // -> "Long Pulse on the Dump"
}
```

Three quirks worth designing around:

1. **Char-array strings.** The message of the day arrives as character codes
   and has to be rebuilt (`EssPv.text()`). A naive `data[pv]["value"]` renders
   a list of integers.
2. **Cold PVs are queued.** A PV the gateway has not been asked for recently
   answers `{"value":null,"status":"queued","monitor_wait_seconds":0.0}` and
   carries a real value only on a subsequent request. The app treats this as
   "no value yet" and keeps the previous reading (`EssPv.isQueued()`).
3. **Enum records may omit `display`.** Decoders must tolerate missing
   `display`, `alarm` and `timeStamp` blocks rather than assuming the full
   numeric shape.

### Measured cost

| Request | URL length | Response | Server latency |
| --- | --- | --- | --- |
| Full app set, 29 PVs | 934 chars | 15.1–15.2 KB | 0.54–0.92 s |
| Glance set, 3 PVs | 104 chars | 1.2 KB | 0.92 s |
| Gateway health | 61 chars | 17 bytes | — |

The web dashboard polls its datasources every 5–10 s. The watch app polls every
30 s in the foreground, which is a deliberate reduction (see §8).

### Reproducing the dashboard's derived values

The dashboard does real arithmetic in widget JavaScript. The app ports it
verbatim so the watch agrees with the web page:

- **Beam destination** (`TD-M:Ctrl-SCE-1:BDest-Sel`, enum index 0–7) selects
  which of eight beam-current PVs and seven pulse-width PVs are the live ones.
  Destination 0 (ion source) has no pulse-width source and reports zero.
- **Beam current** and **pulse length** are clamped at zero, because the
  faraday-cup readings drift slightly negative with no beam (observed:
  −0.047 mA on LEBT).
- **Average beam power** is `E[MeV] × I[mA] × t[ms] × f[Hz]`, which lands in
  watts because MeV·mA is kilowatts instantaneous and ms·Hz is the duty factor
  in units of 1e−3.
- **Beam energy** is a lookup table on the destination index, not a PV.

One upstream inconsistency is preserved rather than silently fixed: the
dashboard's *power* calculation uses 216 MeV and 856 MeV for destinations 6 and
7, while its *displayed* "Estimated Beam Energy" widget uses 361.5 MeV and
869 MeV for the same destinations. `EssConfig.powerEnergies()` and
`EssConfig.displayEnergies()` hold both tables, with a comment. The watch
therefore matches the web page, including where the web page disagrees with
itself.

The indicator polarity also has one exception: every red/amber/green widget
treats enum index 1 as good, **except** "OP Beam Request"
(`TD-M:Ctrl-SCE-1:SwBInhibit-Sel`), where index 0 is good because the PV is an
inhibit. `EssModel.indicator()` special-cases it.

---

## 3. The target device

From Garmin's device reference for the Forerunner 265 (`fr265`) and the
compatible-devices table:

| Attribute | Value |
| --- | --- |
| Device ID | `fr265` (and `fr265s` for the 41 mm sibling) |
| Connect IQ version | **5.2** |
| Screen | 416 × 416 round AMOLED, 65536 colours (`fr265s`: 360 × 360) |
| Touch | Yes |
| Buttons | enter, up, menu, down, esc |
| Launcher icon | 60 × 60 |
| Part number | 006-B4257-00 |
| Wi-Fi | Yes |

Memory limits per app type — the single most important design constraint:

| App type | Limit | Note |
| --- | --- | --- |
| Watch App (Device App) | **768 KB** | |
| Widget | 786432 | **Not offered on this device** (see §4) |
| Glance | **64 KB** | |
| Background | **64 KB** | Requires `Background` permission |
| Data Field | 256 KB | |
| Watch Face | 128 KB | |

Available fonts (heights in pixels): `FONT_XTINY` 34, `FONT_TINY` 43,
`FONT_SMALL` 50, `FONT_MEDIUM` 58, `FONT_LARGE` 67, `FONT_NUMBER_MILD` 95,
`FONT_NUMBER_MEDIUM` 117, `FONT_NUMBER_HOT` 140, `FONT_GLANCE` 39,
`FONT_GLANCE_NUMBER` 50.

---

## 4. Which app type, and why

Garmin's compatible-devices table lists the FR265's supported app types as
**Audio Content, Data Fields, Device Apps, Watch Faces**. *Widgets are absent.*
On Connect IQ 5 wearables the widget carousel is gone; its role is taken by the
glance list plus device apps. The device reference's own note is explicit:
glance support should be "built as Watch App or Widget", and Widget "requires
4.x SDK".

So: **`type="watch-app"` (a Device App) with a `GlanceView`.** A widget would be
the wrong container on this hardware, and a data field would be wrong because
this data has nothing to do with a recorded activity.

`minApiLevel` is set to **4.2.0** — the oldest level that still has
`GlanceView` (3.1.0), `makeWebRequest` (1.3.0) and `Application.Storage`
(2.4.0), while covering every current CIQ 4/5 wearable should the product list
be widened later. The FR265 ships 5.2, comfortably above it.

Only one permission is needed: **`Communications`**. No `Background`, because
the app does not register a background service (see §6).

### Network path

`Communications.makeWebRequest()` is documented to work "when connected to
WiFi or a mobile device over Bluetooth". In practice almost every request will
go over BLE to the Garmin Connect app on the phone, which proxies it. This is
fine for the target:

- The site is HTTPS behind Cloudflare with an ordinary public certificate, so
  it passes the device's trust store.
- It returns `application/json`, so `HTTP_RESPONSE_CONTENT_TYPE_JSON` parses
  the body into a `Dictionary` with no manual parsing.
- 15 KB is well inside what the BLE pipe will carry, though it is the slow part
  of the round trip — expect seconds, not the sub-second server latency.

Failures do **not** arrive as HTTP status codes. `makeWebRequest` reports
negative `BLE_*` / `NETWORK_*` codes, so `EssApi.describeError()` maps the ones
that can actually happen here (`BLE_CONNECTION_UNAVAILABLE`,
`BLE_HOST_TIMEOUT`, `BLE_QUEUE_FULL`, `BLE_REQUEST_TOO_LARGE`,
`NETWORK_RESPONSE_TOO_LARGE`, `NETWORK_RESPONSE_OUT_OF_MEMORY`,
`INVALID_HTTP_BODY_IN_NETWORK_RESPONSE`, …) into something that fits on a
416 px screen.

---

## 5. Architecture

```
EssOpiApp  (AppBase)
├── getInitialView()  -> EssPageView + EssPageDelegate     foreground, 768 KB
└── getGlanceView()   -> EssGlanceView                     glance, 64 KB

EssPageView ──uses──> EssModel ──uses──> EssPv  (decoders)
     │                   │                EssConfig (endpoints, PV tables)
     │                   └──writes──> EssCache (Application.Storage)
     ├──uses──> EssApi  (makeWebRequest + error mapping)
     └──uses──> EssDraw (round-screen layout helpers)

EssGlanceView ──uses──> EssCache, EssApi, EssPv, EssConfig, EssDraw
```

**One request feeds every page.** The six pages are drawn by a single view
switching on a page index, rather than six views each fetching. A page change
costs nothing; only the 30 s timer and the START button cause traffic.

**The glance is memory-bounded by design.** It cannot use `EssModel`, because
pulling in the full 29-PV response (15 KB of JSON, several times that once
parsed into Monkey C objects) against a 64 KB pool is not viable. Instead it:

1. draws the three-field summary the foreground app cached in
   `Application.Storage`, so something useful appears immediately, then
2. issues its own **three-PV, 1.2 KB** request to freshen the headline.

The FR265 is a music-capable wearable, which per Garmin's glance documentation
puts it in the "live UI update" class: the glance stays resident and
`WatchUi.requestUpdate()` works, rather than the filesystem-cached
"background UI update" path that non-music devices get.

**Layout is fraction-based.** Every coordinate in `EssDraw` is a fraction of
`dc.getWidth()`/`getHeight()`, with 10–14 % horizontal margins so text clears
the bezel of a round display. The same code therefore lays out on the 416 px
FR265 and the 360 px FR265s with no per-device resources.

**Palette is AMOLED-aware.** Black field (nearly free on this panel), white
values, amber accents, green/red indicators. Alarm severity from the PV's own
`alarm.severity` colours the headline reading: white when clear, amber on a
minor alarm, red on major or invalid.

### Pages

| Page | Content |
| --- | --- |
| BEAM CURRENT | Destination, beam current (hero), pulse length, repetition rate |
| BEAM POWER | Average beam power (hero), estimated energy, repetition rate |
| PERMITS | Beam permit, beam request, PSS ready, SHC ready |
| PLANT | 4.5 K cryo, 2 K cryo, magnetron, high voltage |
| MODES | Beam mode, PSS mode, RF frequency, source frequency |
| CONTROL ROOM | Message of the day, word-wrapped |

The footer carries page position, data age in seconds, a `...` while a request
is in flight, `GW KO` if the gateway reports itself unhealthy, and `!` if the
last attempt failed while older data is still on screen.

---

## 6. Deliberate omissions

**No background service.** `Background.registerForTemporalEvent()` is capped at
one wake every five minutes, the background pool is 64 KB, and a service that
fails to exit within 30 s is killed. It would only serve to keep the glance
warm while the app is closed — real but modest value against a permanent
battery and complexity cost. The glance refreshing itself on display covers
the same ground. If it is wanted later: annotate the service delegate and
everything it touches `(:background)`, add the `Background` permission, and
fetch no more than the three-PV glance set.

**No trend plots.** `/data/api/v1/archiver/.../freeboard` would supply them,
but a 2048-point series is far more data than a watch should pull over BLE, and
far more pixels than 416 px of round screen can use well. A short sparkline
from a 32-point, 5-minute window is the sane version of this feature.

**No settings UI.** Which PVs to show is a code-level decision for now. Garmin
app settings (`Properties`) would be the place to let a user pick a screen.

---

## 7. Toolchain

- **SDK**: the Linux SDK is listed in a machine-readable index at
  `https://developer.garmin.com/downloads/connect-iq/sdks/sdks.json`, which the
  SDK Manager binary reads. The newest entry at time of writing is **9.3.0**
  (released 2026-10-20), downloadable as
  `connectiq-sdk-lin-9.3.0-2026-10-20-95888f262.zip` (215 MB) from
  `https://developer.garmin.com/downloads/connect-iq/sdks/<filename>`.
- **Device files are not in the SDK zip.** The zip contains `bin/` (monkeyc,
  monkeydo, connectiq simulator, barrelbuild), `doc/`, `samples/` and
  `resources/device-reference/` — but the per-device `compiler.json` /
  `simulator.json` that `monkeyc -d fr265` needs are fetched separately by the
  SDK Manager from `api.gcs.garmin.com/ciq-product-onboarding/devices`, which
  requires a signed-in Garmin developer account. **Running the GUI SDK Manager
  once, with a developer account, is an unavoidable step.**
- **Java**: the toolchain is JVM-based (`monkeybrains.jar`). JDK 17+ works.
- **Developer key**: a 4096-bit RSA key in PKCS#8 DER form, generated with
  `openssl`; see the README. The same key must be reused for every build of an
  app that will be updated in the store.
- **Build**: `monkeyc -f monkey.jungle -d fr265 -y developer_key.der -o bin/EssOpi.prg -l 2`
- **Run**: `connectiq &` then `monkeydo bin/EssOpi.prg fr265`. Turn on
  Settings → Bluetooth → Phone connected in the simulator or every request
  returns `BLE_CONNECTION_UNAVAILABLE`.
- **Sideload**: copy the `.prg` to `GARMIN/APPS/` over USB mass storage.

The type-check level is a compiler flag (`-l 0..3`), not a jungle setting; the
VS Code Monkey C extension exposes the same thing as `monkeyC.typeCheckLevel`.

---

## 8. Verification status — read this

**What was verified against primary sources:**

- Every endpoint, response shape and quirk in §2 was exercised against the live
  service, and every size and latency figure was measured.
- Every PV name, destination table, energy table, indicator polarity and
  derived formula in the app was read out of the live `dashboard.json`.
- Every Connect IQ API used (`makeWebRequest` options and error constants,
  `GlanceView`, `AppBase.getGlanceView`, `Application.Storage.setValue/getValue`,
  `Timer.Timer.start`, `Dc.drawText/fillCircle/getTextWidthInPixels/getFontHeight/setAntiAlias`,
  `Graphics.fitTextToArea`, `Lang.Number.toChar`, `Lang.Char.toString`,
  `Lang.String.toCharArray`, `Lang.Array.indexOf`, `DeviceSettings.connectionAvailable`
  and `.phoneConnected`) was checked against the SDK 9.3.0 API documentation
  shipped inside the SDK.
- The manifest matches the schema and idioms of SDK 9.3.0's own modern samples,
  and `fr265` is confirmed as a valid product ID in one of them.

**What was NOT verified: the code has never been compiled or run.** The SDK was
downloaded and unpacked successfully, but executing its binaries (`monkeyc`,
`connectiq`) was blocked by this environment's sandbox policy. So:

- There are no compiler or type-checker results. Expect to fix syntax or typing
  nits on the first build. Start at `-l 2`, not `-l 3`.
- No screenshot exists. The layout numbers are reasoned from the documented
  font heights and screen geometry, not seen.
- **The one design decision that genuinely needs a compiler** is the `(:glance)`
  annotation split in `EssOpiApp`. Garmin documents that only annotated code is
  compiled into a restricted scope and that "you must decorate all related code
  with the annotation (including your Application class)", but does not say
  whether annotating a *class* pulls in its unannotated methods. The app class
  is therefore annotated `(:glance)` with `getGlanceView()` annotated too, and
  `getInitialView()` carries `(:typecheck(disableGlanceCheck))`. If the glance
  build still fails to resolve or overruns 64 KB, the fallbacks in order are:
  1. annotate the remaining foreground classes `(:glance)` as well (the app is
     small; the whole thing may simply fit in 64 KB), or
  2. drop `getGlanceView()` and ship the device app alone — the six pages are
     the substance of the app and do not depend on the glance at all.

---

## 9. Legal and etiquette

- **The data is ESS's.** This is a public, unauthenticated read-only interface,
  but that is not a licence. Anything published should credit the European
  Spallation Source ERIC and should not imply endorsement.
- `https://pos.ess.eu/robots.txt` allows `User-agent: *` on all paths but
  attaches Cloudflare content signals: `search=yes, ai-train=no, use=reference`,
  and explicitly disallows a list of AI training crawlers. A user-initiated
  watch app showing live values to its owner is a reference use, not crawling
  for training — but the signal is a stated reservation of rights and should be
  respected as written.
- **Poll conservatively.** The web page polls every 5–10 s because it is a
  control-room display on a wired network. A watch does not need that. 30 s in
  the foreground and nothing in the background is the design here; do not lower
  it without asking ESS.
- **Talk to ESS before any store release.** Garmin's app review guidelines
  cover third-party content and trademarks, and the app's entire value is
  someone else's live data under their name. Sideloading for personal use is a
  different matter from publishing.
- The app ID in `manifest.xml` is a placeholder; generate a fresh one for any
  real distribution.

---

## 10. Primary sources

- <https://pos.ess.eu/> — page, `dashboard.json`, `menu/available-screens.html`,
  `robots.txt`, and the `/data/api/v2/pvget`, `/data/api/v1/archiver` and
  `/data/-/gwhealth` endpoints
- <https://developer.garmin.com/connect-iq/device-reference/fr265/> — FR265
  attributes, app-type memory limits, fonts, layouts
- <https://developer.garmin.com/connect-iq/compatible-devices/> — CIQ version
  and supported app types per device
- <https://developer.garmin.com/connect-iq/core-topics/https/> — JSON REST
  requests via the mobile proxy
- <https://developer.garmin.com/connect-iq/core-topics/glances/> — glance memory
  pools, lifecycle classes, `:glance` annotation
- <https://developer.garmin.com/connect-iq/core-topics/backgrounding/> —
  temporal-event cap, 30 s exit rule, `:background` annotation
- <https://developer.garmin.com/connect-iq/monkey-c/monkey-types/> — type-check
  levels, `:typecheck(disableGlanceCheck)`
- <https://developer.garmin.com/connect-iq/api-docs/Toybox/Communications.html>
  — `makeWebRequest` options and error constants
- Connect IQ SDK 9.3.0: bundled API documentation and the `WebRequest`,
  `ExtendedCodeSpace` and `BackgroundTimer` samples
