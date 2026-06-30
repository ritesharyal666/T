<?php
/**
 * db.php
 * ------
 * Returns a singleton PDO connection configured for safe, prepared-statement
 * only usage:
 *   - ERRMODE_EXCEPTION  -> failures throw, never silently continue
 *   - EMULATE_PREPARES = false -> real server-side prepared statements
 *   - FETCH_ASSOC -> predictable associative result rows
 */

declare(strict_types=1);

require_once __DIR__ . '/config.php';

function getPDO(): PDO
{
    static $pdo = null;

    if ($pdo === null) {
        $dsn = sprintf(
            'mysql:host=%s;dbname=%s;charset=%s',
            DB_HOST,
            DB_NAME,
            DB_CHARSET
        );

        $pdo = new PDO($dsn, DB_USER, DB_PASS, [
            PDO::ATTR_ERRMODE            => PDO::ERRMODE_EXCEPTION,
            PDO::ATTR_DEFAULT_FETCH_MODE => PDO::FETCH_ASSOC,
            PDO::ATTR_EMULATE_PREPARES   => false,
        ]);
    }

    return $pdo;
}
