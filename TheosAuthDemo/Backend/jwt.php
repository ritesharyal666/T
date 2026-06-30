<?php
/**
 * jwt.php
 * -------
 * Minimal, dependency-free JWT (HS256) encode/decode.
 *
 * Claims used by this app:
 *   iss  - issuer (JWT_ISSUER)
 *   sub  - subject (user id)
 *   iat  - issued-at (unix time)
 *   exp  - expiry (iat + JWT_TTL, i.e. 24h)
 *   jti  - unique token id (used for server-side revocation / logout)
 *   username - convenience claim for display
 */

declare(strict_types=1);

require_once __DIR__ . '/config.php';

function base64url_encode(string $data): string
{
    return rtrim(strtr(base64_encode($data), '+/', '-_'), '=');
}

function base64url_decode(string $data): string
{
    $remainder = strlen($data) % 4;
    if ($remainder) {
        $data .= str_repeat('=', 4 - $remainder);
    }
    return (string) base64_decode(strtr($data, '-_', '+/'));
}

/**
 * Build a signed JWT from a claims array.
 */
function jwt_encode(array $claims): string
{
    $header = ['typ' => 'JWT', 'alg' => 'HS256'];

    $segments = [
        base64url_encode((string) json_encode($header, JSON_UNESCAPED_SLASHES)),
        base64url_encode((string) json_encode($claims, JSON_UNESCAPED_SLASHES)),
    ];

    $signingInput = implode('.', $segments);
    $signature    = hash_hmac('sha256', $signingInput, JWT_SECRET, true);
    $segments[]   = base64url_encode($signature);

    return implode('.', $segments);
}

/**
 * Validate signature + expiry and return the claims, or null if invalid.
 */
function jwt_decode(string $jwt): ?array
{
    $parts = explode('.', $jwt);
    if (count($parts) !== 3) {
        return null;
    }

    [$h, $p, $s] = $parts;

    // Verify signature in constant time.
    $expected = base64url_encode(hash_hmac('sha256', "$h.$p", JWT_SECRET, true));
    if (!hash_equals($expected, $s)) {
        return null;
    }

    $claims = json_decode(base64url_decode($p), true);
    if (!is_array($claims)) {
        return null;
    }

    // Reject expired / not-yet-valid tokens.
    $now = time();
    if (!isset($claims['exp']) || $now >= (int) $claims['exp']) {
        return null;
    }
    if (isset($claims['iat']) && $now + 60 < (int) $claims['iat']) {
        return null; // issued in the future (allow 60s clock skew)
    }

    return $claims;
}
