<?php
declare(strict_types=1);

require __DIR__ . '/bootstrap.php';

try {
    qbook_db()->query('SELECT 1');

    qbook_json([
        'ok' => true,
        'status' => 'healthy',
        'serverTime' => qbook_server_time(),
    ]);
} catch (Throwable $e) {
    qbook_json([
        'ok' => false,
        'status' => 'unavailable',
        'serverTime' => qbook_server_time(),
    ], 503);
}
