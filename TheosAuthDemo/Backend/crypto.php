<?php
/**
 * crypto.php
 * ----------
 * Symmetric payload encryption shared with the iOS CryptoManager.
 *
 * Scheme: AES-256-CBC with Encrypt-then-MAC (HMAC-SHA256).
 *
 * Why CBC+HMAC and not GCM?
 *   AES-256-GCM is the preferred AEAD construction, but Apple's *public*
 *   CommonCrypto API does not expose a stable one-shot GCM interface to
 *   Objective-C (the GCM helpers live in private SPI headers). To keep the
 *   client fully buildable with only public APIs while still providing
 *   authenticated encryption, both sides use AES-256-CBC + HMAC-SHA256
 *   (Encrypt-then-MAC), which gives equivalent confidentiality + integrity.
 *
 * Wire format (JSON envelope, all fields standard base64):
 *   { "v": 1, "iv": "...", "ct": "...", "mac": "..." }
 *   mac = HMAC-SHA256(macKey, iv || ct)
 *
 * NOTE: This payload encryption is defense-in-depth. The real transport
 * security is TLS/HTTPS (enforced by .htaccess + iOS ATS). The pre-shared
 * key model used here is for the demo only.
 */

declare(strict_types=1);

require_once __DIR__ . '/config.php';

/**
 * Derive independent encryption and MAC keys from the shared master key.
 * Must mirror CryptoManager.m exactly.
 */
function crypto_keys(): array
{
    static $keys = null;

    if ($keys === null) {
        $master = hex2bin(CRYPTO_MASTER_KEY_HEX);
        if ($master === false || strlen($master) !== 32) {
            throw new RuntimeException('Invalid CRYPTO_MASTER_KEY_HEX (need 64 hex chars).');
        }
        $keys = [
            'enc' => hash('sha256', $master . 'enc', true), // 32 bytes -> AES-256
            'mac' => hash('sha256', $master . 'mac', true), // 32 bytes -> HMAC key
        ];
    }

    return $keys;
}

/**
 * Encrypt a plaintext string into a transport envelope.
 *
 * @return array{v:int,iv:string,ct:string,mac:string}
 */
function crypto_encrypt(string $plaintext): array
{
    $keys = crypto_keys();
    $iv   = random_bytes(16); // secure random IV

    $ct = openssl_encrypt(
        $plaintext,
        'aes-256-cbc',
        $keys['enc'],
        OPENSSL_RAW_DATA, // PKCS7 padding applied automatically
        $iv
    );

    if ($ct === false) {
        throw new RuntimeException('Encryption failed.');
    }

    $mac = hash_hmac('sha256', $iv . $ct, $keys['mac'], true);

    return [
        'v'   => 1,
        'iv'  => base64_encode($iv),
        'ct'  => base64_encode($ct),
        'mac' => base64_encode($mac),
    ];
}

/**
 * Verify + decrypt a transport envelope.
 *
 * @return string|null Plaintext on success, null on any validation failure.
 */
function crypto_decrypt(array $env): ?string
{
    if (!isset($env['iv'], $env['ct'], $env['mac'])) {
        return null;
    }

    $iv  = base64_decode((string) $env['iv'], true);
    $ct  = base64_decode((string) $env['ct'], true);
    $mac = base64_decode((string) $env['mac'], true);

    if ($iv === false || $ct === false || $mac === false) {
        return null;
    }
    if (strlen($iv) !== 16 || strlen($mac) !== 32) {
        return null;
    }

    $keys = crypto_keys();

    // Authenticate BEFORE decrypting (Encrypt-then-MAC). Constant-time compare.
    $expected = hash_hmac('sha256', $iv . $ct, $keys['mac'], true);
    if (!hash_equals($expected, $mac)) {
        return null;
    }

    $plaintext = openssl_decrypt(
        $ct,
        'aes-256-cbc',
        $keys['enc'],
        OPENSSL_RAW_DATA,
        $iv
    );

    return $plaintext === false ? null : $plaintext;
}
