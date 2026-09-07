<?php
declare(strict_types=1);
require_once __DIR__ . '/accounts_common.php';

$user = qbook_require_user();
qbook_require_role($user, ['ADMIN']);
production_require_method('GET');

accounts_endpoint(function (): array {
    $db = production_db();
    $dateFrom = trim((string)($_GET['date_from'] ?? ''));
    $dateTo = trim((string)($_GET['date_to'] ?? ''));
    $search = trim((string)($_GET['search'] ?? ''));
    $includeZero = (string)($_GET['include_zero'] ?? '') === '1';
    if ($dateFrom !== '') $dateFrom = accounts_date($dateFrom);
    if ($dateTo !== '') $dateTo = accounts_date($dateTo);
    if ($dateFrom !== '' && $dateTo !== '' && $dateFrom > $dateTo) accounts_fail('INVALID_DATE_RANGE');

    $where = [];
    $params = [];
    if ($dateFrom !== '') { $where[] = 'j.transaction_date>=?'; $params[] = $dateFrom; }
    if ($dateTo !== '') { $where[] = 'j.transaction_date<=?'; $params[] = $dateTo; }
    if ($search !== '') {
        $where[] = '(a.code LIKE ? OR a.name LIKE ?)';
        $like = '%' . $search . '%';
        array_push($params, $like, $like);
    }
    $whereSql = $where ? 'WHERE ' . implode(' AND ', $where) : '';
    $having = $includeZero ? '' : 'HAVING ROUND(SUM(l.debit-l.credit),2)<>0';
    $sql = "SELECT a.id account_id,a.code account_code,a.name account_name,a.account_type,
                   CASE WHEN ROUND(SUM(l.debit-l.credit),2)>0 THEN ROUND(SUM(l.debit-l.credit),2) ELSE 0 END debit_balance,
                   CASE WHEN ROUND(SUM(l.debit-l.credit),2)<0 THEN ABS(ROUND(SUM(l.debit-l.credit),2)) ELSE 0 END credit_balance
            FROM qbook_financial_journal_lines l
            JOIN qbook_financial_journals j ON j.id=l.journal_id
            JOIN qbook_accounts_chart a ON a.id=l.account_id
            {$whereSql}
            GROUP BY a.id,a.code,a.name,a.account_type
            {$having}
            ORDER BY a.code,a.name";
    $stmt = $db->prepare($sql);
    $stmt->execute($params);
    $rows = $stmt->fetchAll();
    $totalDebit = 0.0;
    $totalCredit = 0.0;
    foreach ($rows as $row) {
        $totalDebit += (float)$row['debit_balance'];
        $totalCredit += (float)$row['credit_balance'];
    }
    return [
        'basis' => ['date_from'=>$dateFrom?:null, 'date_to'=>$dateTo?:null, 'currency'=>'NGN'],
        'accounts' => $rows,
        'total_debit' => number_format($totalDebit, 2, '.', ''),
        'total_credit' => number_format($totalCredit, 2, '.', ''),
        'balanced' => abs($totalDebit-$totalCredit) < 0.005,
    ];
});
