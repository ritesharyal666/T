#!/usr/bin/env python3
"""
devserver.py — a runnable backend for TheosAuthDemo.

This is a faithful, dependency-free stand-in for the PHP backend (PHP can't be
installed in this environment). It implements the IDENTICAL wire protocol the
iOS app expects:
  * AES-256-CBC + HMAC-SHA256 (Encrypt-then-MAC) request/response envelopes
  * HS256 JWTs with sub/iat/exp/jti, 24h expiry, server-side revocation
  * register / login / verify / logout, same validation + rate limiting
It reads the REAL secrets from ../config.php and stores data in a local SQLite
file, so accounts persist across restarts.

Run:   python3 devserver.py            # listens on 127.0.0.1:8787
       PORT=9000 python3 devserver.py  # custom port
Only stdlib + the `openssl` binary are used (no third-party packages).
"""

import base64, hashlib, hmac, json, os, re, sqlite3, subprocess, threading, time
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer

HERE    = os.path.dirname(os.path.abspath(__file__))
CONFIG  = os.path.join(HERE, "..", "config.php")
DB_PATH = os.path.join(HERE, "devdata.sqlite")
PORT    = int(os.environ.get("PORT", "8787"))

# --- read the project's real configuration --------------------------------
def load_php_config(path):
    cfg, text = {}, open(path, encoding="utf-8").read()
    for name, raw in re.findall(r"define\('([A-Z_]+)',\s*(.+?)\);", text):
        raw = raw.strip()
        if raw.startswith("'") and raw.endswith("'"):
            cfg[name] = raw[1:-1]
        else:
            try: cfg[name] = int(raw)
            except ValueError: cfg[name] = raw
    return cfg

CFG               = load_php_config(CONFIG)
MASTER            = bytes.fromhex(CFG["CRYPTO_MASTER_KEY_HEX"])
JWT_SECRET        = CFG["JWT_SECRET"].encode()
JWT_ISSUER        = CFG["JWT_ISSUER"]
JWT_TTL           = int(CFG["JWT_TTL"])
RATE_LIMIT_WINDOW = int(CFG["RATE_LIMIT_WINDOW"])
RATE_LIMIT_MAX    = int(CFG["RATE_LIMIT_MAX"])
ENC_KEY           = hashlib.sha256(MASTER + b"enc").digest()
MAC_KEY           = hashlib.sha256(MASTER + b"mac").digest()

# --- crypto (same scheme as CryptoManager.m / crypto.php) -----------------
def aes_cbc(data, iv, decrypt):
    args = ["openssl", "enc", "-aes-256-cbc", "-K", ENC_KEY.hex(), "-iv", iv.hex()]
    if decrypt: args.insert(2, "-d")
    p = subprocess.run(args, input=data, capture_output=True)
    return p.stdout if p.returncode == 0 else None

def encrypt_envelope(plaintext):
    iv = os.urandom(16)
    ct = aes_cbc(plaintext, iv, False)
    mac = hmac.new(MAC_KEY, iv + ct, hashlib.sha256).digest()
    return {"v": 1, "iv": base64.b64encode(iv).decode(),
            "ct": base64.b64encode(ct).decode(),
            "mac": base64.b64encode(mac).decode()}

def decrypt_envelope(env):
    try:
        iv, ct, mac = (base64.b64decode(env[k]) for k in ("iv", "ct", "mac"))
    except Exception:
        return None
    if len(iv) != 16 or len(mac) != 32:
        return None
    if not hmac.compare_digest(hmac.new(MAC_KEY, iv + ct, hashlib.sha256).digest(), mac):
        return None
    return aes_cbc(ct, iv, True)

# --- JWT (same as jwt.php) ------------------------------------------------
def b64url(b): return base64.urlsafe_b64encode(b).rstrip(b"=").decode()
def b64url_dec(s): return base64.urlsafe_b64decode(s + "=" * (-len(s) % 4))

def jwt_encode(claims):
    h = b64url(json.dumps({"typ": "JWT", "alg": "HS256"}, separators=(",", ":")).encode())
    p = b64url(json.dumps(claims, separators=(",", ":")).encode())
    sig = hmac.new(JWT_SECRET, f"{h}.{p}".encode(), hashlib.sha256).digest()
    return f"{h}.{p}.{b64url(sig)}"

def jwt_decode(token):
    parts = token.split(".")
    if len(parts) != 3: return None
    h, p, s = parts
    if not hmac.compare_digest(b64url(hmac.new(JWT_SECRET, f"{h}.{p}".encode(), hashlib.sha256).digest()), s):
        return None
    claims = json.loads(b64url_dec(p))
    if "exp" not in claims or time.time() >= int(claims["exp"]):
        return None
    return claims

