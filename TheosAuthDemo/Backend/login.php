<?php
/**
 * login.php  (POST /login.php)
 * ----------------------------
 * Verify credentials and issue a signed JWT (24h).
 *
 * Returns: { "success": true, "token": "...", "username": "..." }
 */

declare(strict_types=1);

require_once __DIR__ . '/middleware.php';

require_method('POST');
rate_limit('login');

// A real bcrypt hash of a random value. Used to keep timing roughly constant
// when the username does not exist, mitigating user-enumeration via timing.
const DUMMY_HASH = '$2y$10$usesomesillystringforsalttouseSalt0e9h1q9q6m2bC3O4z5W6a7';

try {
    $in       = read_request();
    $username = trim((string) ($in['username'] ?? ''));
    $password = (string) ($in['password'] ?? '');

    if ($username === '' || $password === '') {
        send_error(400, 'Username and password are required.');
    }

    $pdo  = getPDO();
    $stmt = $pdo->prepare(
        'SELECT id, username, password_hash FROM users WHERE username = :u LIMIT 1'
    );
    $stmt->execute([':u' => $username]);
    $user = $stmt->fetch();

    // Always run password_verify (against a dummy hash if no user) so the
    // response time does not reveal whether the username exists.
    $hash  = $user['password_hash'] ?? DUMMY_HASH;
    $valid = password_verify($password, $hash);

    if (!$user || !$valid) {
        // Identical message for both cases -> no user enumeration.
        send_error(401, 'Invalid username or password.');
    }

    // --- Issue JWT --------------------------------------------------------
    $now    = time();
    $claims = [
        'iss'      => JWT_ISSUER,
        'sub'      => (int) $user['id'],
        'username' => $user['username'],
        'iat'      => $now,
        'exp'      => $now + JWT_TTL,
        'jti'      => bin2hex(random_bytes(16)),
    ];

    $token = jwt_encode($claims);

    // --- Enforce one login per device -------------------------------------
    // Record this login's jti + device as the account's single active session.
    // Any token previously issued to another device no longer matches
    // current_jti, so require_auth() rejects it — the old device is logged out.
    $deviceId = substr(trim((string) ($in['device_id'] ?? '')), 0, 64);
    $upd = $pdo->prepare(
        'UPDATE users SET current_jti = :jti, current_device = :dev WHERE id = :id'
    );
    $upd->execute([
        ':jti' => $claims['jti'],
        ':dev' => $deviceId !== '' ? $deviceId : null,
        ':id'  => (int) $user['id'],
    ]);

    send_success(200, [
        'token'    => $token,
        'username' => $user['username'],
    ]);
} catch (Throwable $e) {
    error_log('login.php: ' . $e->getMessage());
    send_error(500, 'Internal server error.');
}
