<?php
declare(strict_types=1);

require_once __DIR__ . '/bootstrap.php';

function qbook_bearer_token(): string {
    $h = $_SERVER['HTTP_AUTHORIZATION'] ?? '';
    return preg_match('/Bearer\s+(.+)/i', $h, $m) ? trim($m[1]) : '';
}

function qbook_token_hash(string $t): string {
    return hash('sha256', $t);
}

function qbook_require_user(): array {
    $t = qbook_bearer_token();

    if ($t === '') {
        qbook_json([
            'ok' => false,
            'error' => 'UNAUTHORIZED'
        ], 401);
    }

    $s = qbook_db()->prepare(
        "SELECT
            u.id,
            u.full_name,
            u.email,
            u.phone,
            u.role,
            u.is_active
         FROM qbook_auth_tokens t
         JOIN qbook_users u
            ON u.id = t.user_id
         WHERE t.token_hash = ?
           AND t.revoked_at IS NULL
           AND t.expires_at > UTC_TIMESTAMP()
           AND u.is_active = 1
         LIMIT 1"
    );

    $s->execute([
        qbook_token_hash($t)
    ]);

    $u = $s->fetch();

    if (!$u) {
        qbook_json([
            'ok' => false,
            'error' => 'UNAUTHORIZED'
        ], 401);
    }

    return $u;
}

function qbook_require_role(array $u, array $roles): void {
    if (!in_array($u['role'], $roles, true)) {
        qbook_json([
            'ok' => false,
            'error' => 'FORBIDDEN'
        ], 403);
    }
}

/*
 * Determine client IP address.
 *
 * We prefer HTTP_X_FORWARDED_FOR when IONOS/proxy infrastructure
 * supplies it, otherwise REMOTE_ADDR.
 *
 * Only the first forwarded IP is stored.
 */
function qbook_client_ip(): ?string {

    $forwarded = trim(
        (string)($_SERVER['HTTP_X_FORWARDED_FOR'] ?? '')
    );

    if ($forwarded !== '') {

        $parts = explode(',', $forwarded);
        $ip = trim($parts[0]);

        if ($ip !== '') {
            return substr($ip, 0, 45);
        }
    }

    $remote = trim(
        (string)($_SERVER['REMOTE_ADDR'] ?? '')
    );

    if ($remote !== '') {
        return substr($remote, 0, 45);
    }

    return null;
}

/*
 * Shared QBook audit logger.
 *
 * IMPORTANT:
 * - Never pass passwords or bearer tokens into $details.
 * - Audit failure must NOT break the user's main action.
 *
 * Example:
 *
 * qbook_audit(
 *     $user,
 *     'CALIBRATION_APPROVED',
 *     'CALIBRATION',
 *     $calibrationId,
 *     [
 *         'mixer_id' => 4,
 *         'status' => 'APPROVED'
 *     ]
 * );
 */
function qbook_audit(
    ?array $user,
    string $eventType,
    ?string $sourceType = null,
    ?int $sourceId = null,
    ?array $details = null
): void {

    try {

        $eventType = strtoupper(trim($eventType));

        if ($eventType === '') {
            return;
        }

        $sourceType =
            $sourceType !== null
                ? strtoupper(trim($sourceType))
                : null;

        $userId = null;

        if (
            $user !== null &&
            isset($user['id']) &&
            (int)$user['id'] > 0
        ) {
            $userId = (int)$user['id'];
        }

        $detailsJson = null;

        if ($details !== null) {

            $detailsJson = json_encode(
                $details,
                JSON_UNESCAPED_UNICODE |
                JSON_UNESCAPED_SLASHES |
                JSON_INVALID_UTF8_SUBSTITUTE
            );

            if ($detailsJson === false) {
                $detailsJson = null;
            }
        }

        $stmt = qbook_db()->prepare(
            "INSERT INTO qbook_audit_log
            (
                user_id,
                event_type,
                source_type,
                source_id,
                details,
                ip_address
            )
            VALUES (?, ?, ?, ?, ?, ?)"
        );

        $stmt->execute([
            $userId,
            $eventType,
            $sourceType !== '' ? $sourceType : null,
            $sourceId,
            $detailsJson,
            qbook_client_ip()
        ]);

    } catch (Throwable $e) {

        /*
         * Intentionally do nothing.
         *
         * Audit logging is important, but a temporary audit-table
         * problem must not cause calibration approval, settings Apply,
         * or another valid production action to fail.
         */
    }
}