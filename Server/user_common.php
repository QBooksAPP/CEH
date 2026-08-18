<?php
declare(strict_types=1);

function qbook_normalize_username(mixed $value): string {
    return strtolower(trim((string)$value));
}

function qbook_validate_username(string $username): void {
    if (!preg_match('/\A[a-z0-9._-]{3,100}\z/', $username)) {
        qbook_json(['ok' => false, 'error' => 'INVALID_USERNAME'], 422);
    }
}

function qbook_public_user(array $row): array {
    return [
        'id' => (int)$row['id'],
        'full_name' => (string)$row['full_name'],
        'username' => $row['username'] !== null ? (string)$row['username'] : null,
        'email' => $row['email'] !== null ? (string)$row['email'] : null,
        'phone' => $row['phone'] !== null ? (string)$row['phone'] : null,
        'role' => (string)$row['role'],
        'is_active' => (bool)$row['is_active'],
    ];
}
