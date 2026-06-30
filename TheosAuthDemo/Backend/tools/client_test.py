#!/usr/bin/env python3
"""
client_test.py — verify a running TheosAuthDemo backend end-to-end.

It speaks the exact wire protocol the iOS app uses (AES-256-CBC + HMAC-SHA256
envelope, HS256 JWT), reading the shared key from ../config.php, and runs the
full register / login / verify / logout flow plus the validation + revocation
edge cases.

Usage:
    python3 client_test.py                      # tests http://127.0.0.1:8787
    python3 client_test.py https://your-url/    # tests a public/deployed URL

Exits non-zero if any check fails. Stdlib + the `openssl` binary only.
"""
import base64, hashlib, hmac, json, os, re, subprocess, sys, urllib.request, urllib.error

BASE   = (sys.argv[1] if len(sys.argv) > 1 else "http://127.0.0.1:8787").rstrip("/")
CONFIG = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "config.php")

cfg = {}
for n, raw in re.findall(r"define\('([A-Z_]+)',\s*(.+?)\);", open(CONFIG).read()):
    raw = raw.strip(); cfg[n] = raw[1:-1] if raw.startswith("'") else raw
MASTER = bytes.fromhex(cfg["CRYPTO_MASTER_KEY_HEX"])
ENC = hashlib.sha256(MASTER + b"enc").digest()
MAC = hashlib.sha256(MASTER + b"mac").digest()

def aes(data, iv, dec):
    a = ["openssl", "enc", "-aes-256-cbc", "-K", ENC.hex(), "-iv", iv.hex()]
    if dec: a.insert(2, "-d")
    return subprocess.run(a, input=data, capture_output=True).stdout

def enc(pt):
    iv = os.urandom(16); ct = aes(pt, iv, False)
    m = hmac.new(MAC, iv + ct, hashlib.sha256).digest()
    return {"v": 1, "iv": base64.b64encode(iv).decode(),
            "ct": base64.b64encode(ct).decode(), "mac": base64.b64encode(m).decode()}

def dec(env):
    iv, ct, m = (base64.b64decode(env[k]) for k in ("iv", "ct", "mac"))
    if not hmac.compare_digest(hmac.new(MAC, iv + ct, hashlib.sha256).digest(), m): return None
    return aes(ct, iv, True)

def call(method, ep, payload=None, token=None):
    h = {"Content-Type": "application/json"}
    if token: h["Authorization"] = f"Bearer {token}"
    data = json.dumps(enc(json.dumps(payload or {}).encode())).encode() if method == "POST" else None
    req = urllib.request.Request(f"{BASE}/{ep}", data=data, headers=h, method=method)
    try:
        r = urllib.request.urlopen(req, timeout=30); status, raw = r.status, r.read()
    except urllib.error.HTTPError as e:
        status, raw = e.code, e.read()
    return status, json.loads(dec(json.loads(raw)))

ok = 0; fail = 0
def check(label, got, want_status, want_success):
    global ok, fail
    s, b = got
    good = (s == want_status and b.get("success") == want_success)
    ok += good; fail += (not good)
    print(f"  [{'PASS' if good else 'FAIL'}] {label}: HTTP {s} {json.dumps(b)[:90]}")

user = "user_" + os.urandom(3).hex()
print(f"Target: {BASE}\nUser:   {user}\n")
check("register new user",        call("POST","register.php",{"username":user,"password":"Password123"}), 201, True)
check("duplicate rejected",       call("POST","register.php",{"username":user,"password":"Password123"}), 409, False)
check("short username rejected",  call("POST","register.php",{"username":"ab","password":"Password123"}), 400, False)
check("weak password rejected",   call("POST","register.php",{"username":"zzz","password":"weak"}),        400, False)
check("wrong password rejected",  call("POST","login.php",{"username":user,"password":"nope"}),            401, False)
s, b = call("POST","login.php",{"username":user,"password":"Password123"})
check("login ok",                 (s, b), 200, True)
token = b.get("token", "")
check("verify with token",        call("GET","verify.php",token=token), 200, True)
check("verify without token",     call("GET","verify.php"),             401, False)
check("logout",                   call("POST","logout.php",token=token),200, True)
check("token revoked post-logout",call("GET","verify.php",token=token), 401, False)

# --- one login per device: a new device takes over, the old one is kicked --
print("\n  -- one login per device --")
user2 = "dev_" + os.urandom(3).hex()
check("register 2nd user",        call("POST","register.php",{"username":user2,"password":"Password123"}), 201, True)
_, bA = call("POST","login.php",{"username":user2,"password":"Password123","device_id":"device-A"})
check("login on device A",        (_, bA), 200, True)
tokenA = bA.get("token","")
check("device A can verify",      call("GET","verify.php",token=tokenA), 200, True)
_, bB = call("POST","login.php",{"username":user2,"password":"Password123","device_id":"device-B"})
check("login on device B",        (_, bB), 200, True)
tokenB = bB.get("token","")
check("device B is active",       call("GET","verify.php",token=tokenB), 200, True)
check("device A kicked off",      call("GET","verify.php",token=tokenA), 401, False)

print(f"\nRESULT: {ok} passed, {fail} failed")
sys.exit(1 if fail else 0)
