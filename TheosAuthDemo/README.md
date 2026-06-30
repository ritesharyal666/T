# TheosAuthDemo

A complete, end-to-end **authentication demo**:

- **iOS frontend** — a Theos *application* (Objective-C / UIKit, ARC, iOS 14+)
  with Login / Register / Home screens, `NSURLSession` networking, Keychain
  token storage, and CommonCrypto payload encryption.
- **Backend** — PHP 8 + MySQL (PDO, prepared statements) REST API with manual
  HS256 JWT, `password_hash()`/`password_verify()`, rate limiting, an
  AES-encrypted request/response envelope, and **one login per device**
  (a single active session per account).

Every request is: **JSON → AES-256-CBC+HMAC encrypt → HTTPS → decrypt → JSON**,
authenticated with a 24-hour JWT.

```
┌────────────┐   encrypted JSON over HTTPS    ┌─────────────────────┐
│  iOS app   │  ───────────────────────────▶  │  Backend            │
│ (Theos)    │   POST /register /login        │  PHP 8 + MySQL      │
│ Login/Reg/ │   GET  /verify                 │  (or devserver.py   │
│ Home       │  ◀───────────────────────────  │   for local demo)   │
└────────────┘   encrypted JSON + JWT          └─────────────────────┘
```

---

## Repository layout

```
TheosAuthDemo/
├── Theos/                         # the iOS app (build with Theos)
│   ├── Makefile  control          # Theos application target + packaging
│   ├── main.m  AppDelegate.{h,m}  # entry point + window/root routing
│   ├── Theme.{h,m}                # reusable UIKit factory helpers
│   ├── CryptoManager.{h,m}        # AES-256-CBC + HMAC-SHA256 (CommonCrypto)
│   ├── NetworkManager.{h,m}       # NSURLSession + encrypt/decrypt pipeline
│   ├── AuthManager.{h,m}          # auth facade + Keychain token storage
│   ├── LoginViewController.{h,m}
│   ├── RegisterViewController.{h,m}
│   ├── HomeViewController.{h,m}
│   └── Resources/Info.plist       # ATS = HTTPS only
├── Backend/
│   ├── config.php                 # secrets + settings (EDIT THESE)
│   ├── db.php  crypto.php  jwt.php  middleware.php
│   ├── register.php  login.php  verify.php  logout.php
│   ├── users.sql                  # MySQL schema
│   ├── .htaccess                  # force HTTPS, block internal includes
│   └── tools/
│       ├── devserver.py           # no-install local backend (mirrors the PHP)
│       ├── serve_public.sh        # devserver + public HTTPS via Cloudflare
│       └── client_test.py         # end-to-end protocol verifier
├── .github/workflows/build-ipa.yml # builds the .ipa on a free macOS runner
├── RUN_ON_IPHONE.md               # detailed sideloading guide
└── README.md                      # you are here
```

---

# How to run this project

There are two halves — **a backend that must be reachable over HTTPS**, and
**the iOS app that talks to it**. Do the backend first.

## 1. Run the backend

Pick **A** (real PHP/MySQL — for deployment) or **B** (zero-install local demo).

### Option A — real PHP 8 + MySQL (the actual backend)

The four endpoints are plain `.php` files, so PHP's **built-in server** runs them
directly — no Apache/nginx needed for local testing.

**1. Install PHP 8 + MySQL** (need the `pdo_mysql` and `openssl` extensions):

```bash
# Debian / Ubuntu / Pop!_OS
sudo apt install php-cli php-mysql mariadb-server
# Fedora
sudo dnf install php-cli php-mysqlnd mariadb-server
# macOS (Homebrew)
brew install php mysql
```

```powershell
# Windows — easiest is XAMPP (bundles PHP + MySQL with a GUI):
#   https://www.apachefriends.org   (then use its "Shell" button for php/mysql)
# or with Chocolatey, in an Administrator PowerShell:
choco install php mariadb
```

On **Windows**, the `pdo_mysql` / `openssl` extensions ship with PHP but may be
disabled — open your `php.ini` (run `php --ini` to find it) and ensure these
lines have **no leading `;`**, then reopen the terminal:

```ini
extension=pdo_mysql
extension=openssl
```

Check it — both must appear:
- Linux/macOS: `php -v` (want 8.x) and `php -m | grep -E 'pdo_mysql|openssl'`
- Windows:     `php -v` and `php -m | findstr /R "pdo_mysql openssl"`

**2. Create the database + tables:**

```bash
# Linux/macOS
sudo mysql < Backend/users.sql      # or:  mysql -u root -p < Backend/users.sql
```

```powershell
# Windows PowerShell (it has no `<` redirection, so pipe the file in):
Get-Content Backend\users.sql | mysql -u root -p
# Windows cmd.exe (or XAMPP Shell) instead:
#   mysql -u root -p < Backend\users.sql
```

Create a DB user (or use root for local only) and grant it access:

