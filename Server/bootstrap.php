<?php
declare(strict_types=1);

function qbook_config(): array {
    static $config = null;
    if ($config === null) {
        $config = require __DIR__ . '/config.php';
    }
    return $config;
}

function qbook_json(array $payload, int $status = 200): never {
    http_response_code($status);
    header('Content-Type: application/json; charset=utf-8');
    header('Cache-Control: no-store, no-cache, must-revalidate, max-age=0');
    header('X-Content-Type-Options: nosniff');
    echo json_encode($payload, JSON_UNESCAPED_SLASHES | JSON_UNESCAPED_UNICODE);
    exit;
}

function qbook_db(): PDO {
    static $pdo = null;
    if ($pdo instanceof PDO) return $pdo;

    $config = qbook_config();
    $db = $config['db'];

    if (empty($db['password']) || $db['password'] === 'YOUR_DATABASE_PASSWORD') {
        throw new RuntimeException('CEH database password has not been configured.');
    }

    $dsn = sprintf(
        'mysql:host=%s;port=%d;dbname=%s;charset=%s',
        $db['host'], $db['port'], $db['name'], $db['charset']
    );

    $pdo = new PDO(
        $dsn,
        $db['user'],
        $db['password'],
        [
            PDO::ATTR_ERRMODE => PDO::ERRMODE_EXCEPTION,
            PDO::ATTR_DEFAULT_FETCH_MODE => PDO::FETCH_ASSOC,
            PDO::ATTR_EMULATE_PREPARES => false,
        ]
    );

    return $pdo;
}

function qbook_server_time(): string {
    return gmdate('Y-m-d\TH:i:s\Z');
}
