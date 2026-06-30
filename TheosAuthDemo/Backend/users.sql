-- users.sql
-- Schema for the TheosAuthDemo backend.
-- Run with:  mysql -u root -p < users.sql

CREATE DATABASE IF NOT EXISTS theos_auth_demo
    CHARACTER SET utf8mb4
    COLLATE utf8mb4_unicode_ci;

USE theos_auth_demo;

-- ---------------------------------------------------------------------------
-- Accounts. Passwords are stored ONLY as password_hash() hashes.
-- ---------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS users (
    id             BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
    username       VARCHAR(32)     NOT NULL,
    password_hash  VARCHAR(255)    NOT NULL,
    -- One login per device: the jti + device id of the single device currently
    -- allowed to use this account. Each login overwrites these, which instantly
    -- invalidates the previous device's token (see require_auth() — any token
    -- whose jti != current_jti is rejected). NULL = no active session.
    current_jti    CHAR(32)        DEFAULT NULL,
    current_device VARCHAR(64)     DEFAULT NULL,
    created_at     DATETIME        NOT NULL DEFAULT CURRENT_TIMESTAMP,
    PRIMARY KEY (id),
    UNIQUE KEY uq_username (username)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- Upgrading an existing install (table already created without these columns)?
-- Run these once; they will error harmlessly ("Duplicate column") on fresh DBs:
--   ALTER TABLE users ADD COLUMN current_jti    CHAR(32)    DEFAULT NULL;
--   ALTER TABLE users ADD COLUMN current_device VARCHAR(64) DEFAULT NULL;

-- ---------------------------------------------------------------------------
-- Revoked JWT ids (server-side logout). Pruned when expires_at passes.
-- ---------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS revoked_tokens (
    jti        CHAR(32)  NOT NULL,
    expires_at DATETIME  NOT NULL,
    PRIMARY KEY (jti),
    KEY idx_expires (expires_at)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- ---------------------------------------------------------------------------
-- Per-IP request log used by the simple rate limiter.
-- ---------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS rate_limits (
    id           BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
    ip_address   VARCHAR(45)     NOT NULL,
    endpoint     VARCHAR(64)     NOT NULL,
    request_time DATETIME        NOT NULL DEFAULT CURRENT_TIMESTAMP,
    PRIMARY KEY (id),
    KEY idx_ip_endpoint_time (ip_address, endpoint, request_time)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;
