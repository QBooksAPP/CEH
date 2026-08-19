<?php
declare(strict_types=1);

require_once __DIR__ . '/production_log_common.php';

function production_report_reference(int $reportNo): string {
    return 'CEH-PR-' . str_pad((string)$reportNo, 6, '0', STR_PAD_LEFT);
}

/**
 * Return the permanent report number for a SIGNED session, allocating it once
 * while the caller holds the Production Session row lock and transaction.
 */
function production_report_issue(PDO $db, int $sessionId): array {
    $stmt = $db->prepare(
        "SELECT report_no, issued_at
         FROM qbook_production_reports
         WHERE production_session_id = ?
         LIMIT 1"
    );
    $stmt->execute([$sessionId]);
    $report = $stmt->fetch();
    if (!$report) {
        $issuedAt = gmdate('Y-m-d H:i:s');
        $db->prepare(
            "INSERT INTO qbook_production_reports (production_session_id, issued_at)
             VALUES (?, ?)"
        )->execute([$sessionId, $issuedAt]);
        $report = ['report_no' => (int)$db->lastInsertId(), 'issued_at' => $issuedAt];
    }
    $reportNo = (int)$report['report_no'];
    return [
        'report_no' => $reportNo,
        'reference' => production_report_reference($reportNo),
        'issued_at' => (string)$report['issued_at'],
    ];
}

function production_report_local_time(string $utc): string {
    $value = new DateTimeImmutable($utc, new DateTimeZone('UTC'));
    return $value->setTimezone(new DateTimeZone('Africa/Lagos'))
        ->format('d M Y H:i') . ' WAT';
}

/**
 * Select and prove a private writable PHP temporary directory for TCPDF.
 * Never fall back to the API/web directory for evidentiary image processing.
 */
function production_report_cache_directory(): string {
    $candidates = array_unique(array_filter([
        trim((string)ini_get('upload_tmp_dir')),
        sys_get_temp_dir(),
    ], static fn(string $path): bool => $path !== ''));
    foreach ($candidates as $candidate) {
        $resolved = realpath($candidate);
        if ($resolved === false || !is_dir($resolved) || !is_writable($resolved)) continue;
        $probe = @tempnam($resolved, 'ceh_pdf_probe_');
        if ($probe === false) continue;
        $written = @file_put_contents($probe, 'CEH');
        @unlink($probe);
        if ($written === 3) return rtrim($resolved, '/\\') . DIRECTORY_SEPARATOR;
    }
    throw new RuntimeException('PDF_PRIVATE_CACHE_UNAVAILABLE');
}

function production_report_blob_bytes(mixed $value): string {
    if (is_resource($value)) {
        $value = stream_get_contents($value);
    }
    if (!is_string($value) || $value === '') {
        throw new RuntimeException('PDF_IMAGE_DATA_MISSING');
    }
    return $value;
}

/**
 * Decode and re-encode a PNG through GD onto white. This preserves the visual
 * evidence while removing PNG profile/alpha variants that differ by device.
 */
function production_report_normalize_png(string $bytes): string {
    if (strlen($bytes) < 8 || substr($bytes, 0, 8) !== "\x89PNG\r\n\x1a\n") {
        throw new RuntimeException('PDF_IMAGE_NOT_PNG');
    }
    $source = @imagecreatefromstring($bytes);
    if ($source === false) throw new RuntimeException('PDF_IMAGE_DECODE_FAILED');
    $width = imagesx($source);
    $height = imagesy($source);
    if ($width <= 0 || $height <= 0 || $width > 5000 || $height > 5000) {
        imagedestroy($source);
        throw new RuntimeException('PDF_IMAGE_DIMENSIONS_INVALID');
    }
    $normalized = imagecreatetruecolor($width, $height);
    if ($normalized === false) {
        imagedestroy($source);
        throw new RuntimeException('PDF_IMAGE_NORMALIZE_FAILED');
    }
    $white = imagecolorallocate($normalized, 255, 255, 255);
    imagefill($normalized, 0, 0, $white);
    imagealphablending($source, true);
    imagecopy($normalized, $source, 0, 0, 0, 0, $width, $height);
    ob_start();
    $encoded = imagepng($normalized, null, 6);
    $png = ob_get_clean();
    imagedestroy($normalized);
    imagedestroy($source);
    if (!$encoded || !is_string($png) || $png === '') {
        throw new RuntimeException('PDF_IMAGE_ENCODE_FAILED');
    }
    return $png;
}
