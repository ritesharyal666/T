<?php
/**
 * middleware.php
 * --------------
 * Shared request/response plumbing used by every endpoint:
 *   - require_method()  : enforce HTTP verb
 *   - read_request()    : decrypt + decode the encrypted JSON body
 *   - send_response()   : encrypt + encode a JSON reply, then exit
 *   - require_auth()    : validate the Bearer JWT (and revocation)
 *   - rate_limit()      : simple per-IP sliding-window limiter
 *
 * All responses are AES-encrypted envelopes so the client decrypt path is
 * uniform regardless of success/error.
 */

declare(strict_types=1);

require_once __DIR__ . '/config.php';
require_once __DIR__ . '/db.php';
require_once __DIR__ . '/crypto.php';
require_once __DIR__ . '/jwt.php';

/**
 * Encrypt a payload array and emit it as the HTTP response, then stop.
 */
function send_response(int $status, array $payload): void
{
    http_response_code($status);
    header('Content-Type: application/json');
    header('X-Content-Type-Options: nosniff');

    $json = (string) json_encode($payload, JSON_UNESCAPED_SLASHES);
    echo json_encode(crypto_encrypt($json));
    exit;
}

/** Convenience helpers for the standard JSON shapes. */
function send_error(int $status, string $message): void
{
    send_response($status, ['success' => false, 'error' => $message]);
}

function send_success(int $status, array $extra = []): void
{
    send_response($status, array_merge(['success' => true], $extra));
}

/** Enforce the expected HTTP method. */
function require_method(string $method): void
{
    if (($_SERVER['REQUEST_METHOD'] ?? '') !== strtoupper($method)) {
        send_error(405, 'Method not allowed.');
    }
}

/**
 * Read, decrypt and JSON-decode the request body.
 *
 * @return array Decoded plaintext payload.
 */
function read_request(): array
{
    $raw = file_get_contents('php://input');
    if ($raw === false || $raw === '') {
        send_error(400, 'Empty request body.');
    }

    $env = json_decode($raw, true);
    if (!is_array($env) || !isset($env['iv'], $env['ct'], $env['mac'])) {
        send_error(400, 'Malformed encrypted request.');
    }

    $plain = crypto_decrypt($env);
    if ($plain === null) {
        send_error(400, 'Unable to decrypt request (integrity check failed).');
    }

    $data = json_decode($plain, true);
    if (!is_array($data)) {
        send_error(400, 'Invalid JSON payload.');
    }

    return $data;
}

/** Robustly fetch the Authorization header across SAPIs. */
function get_authorization_header(): ?string
{
    if (!empty($_SERVER['HTTP_AUTHORIZATION'])) {
        return trim($_SERVER['HTTP_AUTHORIZATION']);
    }
    if (!empty($_SERVER['REDIRECT_HTTP_AUTHORIZATION'])) {
        return trim($_SERVER['REDIRECT_HTTP_AUTHORIZATION']);
    }
    if (function_exists('apache_request_headers')) {
        $headers = apache_request_headers();
        foreach ($headers as $name => $value) {
            if (strtolower($name) === 'authorization') {
                return trim($value);
            }
        }
    }
    return null;
}

/** Has this token's jti been revoked (via logout)? */
function is_token_revoked(string $jti): bool
{
    if ($jti === '') {
        return true;
    }
    $stmt = getPDO()->prepare('SELECT 1 FROM revoked_tokens WHERE jti = :jti LIMIT 1');
    $stmt->execute([':jti' => $jti]);
    return (bool) $stmt->fetchColumn();
}

/**
 * One login per device: is this jti the account's current (only) active
 * session? A newer login on another device overwrites current_jti, so an
 * older device's token — though otherwise valid — is treated as logged out.
 */
function is_active_session(int $userId, string $jti): bool
{
    if ($userId <= 0 || $jti === '') {
        return false;
    }
    $stmt = getPDO()->prepare('SELECT current_jti FROM users WHERE id = :id LIMIT 1');
    $stmt->execute([':id' => $userId]);
    $current = $stmt->fetchColumn();
    return is_string($current) && hash_equals($current, $jti);
}

/**
 * Require a valid, non-revoked Bearer token. Returns the JWT claims.
 */
function require_auth(): array
{
    $header = get_authorization_header();
    if ($header === null || !preg_match('/^Bearer\s+(.+)$/i', $header, $m)) {
        send_error(401, 'Missing or invalid Authorization header.');
    }

    $claims = jwt_decode(trim($m[1]));
    if ($claims === null) {
        send_error(401, 'Invalid or expired token.');
    }

    if (is_token_revoked((string) ($claims['jti'] ?? ''))) {
        send_error(401, 'Token has been revoked.');
    }

    // One login per device: reject tokens superseded by a newer login.
    if (!is_active_session((int) ($claims['sub'] ?? 0), (string) ($claims['jti'] ?? ''))) {
        send_error(401, 'Session ended: your account was signed in on another device.');
    }

    return $claims;
}

/**
 * Sliding-window per-IP rate limiter, backed by the rate_limits table.
 * Call at the top of sensitive endpoints (login/register).
 */
function rate_limit(string $endpoint): void
{
    $pdo       = getPDO();
    $ip        = (string) ($_SERVER['REMOTE_ADDR'] ?? '0.0.0.0');
    $threshold = date('Y-m-d H:i:s', time() - RATE_LIMIT_WINDOW);

    // Drop entries outside the current window for this IP/endpoint.
    $del = $pdo->prepare(
        'DELETE FROM rate_limits
         WHERE ip_address = :ip AND endpoint = :ep AND request_time < :t'
    );
    $del->execute([':ip' => $ip, ':ep' => $endpoint, ':t' => $threshold]);

    // Count remaining requests in the window.
    $cnt = $pdo->prepare(
        'SELECT COUNT(*) FROM rate_limits WHERE ip_address = :ip AND endpoint = :ep'
    );
    $cnt->execute([':ip' => $ip, ':ep' => $endpoint]);

    if ((int) $cnt->fetchColumn() >= RATE_LIMIT_MAX) {
        send_error(429, 'Too many requests. Please try again later.');
    }

    // Record this request.
    $ins = $pdo->prepare(
        'INSERT INTO rate_limits (ip_address, endpoint, request_time)
         VALUES (:ip, :ep, NOW())'
    );
    $ins->execute([':ip' => $ip, ':ep' => $endpoint]);
}
