<?php
declare(strict_types=1);

function qbook_recalculate_calibration_results(PDO $db, int $calibrationId): void
{
    $stmt = $db->prepare(
        "SELECT container_weight_kg, stone_moisture_pct, sand_moisture_pct,
                cement_safety_factor_pct
         FROM qbook_calibrations
         WHERE id = ?
         LIMIT 1"
    );
    $stmt->execute([$calibrationId]);
    $cal = $stmt->fetch();

    if (!$cal) {
        throw new RuntimeException('CALIBRATION_NOT_FOUND');
    }

    $container = (float)$cal['container_weight_kg'];
    $stoneMoisture = (float)$cal['stone_moisture_pct'];
    $sandMoisture = (float)$cal['sand_moisture_pct'];
    $cementSafety = (float)$cal['cement_safety_factor_pct'];

    $stmt = $db->prepare(
        "SELECT material, gate_cm, trial_no, total_weight_kg, counts
         FROM qbook_calibration_trials
         WHERE calibration_id = ?
         ORDER BY material, gate_cm, trial_no"
    );
    $stmt->execute([$calibrationId]);

    $groups = [];

    foreach ($stmt->fetchAll() as $row) {
        if ($row['total_weight_kg'] === null || $row['counts'] === null) {
            continue;
        }

        $weight = (float)$row['total_weight_kg'];
        $counts = (float)$row['counts'];
        if ($counts <= 0) {
            continue;
        }

        $material = (string)$row['material'];
        $gate = $row['gate_cm'] === null ? null : (float)$row['gate_cm'];
        $key = $material . '|' . ($gate === null ? 'NULL' : number_format($gate, 3, '.', ''));

        $net = $weight - $container;
        if ($net <= 0) {
            continue;
        }

        if ($material === 'STONE') {
            $net /= (1.0 + ($stoneMoisture / 100.0));
        } elseif ($material === 'SAND') {
            $net /= (1.0 + ($sandMoisture / 100.0));
        }

        if (!isset($groups[$key])) {
            $groups[$key] = [
                'material' => $material,
                'gate_cm' => $gate,
                'gross' => [],
                'net' => [],
                'counts' => [],
            ];
        }

        $groups[$key]['gross'][] = $weight;
        $groups[$key]['net'][] = $net;
        $groups[$key]['counts'][] = $counts;
    }

    $db->prepare("DELETE FROM qbook_calibration_results WHERE calibration_id = ?")
       ->execute([$calibrationId]);

    $insert = $db->prepare(
        "INSERT INTO qbook_calibration_results
         (calibration_id, material, gate_cm, avg_total_weight_kg, avg_counts,
          moisture_pct, net_dry_weight_kg, kg_per_count, calculated_at)
         VALUES (?, ?, ?, ?, ?, ?, ?, ?, UTC_TIMESTAMP())"
    );

    foreach ($groups as $g) {
        $n = count($g['counts']);
        if ($n === 0) {
            continue;
        }

        $avgGross = array_sum($g['gross']) / $n;
        $avgNet = array_sum($g['net']) / $n;
        $avgCounts = array_sum($g['counts']) / $n;
        if ($avgCounts <= 0) {
            continue;
        }

        $kgPerCount = $avgNet / $avgCounts;
        if ($g['material'] === 'CEMENT_FULL' || $g['material'] === 'CEMENT_HALF') {
            $kgPerCount *= (1.0 - ($cementSafety / 100.0));
        }

        $moisture = 0.0;
        if ($g['material'] === 'STONE') {
            $moisture = $stoneMoisture;
        } elseif ($g['material'] === 'SAND') {
            $moisture = $sandMoisture;
        }

        $insert->execute([
            $calibrationId,
            $g['material'],
            $g['gate_cm'],
            $avgGross,
            $avgCounts,
            $moisture,
            $avgNet,
            $kgPerCount,
        ]);
    }
}
