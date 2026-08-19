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

function production_report_prove_writable_directory(string $candidate): ?string {
    $resolved = realpath($candidate);
    if ($resolved === false || !is_dir($resolved) || !is_writable($resolved)) return null;
    $probe = @tempnam($resolved, 'ceh_pdf_probe_');
    if ($probe === false) return null;
    $written = @file_put_contents($probe, 'CEH');
    @unlink($probe);
    return $written === 3 ? rtrim($resolved, '/\\') . DIRECTORY_SEPARATOR : null;
}

function production_report_create_request_cache(string $baseDirectory): ?string {
    $base = production_report_prove_writable_directory($baseDirectory);
    if ($base === null) return null;
    for ($attempt = 0; $attempt < 3; $attempt++) {
        try {
            $suffix = bin2hex(random_bytes(12));
        } catch (Throwable) {
            return null;
        }
        $requestCache = $base . 'ceh_pdf_' . $suffix;
        if (!@mkdir($requestCache, 0700)) continue;
        @chmod($requestCache, 0700);
        $verified = production_report_prove_writable_directory($requestCache);
        if ($verified !== null) return $verified;
        @rmdir($requestCache);
    }
    return null;
}

/** Remove files only from the cryptographically unique cache owned by this request. */
function production_report_cleanup_cache_directory(string $requestCache): void {
    $resolved = realpath($requestCache);
    if ($resolved === false || is_link($resolved)
        || !str_starts_with(basename($resolved), 'ceh_pdf_')) return;
    $entries = @scandir($resolved);
    if (is_array($entries)) {
        foreach ($entries as $entry) {
            if ($entry === '.' || $entry === '..') continue;
            $path = $resolved . DIRECTORY_SEPARATOR . $entry;
            if (is_file($path) || is_link($path)) @unlink($path);
        }
    }
    @rmdir($resolved);
}

/**
 * Select and prove a private writable directory for TCPDF. PHP's configured
 * temporary paths are preferred. IONOS may expose them but deny writes, so a
 * CEH-controlled, HTTP-blocked runtime directory is the final fallback.
 *
 * Optional arguments exist only to make the failure/fallback path testable.
 */
function production_report_cache_directory(
    ?array $privateTempCandidates = null,
    ?string $runtimeCache = null
): string {
    $candidates = $privateTempCandidates ?? [
        trim((string)ini_get('upload_tmp_dir')),
        sys_get_temp_dir(),
    ];
    $candidates = array_unique(array_filter(
        $candidates,
        static fn(mixed $path): bool => is_string($path) && trim($path) !== ''
    ));
    foreach ($candidates as $candidate) {
        $verified = production_report_create_request_cache($candidate);
        if ($verified !== null) return $verified;
    }

    $serverRoot = realpath(__DIR__);
    $runtimeCache ??= __DIR__ . '/runtime/pdf-cache';
    $runtimeRoot = dirname($runtimeCache);
    if ($serverRoot === false || is_link($runtimeRoot) || is_link($runtimeCache)) {
        throw new RuntimeException('PDF_PRIVATE_CACHE_UNAVAILABLE');
    }
    if (!is_dir($runtimeCache) && !@mkdir($runtimeCache, 0700, true) && !is_dir($runtimeCache)) {
        throw new RuntimeException('PDF_PRIVATE_CACHE_UNAVAILABLE');
    }
    @chmod($runtimeRoot, 0700);
    @chmod($runtimeCache, 0700);
    $resolvedRuntime = realpath($runtimeCache);
    $allowedPrefix = rtrim($serverRoot, '/\\') . DIRECTORY_SEPARATOR . 'runtime' . DIRECTORY_SEPARATOR;
    if ($resolvedRuntime === false
        || !str_starts_with($resolvedRuntime . DIRECTORY_SEPARATOR, $allowedPrefix)) {
        throw new RuntimeException('PDF_PRIVATE_CACHE_UNAVAILABLE');
    }
    $verified = production_report_create_request_cache($resolvedRuntime);
    if ($verified !== null) return $verified;
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

/**
 * Temporary Build #48 production diagnostic boundary. Remove the Admin-only
 * diagnostic_code after the IONOS image path has been verified. Never return
 * the underlying exception message because TCPDF may include local paths.
 */
function production_report_safe_diagnostic(Throwable $exception): string {
    return match ($exception->getMessage()) {
        'PDF_PRIVATE_CACHE_UNAVAILABLE' => 'PDF_CACHE_UNAVAILABLE',
        'PDF_LOGO_UNREADABLE' => 'PDF_LOGO_UNREADABLE',
        'PDF_LOGO_INVALID' => 'PDF_LOGO_INVALID',
        'PDF_SIGNATURE_MISSING' => 'PDF_SIGNATURE_MISSING',
        'PDF_SIGNATURE_HASH_MISMATCH' => 'PDF_SIGNATURE_HASH_MISMATCH',
        'PDF_SIGNATURE_INVALID' => 'PDF_SIGNATURE_INVALID',
        'PDF_IMAGE_EMBED_FAILED' => 'PDF_IMAGE_EMBED_FAILED',
        'PDF_REQUIRED_IMAGES_MISSING' => 'PDF_OUTPUT_IMAGES_MISSING',
        'PDF_ENGINE_UNAVAILABLE' => 'PDF_ENGINE_UNAVAILABLE',
        default => 'PDF_RENDER_FAILED',
    };
}

function production_report_fail(array $user, Throwable $exception): never {
    $code = production_report_safe_diagnostic($exception);
    error_log('CEH Production Report generation failed [' . $code . ']');
    $response = ['ok' => false, 'error' => 'PRODUCTION_REPORT_FAILED'];
    if (($user['role'] ?? '') === 'ADMIN') {
        // Existing Flutter versions display `error`, so Admin can diagnose
        // this temporary production check without a diagnostic APK.
        $response['error'] = $code;
        $response['diagnostic_code'] = $code;
    }
    qbook_json($response, 500);
}
