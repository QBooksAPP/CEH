<?php
declare(strict_types=1);

require_once __DIR__ . '/auth.php';

$user = qbook_require_user();
qbook_require_role($user, ['ADMIN', 'SUPERVISOR', 'OPERATOR', 'VIEWER']);

if ($_SERVER['REQUEST_METHOD'] !== 'GET') {
    qbook_json(['ok' => false, 'error' => 'METHOD_NOT_ALLOWED'], 405);
}

$stmt = qbook_db()->query(
    "SELECT id, code, name, notes
     FROM qbook_mixers
     WHERE is_active = 1
     ORDER BY code"
);

$mixers = [];

foreach ($stmt->fetchAll() as $row) {
    $mixers[] = [
        'id' => (int)$row['id'],
        'code' => (string)$row['code'],
        'name' => (string)$row['name'],
        'notes' => $row['notes'],
    ];
}

qbook_json([
    'ok' => true,
    'mixers' => $mixers,
]);
