<?php
declare(strict_types=1);

require_once __DIR__ . '/auth.php';

/*
 * Production evidence timestamps are stored as UTC. This scopes the timezone
 * change to Production Log requests and avoids changing unrelated legacy API
 * timestamp behaviour on a server whose SYSTEM timezone is not UTC.
 */
function production_db(): PDO {
    static $configured = false;
    $db = qbook_db();
    if (!$configured) {
        $db->exec("SET time_zone = '+00:00'");
        $configured = true;
    }
    return $db;
}

function production_require_method(string $method): void {
    if ($_SERVER['REQUEST_METHOD'] !== $method) {
        qbook_json(['ok' => false, 'error' => 'METHOD_NOT_ALLOWED'], 405);
    }
}

function production_input(): array {
    $input = json_decode(file_get_contents('php://input'), true);
    if (!is_array($input)) qbook_json(['ok' => false, 'error' => 'INVALID_JSON'], 400);
    return $input;
}

function production_can_access(array $user, array $session): bool {
    return $user['role'] === 'ADMIN' || (int)$session['operator_id'] === (int)$user['id'];
}

function production_session_row(PDO $db, int $id, bool $lock = false): array {
    $sql = "SELECT * FROM qbook_production_sessions WHERE id = ?" . ($lock ? " FOR UPDATE" : "");
    $stmt = $db->prepare($sql);
    $stmt->execute([$id]);
    $row = $stmt->fetch();
    if (!$row) qbook_json(['ok' => false, 'error' => 'PRODUCTION_SESSION_NOT_FOUND'], 404);
    return $row;
}

function production_loads(PDO $db, int $sessionId): array {
    $stmt = $db->prepare("SELECT id, load_number, volume_m3, recorded_at, updated_at FROM qbook_production_loads WHERE production_session_id = ? ORDER BY load_number");
    $stmt->execute([$sessionId]);
    return array_map(static fn(array $r): array => [
        'id' => (int)$r['id'], 'load_number' => (int)$r['load_number'],
        'volume_m3' => round((float)$r['volume_m3'], 2),
        'recorded_at' => $r['recorded_at'], 'updated_at' => $r['updated_at'],
    ], $stmt->fetchAll());
}

function production_payload(PDO $db, array $row, bool $includeSignature = false): array {
    $loads = production_loads($db, (int)$row['id']);
    $total = round(array_sum(array_column($loads, 'volume_m3')), 2);
    $signoff = null;
    if ($row['status'] === 'SIGNED') {
        $stmt = $db->prepare("SELECT representative_name, signature_mime, signature_data, signature_sha256, load_count, total_m3, signed_at FROM qbook_production_signoffs WHERE production_session_id = ?");
        $stmt->execute([(int)$row['id']]);
        $s = $stmt->fetch();
        if ($s) {
            $signoff = [
                'representative_name' => $s['representative_name'], 'signed_at' => $s['signed_at'],
                'load_count' => (int)$s['load_count'], 'total_m3' => round((float)$s['total_m3'], 2),
                'signature_mime' => $s['signature_mime'], 'signature_sha256' => $s['signature_sha256'],
            ];
            if ($includeSignature) $signoff['signature_base64'] = base64_encode($s['signature_data']);
        }
    }
    return [
        'id' => (int)$row['id'], 'production_date' => $row['production_date'],
        'client_name' => $row['client_name'], 'project_site' => $row['project_site'],
        'mixer' => ['id' => (int)$row['mixer_id'], 'code' => $row['mixer_code_snapshot'], 'name' => $row['mixer_name_snapshot']],
        'loading_point' => $row['loading_point'], 'discharge_point' => $row['discharge_point'],
        'operator' => ['id' => (int)$row['operator_id'], 'name' => $row['operator_name_snapshot']],
        'notes' => $row['notes'], 'status' => $row['status'], 'created_at' => $row['created_at'],
        'signed_at' => $row['signed_at'], 'loads' => $loads, 'load_count' => count($loads),
        'total_m3' => $total, 'signoff' => $signoff,
    ];
}

function production_clean_text(mixed $value, int $max, string $error, bool $required = true): string {
    $value = trim((string)$value);
    if (($required && $value === '') || mb_strlen($value) > $max) qbook_json(['ok' => false, 'error' => $error], 422);
    return $value;
}