```sql
-- run inside the MySQL prompt (`sudo mysql` on Linux, `mysql -u root -p` on Windows/macOS)
CREATE USER 'theos_user'@'localhost' IDENTIFIED BY 'change_me';
GRANT ALL PRIVILEGES ON theos_auth_demo.* TO 'theos_user'@'localhost';
FLUSH PRIVILEGES;
```

**3. Configure `Backend/config.php`** — set `DB_USER` / `DB_PASS` to match step 2,
and generate fresh secrets:

```bash
openssl rand -hex 32   # -> paste as JWT_SECRET
openssl rand -hex 32   # -> paste as CRYPTO_MASTER_KEY_HEX   (also used in step 2 of "Configure the app")
```

(On Windows, run these in **Git Bash**, or use the `openssl` from Git for Windows
at `C:\Program Files\Git\usr\bin`.)

**4. Start the PHP server** from the repo root:

```bash
php -S 127.0.0.1:8000 -t Backend
```

Endpoints are now live at `http://127.0.0.1:8000/register.php`, `/login.php`,
`/verify.php`, `/logout.php`. Leave this running.

**5. Verify** (from another terminal — on **Windows** use `python` instead of `python3`):

```bash
python3 Backend/tools/client_test.py http://127.0.0.1:8000
```

Expected: **`RESULT: 16 passed, 0 failed`**.

> **HTTPS note:** `php -S` serves plain **HTTP** and ignores `.htaccess`. That's
> fine for `client_test.py`, but the **iOS app refuses non-HTTPS**. To use the app
> against this PHP server, put a real-TLS tunnel in front of it and use that URL:
> ```bash
> # Linux/macOS
> ~/.local/bin/cloudflared tunnel --url http://127.0.0.1:8000     # prints an https URL
> # Windows
> .\cloudflared.exe tunnel --url http://127.0.0.1:8000
> ```
> For production, run `Backend/` behind **Apache/nginx with a valid TLS cert**
> (Let's Encrypt). Under Apache the included `.htaccess` forces HTTPS and blocks
> the internal includes (`config.php`, `db.php`, …); replicate those rules for nginx.

Your API base URL is `http://127.0.0.1:8000/` (local tests) or the `https://…`
tunnel/deployed URL (for the app).

### Option B — local demo backend, no PHP/MySQL needed

`Backend/tools/devserver.py` is a faithful, dependency-free stand-in for the PHP
backend: **identical** crypto envelope, JWT, validation, rate limiting and
revocation, backed by a local SQLite file. It needs only Python 3 and the
`openssl` binary. Use this to try the whole thing without setting up a server.

Requires **Python 3** and the **`openssl`** binary on your `PATH`. On Windows,
`openssl` comes with [Git for Windows](https://git-scm.com/download/win) (it's at
`C:\Program Files\Git\usr\bin`) or via `choco install openssl`.

```bash
# Linux/macOS  (listens on 127.0.0.1:8787)
python3 Backend/tools/devserver.py
```
```powershell
# Windows
python Backend\tools\devserver.py
```

To reach it from a phone, expose it on a **public HTTPS URL** (no account, no
signup) with a Cloudflare quick tunnel:

```bash
# Linux/macOS — one command starts the server AND the tunnel:
Backend/tools/serve_public.sh
```
```powershell
# Windows (serve_public.sh is bash-only) — run two terminals instead:
#   terminal 1:  python Backend\tools\devserver.py
#   terminal 2:  .\cloudflared.exe tunnel --url http://127.0.0.1:8787
```

It prints a URL like `https://<random>.trycloudflare.com` — that's your API base
URL. It stays up only while these commands run, and the URL **changes every
restart** (for a stable URL, use a free Cloudflare named tunnel).

> First time only — install `cloudflared`:
> ```bash
> # Linux x86_64 (no root):
> mkdir -p ~/.local/bin && curl -sL -o ~/.local/bin/cloudflared \
>   https://github.com/cloudflare/cloudflared/releases/latest/download/cloudflared-linux-amd64
> chmod +x ~/.local/bin/cloudflared
> ```
> ```powershell
> # Windows: winget install Cloudflare.cloudflared   (or choco install cloudflared,
> # or download cloudflared-windows-amd64.exe from the cloudflared releases page)
> ```

### Verify the backend works

With the backend running, from another terminal (on **Windows** use `python`):

```bash
python3 Backend/tools/client_test.py http://127.0.0.1:8787      # local
python3 Backend/tools/client_test.py https://<your-public-url>  # public/deployed
```

Expected: **`RESULT: 16 passed, 0 failed`** (register, duplicate/validation
rejects, wrong-password reject, login, verify, logout, post-logout revocation,
and one-login-per-device: a second device takes over and kicks the first).

## 2. Configure the app

Edit two values so the app matches your backend:

1. **`Theos/NetworkManager.m` → `kTADBaseURL`** — set to your API base URL from
   step 1 (must be `https://`, keep the trailing slash):
   ```objc
   static NSString *const kTADBaseURL = @"https://api.yourdomain.com/";
   ```
2. **`Theos/CryptoManager.m` → `kTADMasterKeyHex`** — must **equal**
   `CRYPTO_MASTER_KEY_HEX` in `Backend/config.php`, or every request fails the
   integrity check. (They already match out of the box; only re-sync if you
   rotate the key.)

## 3. Build the iOS app

You need macOS to compile iOS. Two ways:

### Option A — on a Mac with Theos

```bash
cd Theos
make package          # builds a .deb in ./packages  (jailbroken installs)
# or, to a jailbroken device on your network:
export THEOS_DEVICE_IP=<device-ip>
make do
```

### Option B — no Mac: build in the cloud (GitHub Actions)

This repo includes `.github/workflows/build-ipa.yml`, which builds an unsigned
`.ipa` on a **free GitHub-hosted macOS runner**.

```bash
git add -A && git commit -m "configure backend URL"
git push                      # to your GitHub repo
```

Then: GitHub → your repo → **Actions** → latest **Build IPA** run → **Artifacts**
→ download `TheosAuthDemo-ipa` → unzip to get `TheosAuthDemo.ipa`.
You can also trigger it manually from the Actions tab ("Run workflow").

## 4. Install on the iPhone

The method depends on the device. See **[RUN_ON_IPHONE.md](RUN_ON_IPHONE.md)**
for full details; in short:

| Device / iOS | How |
|---|---|
| **Jailbroken** | Install the `.deb` via Sileo/Filza or `dpkg -i` over SSH. |
| **Not jailbroken, iOS 14.0–16.6.1 / 17.0** | **TrollStore** — permanent, no Apple ID, no expiry. Best. |
| **Not jailbroken, iOS 16.7+ / 17.1+ / 18.x / 26** | **AltStore / Sideloadly** (Windows/Mac) or **AltServer-Linux** — free Apple ID, **re-sign every 7 days**. |
| **Any (paid)** | Apple Developer cert + `ideviceinstaller -i TheosAuthDemo.ipa` (~1 year). |

> iPhone 16 Pro Max ships on iOS 18+, so TrollStore is **not** available — use
> the AltStore / Sideloadly path (a Windows/Mac for ~10 min is by far the
> easiest; AltServer-Linux works but is fiddly).

## 5. Use it

Open the app → **Register** (username 3–32 chars, password ≥8 with a letter and a
number) → it logs you in and shows **Welcome, <username>** → **Logout** clears the
Keychain token and revokes it server-side.

> The backend must be reachable (step 1 running) when you use the app. If
> `kTADBaseURL` points at a Cloudflare quick tunnel, keep `serve_public.sh`
> running and don't restart it between building and testing (the URL changes).

---

## Security notes

- Passwords are stored only as `password_hash()` (bcrypt) hashes — never
  plaintext. The devserver uses scrypt as a stdlib stand-in.
- All DB access uses **prepared statements** (no string-built SQL).
- JWTs are HS256, expire after 24h, carry a `jti`, and can be **revoked**
  server-side (logout writes the `jti` to `revoked_tokens`).
- **One login per device.** Each account has a single active session: login
  records the new token's `jti` + device id on the user row (`current_jti`),
  so signing in on a second device instantly invalidates the first device's
  token — `require_auth()` rejects any token whose `jti` is no longer the
  account's current one. The app sends a stable per-device UUID (kept in the
  Keychain) as `device_id`, and the kicked device drops to the login screen on
  its next request (e.g. the launch-time `verify`).
