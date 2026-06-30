<?php
/**
 * verify.php  (GET /verify.php)
 * -----------------------------
 * Validate the Bearer JWT and return the current user.
 * Used by the app on launch to confirm a stored token is still valid.
 *
 * Returns: { "success": true, "user": { id, username, created_at } }
 */

declare(strict_types=1);

require_once __DIR__ . '/middleware.php';

require_method('GET');

try {
    $claims = require_auth(); // 401s automatically on any failure

    $stmt = getPDO()->prepare(
        'SELECT id, username, created_at FROM users WHERE id = :id LIMIT 1'
    );
    $stmt->execute([':id' => (int) $claims['sub']]);
    $user = $stmt->fetch();

    if (!$user) {
        send_error(404, 'User not found.');
    }

    send_success(200, ['user' => $user]);
} catch (Throwable $e) {
    error_log('verify.php: ' . $e->getMessage());
    send_error(500, 'Internal server error.');
}