# --- password hashing (scrypt stands in for PHP bcrypt) -------------------
def password_hash(pw):
    salt = os.urandom(16)
    h = hashlib.scrypt(pw.encode(), salt=salt, n=16384, r=8, p=1, dklen=32)
    return "scrypt$" + base64.b64encode(salt).decode() + "$" + base64.b64encode(h).decode()

def password_verify(pw, stored):
    try:
        _, salt_b64, hash_b64 = stored.split("$")
        h = hashlib.scrypt(pw.encode(), salt=base64.b64decode(salt_b64), n=16384, r=8, p=1, dklen=32)
        return hmac.compare_digest(h, base64.b64decode(hash_b64))
    except Exception:
        return False

DUMMY_HASH = password_hash("not-a-real-password")

# --- database (persistent SQLite mirror of users.sql) ---------------------
DB_LOCK = threading.Lock()
DB = sqlite3.connect(DB_PATH, check_same_thread=False)
DB.row_factory = sqlite3.Row
DB.executescript("""
    CREATE TABLE IF NOT EXISTS users (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        username TEXT UNIQUE NOT NULL,
        password_hash TEXT NOT NULL,
        current_jti TEXT,        -- one login per device: the only active session
        current_device TEXT,     -- ...and the device it is bound to
        created_at TEXT NOT NULL DEFAULT (datetime('now')));
    CREATE TABLE IF NOT EXISTS revoked_tokens (jti TEXT PRIMARY KEY, expires_at INTEGER NOT NULL);
    CREATE TABLE IF NOT EXISTS rate_limits (id INTEGER PRIMARY KEY AUTOINCREMENT,
        ip_address TEXT, endpoint TEXT, request_time REAL);
""")
# Migrate an older devdata.sqlite that predates the single-session columns.
_cols = {r["name"] for r in DB.execute("PRAGMA table_info(users)")}
if "current_jti" not in _cols:
    DB.execute("ALTER TABLE users ADD COLUMN current_jti TEXT")
if "current_device" not in _cols:
    DB.execute("ALTER TABLE users ADD COLUMN current_device TEXT")
DB.commit()

# --- endpoint logic (faithful to the .php files) --------------------------
USERNAME_RE = re.compile(r"^[A-Za-z0-9_]{3,32}$")

def rate_limit(ip, endpoint):
    now = time.time()
    DB.execute("DELETE FROM rate_limits WHERE ip_address=? AND endpoint=? AND request_time < ?",
               (ip, endpoint, now - RATE_LIMIT_WINDOW))
    n = DB.execute("SELECT COUNT(*) c FROM rate_limits WHERE ip_address=? AND endpoint=?",
                   (ip, endpoint)).fetchone()["c"]
    if n >= RATE_LIMIT_MAX:
        return False
    DB.execute("INSERT INTO rate_limits(ip_address,endpoint,request_time) VALUES(?,?,?)",
               (ip, endpoint, now))
    return True

def require_auth(headers):
    m = re.match(r"^Bearer\s+(.+)$", headers.get("Authorization", ""), re.I)
    if not m:
        return None, (401, {"success": False, "error": "Missing or invalid Authorization header."})
    claims = jwt_decode(m.group(1).strip())
    if claims is None:
        return None, (401, {"success": False, "error": "Invalid or expired token."})
    if DB.execute("SELECT 1 FROM revoked_tokens WHERE jti=?", (claims.get("jti"),)).fetchone():
        return None, (401, {"success": False, "error": "Token has been revoked."})
    # One login per device: reject any token superseded by a newer login.
    row = DB.execute("SELECT current_jti FROM users WHERE id=?", (claims.get("sub"),)).fetchone()
    if not row or row["current_jti"] != claims.get("jti"):
        return None, (401, {"success": False,
                            "error": "Session ended: your account was signed in on another device."})
    return claims, None

def ep_register(body, ip, headers):
    if not rate_limit(ip, "register"):
        return 429, {"success": False, "error": "Too many requests. Please try again later."}
    username = (body.get("username") or "").strip()
    password = body.get("password") or ""
    if not USERNAME_RE.match(username):
        return 400, {"success": False, "error": "Username must be 3-32 characters (letters, numbers, underscore)."}
    if len(password) < 8 or not re.search(r"[A-Za-z]", password) or not re.search(r"[0-9]", password):
        return 400, {"success": False, "error": "Password must be at least 8 characters and contain a letter and a number."}
    if DB.execute("SELECT id FROM users WHERE username=?", (username,)).fetchone():
        return 409, {"success": False, "error": "Username is already taken."}
    DB.execute("INSERT INTO users(username,password_hash) VALUES(?,?)", (username, password_hash(password)))
    DB.commit()
    return 201, {"success": True, "message": "Account created successfully."}

