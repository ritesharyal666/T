<?php
/**
 * config.php
 * ----------
 * Central configuration for the TheosAuthDemo backend.
 *
 * SECURITY: Every value marked "CHANGE ME" must be replaced before this is
 * used anywhere other than a local demo. The crypto master key and the JWT
 * secret in particular MUST be long, random and kept out of source control.
 */

declare(strict_types=1);

// ---------------------------------------------------------------------------
// Database (PDO / MySQL)
// ---------------------------------------------------------------------------
define('DB_HOST', '127.0.0.1');
define('DB_NAME', 'theos_auth_demo');
define('DB_USER', 'theos_user');     // CHANGE ME
define('DB_PASS', 'change_me');      // CHANGE ME
define('DB_CHARSET', 'utf8mb4');

// ---------------------------------------------------------------------------
// JWT (HS256, signed manually – see jwt.php)
// ---------------------------------------------------------------------------
// Generated with `openssl rand -hex 32`. Rotate for production.
define('JWT_SECRET', '961637a56329325f96596166f8bdf366eb9f56a8d5180729c482cf0d30f4c562');
define('JWT_ISSUER', 'TheosAuthDemo');
define('JWT_TTL', 86400); // token lifetime in seconds (24 hours)

// ---------------------------------------------------------------------------
// Payload encryption (AES-256-CBC + HMAC-SHA256, see crypto.php)
// ---------------------------------------------------------------------------
// This MUST match kTADMasterKeyHex in the iOS app (CryptoManager.m).
// 64 hex chars = 32 raw bytes. Generated with `openssl rand -hex 32`.
define('CRYPTO_MASTER_KEY_HEX', '9af29479de0b00650c20b6009a889a5bf90774ad6b15f6f0cd0132aa5287b108');

// ---------------------------------------------------------------------------
// Simple per-IP rate limiting
// ---------------------------------------------------------------------------
define('RATE_LIMIT_WINDOW', 60); // seconds
define('RATE_LIMIT_MAX', 10);    // max requests per window per endpoint per IP
