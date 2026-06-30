# Running TheosAuthDemo on a non-jailbroken iPhone (from a Linux PC)

You can't build iOS on Linux and you don't need a Mac — GitHub builds it for you
in the cloud, you download an `.ipa`, and you sideload it onto the iPhone.

```
Linux PC ──push──▶ GitHub Actions (macOS runner) ──.ipa──▶ download ──▶ iPhone
```

---

## Step 0 — point the app at a reachable backend (important)

The app talks to the backend over **HTTPS only** (App Transport Security). The UI
will launch without a backend, but login/register will fail until one is reachable.

Before building, edit [Theos/NetworkManager.m](Theos/NetworkManager.m):

```objc
static NSString *const kTADBaseURL = @"https://your-server.example.com/";
```

and deploy `Backend/` to a host with a **valid TLS certificate** (a self-signed
cert won't pass ATS). If you just want to see the UI run first, you can skip this
and wire the backend later — but then re-run the build afterward.

---

## Step 1 — push the project to GitHub

From this folder:

```bash
cd "TheosAuthDemo"
git init -b main
git add .
git commit -m "TheosAuthDemo: app + backend"
# create an empty repo at https://github.com/new (private is fine), then:
git remote add origin https://github.com/<you>/TheosAuthDemo.git
git push -u origin main
```

The push triggers `.github/workflows/build-ipa.yml`. (For **private** repos,
macOS runner minutes draw on your free monthly allotment — a build is only a few
minutes. Public repos are free.)

## Step 2 — download the `.ipa`

GitHub → your repo → **Actions** tab → the latest **Build IPA** run → scroll to
**Artifacts** → download **TheosAuthDemo-ipa** → unzip to get `TheosAuthDemo.ipa`.

Get that file onto the iPhone however is convenient (e.g. upload it somewhere and
download in Safari/Files, or transfer over USB with `libimobiledevice`).

## Step 3 — install it. Pick the path for your iOS version.

Check the version on the phone: **Settings → General → About → iOS Version**.

### Path A — TrollStore  ✅ best, permanent, no computer needed (iOS 14.0–16.6.1, and 17.0)
TrollStore permanently signs apps with no 7-day expiry and no Apple ID.
1. Install TrollStore using the method for your exact iOS version — follow the
   official guide: <https://ios.cfw.guide/installing-trollstore/> (or
   <https://trollstore.app>).
2. Open `TheosAuthDemo.ipa` in TrollStore → **Install**. Done — it stays installed.

### Path B — AltStore / AltServer-Linux  (iOS 16.7+, 17.1+, 18.x — no TrollStore)
Free Apple ID signing. The app must be **re-signed every 7 days**, and a computer
must run the signing server.
- On Linux: **AltServer-Linux** — <https://github.com/NisanLab/AltServer-Linux>
  (needs `usbmuxd` + `libimobiledevice` + an anisette server; fiddly but works).
- Easiest if you can borrow a Windows/Mac for 10 min: install **AltStore** or use
  **Sideloadly** (<https://sideloadly.io>), plug in the phone, sign in with a free
  Apple ID, and install the `.ipa`.
- Trust the developer profile: **Settings → General → VPN & Device Management →
  trust your Apple ID**.

### Path C — Paid Apple Developer account ($99/yr)  (any iOS, ~1-year signing)
Sign the `.ipa` with a real certificate + provisioning profile, then install from
Linux with `ideviceinstaller -i TheosAuthDemo.ipa`. No 7-day expiry.

---

## Notes
- The build is **arm64-only** for sideload compatibility (set in the workflow).
- The app's bundle id is `com.tweak.theosauthdemo`; AltStore rewrites it
  automatically during free-Apple-ID signing.
- If the build fails, the Actions log shows exactly where — paste it back to me.