def ep_login(body, ip, headers):
    if not rate_limit(ip, "login"):
        return 429, {"success": False, "error": "Too many requests. Please try again later."}
    username = (body.get("username") or "").strip()
    password = body.get("password") or ""
    if not username or not password:
        return 400, {"success": False, "error": "Username and password are required."}
    row = DB.execute("SELECT id,username,password_hash FROM users WHERE username=?", (username,)).fetchone()
    if not row or not password_verify(password, row["password_hash"] if row else DUMMY_HASH):
        return 401, {"success": False, "error": "Invalid username or password."}
    now = int(time.time())
    claims = {"iss": JWT_ISSUER, "sub": row["id"], "username": row["username"],
              "iat": now, "exp": now + JWT_TTL, "jti": os.urandom(16).hex()}
    # One login per device: this login becomes the account's only active session;
    # the previously bound device's token stops matching current_jti (logged out).
    device = ((body.get("device_id") or "").strip()[:64]) or None
    DB.execute("UPDATE users SET current_jti=?, current_device=? WHERE id=?",
               (claims["jti"], device, row["id"]))
    DB.commit()
    return 200, {"success": True, "token": jwt_encode(claims), "username": row["username"]}

def ep_verify(body, ip, headers):
    claims, err = require_auth(headers)
    if err: return err
    row = DB.execute("SELECT id,username,created_at FROM users WHERE id=?", (claims["sub"],)).fetchone()
    if not row:
        return 404, {"success": False, "error": "User not found."}
    return 200, {"success": True, "user": dict(row)}

def ep_logout(body, ip, headers):
    claims, err = require_auth(headers)
    if err: return err
    DB.execute("DELETE FROM revoked_tokens WHERE expires_at < ?", (int(time.time()),))
    DB.execute("INSERT OR IGNORE INTO revoked_tokens(jti,expires_at) VALUES(?,?)",
               (claims["jti"], int(claims["exp"])))
    # Free the one-login-per-device slot, but only if this token still owns it.
    DB.execute("UPDATE users SET current_jti=NULL, current_device=NULL WHERE id=? AND current_jti=?",
               (claims["sub"], claims["jti"]))
    DB.commit()
    return 200, {"success": True, "message": "Logged out successfully."}

ROUTES = {
    ("POST", "/register.php"): ep_register,
    ("POST", "/login.php"):    ep_login,
    ("GET",  "/verify.php"):   ep_verify,
    ("POST", "/logout.php"):   ep_logout,
}

class Handler(BaseHTTPRequestHandler):
    def log_message(self, fmt, *a):
        print(f"  {self.command} {self.path} -> {a[1] if len(a) > 1 else ''}")

    def _client_ip(self):
        # Behind the tunnel, the real client IP is forwarded here.
        return self.headers.get("CF-Connecting-IP") or self.client_address[0]

    def _dispatch(self, method):
        route = ROUTES.get((method, self.path.split("?")[0]))
        if not route:
            return self._send(404, {"success": False, "error": "Not found."})
        body = {}
        if method == "POST":
            length = int(self.headers.get("Content-Length", 0))
            raw = self.rfile.read(length) if length else b""
            if raw:
                try:
                    env = json.loads(raw)
                except Exception:
                    return self._send(400, {"success": False, "error": "Malformed encrypted request."})
                plain = decrypt_envelope(env)
                if plain is None:
                    return self._send(400, {"success": False, "error": "Unable to decrypt request (integrity check failed)."})
                body = json.loads(plain)
        with DB_LOCK:
            status, payload = route(body, self._client_ip(), self.headers)
        self._send(status, payload)

    def do_POST(self): self._dispatch("POST")
    def do_GET(self):  self._dispatch("GET")

    def _send(self, status, payload):
        data = json.dumps(encrypt_envelope(json.dumps(payload).encode())).encode()
        self.send_response(status)
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(data)))
        self.end_headers()
        self.wfile.write(data)

def main():
    server = ThreadingHTTPServer(("127.0.0.1", PORT), Handler)
    print(f"TheosAuthDemo backend listening on http://127.0.0.1:{PORT}")
    print(f"  config : {os.path.normpath(CONFIG)}")
    print(f"  db     : {DB_PATH}")
    print(f"  routes : /register.php /login.php /verify.php /logout.php")
    print("  (expose publicly with cloudflared — see serve_public.sh)")
    try:
        server.serve_forever()
    except KeyboardInterrupt:
        print("\nshutting down.")
        server.shutdown()

if __name__ == "__main__":
    main()
