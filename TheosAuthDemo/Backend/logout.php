<?php
/**
 * logout.php  (POST /logout.php)
 * ------------------------------
 * Stateless-JWT logout.
 *
 * A JWT is self-contained, so "logging out" cannot un-issue it. To get real
 * server-side invalidation we keep a small revocation list keyed by the token
 * `jti`. We store the jti until its natural expiry; expired rows are pruned on
 * write, so the table never grows unbounded.
 *
 * The client should ALSO discard its stored token (it does – see AuthManager).
 */

declare(strict_types=1);

require_once __DIR__ . '/middleware.php';

require_method('POST');

try {
    $claims = require_auth();

    $pdo = getPDO();

    // Prune already-expired revocations (housekeeping).
    $pdo->prepare('DELETE FROM revoked_tokens WHERE expires_at < NOW()')->execute();

    // Revoke this token's jti until it would have expired anyway.
    $stmt = $pdo->prepare(
        'INSERT IGNORE INTO revoked_tokens (jti, expires_at)
         VALUES (:jti, FROM_UNIXTIME(:exp))'
    );
    $stmt->execute([
        ':jti' => (string) $claims['jti'],
        ':exp' => (int) $claims['exp'],
    ]);

    // Free the one-login-per-device slot, but only if this token is still the
    // active one — don't clobber a newer device that already took over.
    $clear = $pdo->prepare(
        'UPDATE users SET current_jti = NULL, current_device = NULL
         WHERE id = :id AND current_jti = :jti'
    );
    $clear->execute([
        ':id'  => (int) $claims['sub'],
        ':jti' => (string) $claims['jti'],
    ]);

    send_success(200, ['message' => 'Logged out successfully.']);
} catch (Throwable $e) {
    error_log('logout.php: ' . $e->getMessage());
    send_error(500, 'Internal server error.');
}
