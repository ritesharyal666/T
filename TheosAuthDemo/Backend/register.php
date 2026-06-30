<?php
/**
 * register.php  (POST /register.php)
 * ----------------------------------
 * Create a new account.
 *   - validates username + password strength
 *   - rejects duplicate usernames
 *   - stores ONLY a password_hash() hash (never plaintext)
 */

declare(strict_types=1);

require_once __DIR__ . '/middleware.php';

require_method('POST');
rate_limit('register');

try {
    $in       = read_request();
    $username = trim((string) ($in['username'] ?? ''));
    $password = (string) ($in['password'] ?? '');

    // --- Input validation -------------------------------------------------
    if (!preg_match('/^[A-Za-z0-9_]{3,32}$/', $username)) {
        send_error(400, 'Username must be 3-32 characters (letters, numbers, underscore).');
    }
    if (strlen($password) < 8
        || !preg_match('/[A-Za-z]/', $password)
        || !preg_match('/[0-9]/', $password)) {
        send_error(400, 'Password must be at least 8 characters and contain a letter and a number.');
    }

    $pdo = getPDO();

    // --- Duplicate check (prepared statement) -----------------------------
    $stmt = $pdo->prepare('SELECT id FROM users WHERE username = :u LIMIT 1');
    $stmt->execute([':u' => $username]);
    if ($stmt->fetch()) {
        send_error(409, 'Username is already taken.');
    }

    // --- Hash + insert ----------------------------------------------------
    $hash = password_hash($password, PASSWORD_DEFAULT);

    $ins = $pdo->prepare(
        'INSERT INTO users (username, password_hash, created_at)
         VALUES (:u, :h, NOW())'
    );
    $ins->execute([':u' => $username, ':h' => $hash]);

    send_success(201, ['message' => 'Account created successfully.']);
} catch (Throwable $e) {
    // Never leak internal details to the client.
    error_log('register.php: ' . $e->getMessage());
    send_error(500, 'Internal server error.');
}
