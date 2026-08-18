<?php
declare(strict_types=1);
require __DIR__ . '/bootstrap.php';

qbook_json([
    'ok' => true,
    'api' => 'CEH API',
    'version' => '1.0.0',
    'message' => 'CEH API is online.',
    'health' => 'health.php',
    'readOnly' => true,
    'serverTime' => qbook_server_time(),
]);