- Payloads use **AES-256-CBC + HMAC-SHA256 (Encrypt-then-MAC)** with random IVs
  and constant-time MAC comparison; the real transport security is TLS/HTTPS
  (ATS on the app, `.htaccess` on the server). SSL validation is **not** disabled.
- Per-IP **rate limiting** on register/login.
- **Rotate the demo secrets** (`JWT_SECRET`, `CRYPTO_MASTER_KEY_HEX`) before any
  real use, especially if this repo is public. Note the master key necessarily
  ships inside the app binary — the pre-shared-key model here is for the demo;
  production would rely on TLS + per-user auth, not a shipped symmetric key.

## Honest limitations

- The iOS app **cannot be built or run on Linux/Windows** — iOS needs macOS
  (Theos/Xcode) to compile, and an iPhone/Simulator to run. Use the GitHub
  Actions build (step 3B) if you have no Mac.
- `devserver.py` is a protocol-faithful **stand-in** for the PHP backend (so you
  can run everything without PHP/MySQL); the `Backend/*.php` files are the real
  thing for deployment. Both implement the identical wire format and were
  verified with `client_test.py`.
- A Cloudflare *quick* tunnel URL is **ephemeral** (changes per restart, up only
  while your machine + the command run). For a stable URL use a free Cloudflare
  named tunnel or deploy the PHP backend (Option A).
