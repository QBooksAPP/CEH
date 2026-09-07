<?php
declare(strict_types=1);
require_once __DIR__ . '/accounts_common.php';

$user = qbook_require_user();
qbook_require_role($user, ['ADMIN']);
production_require_method('GET');

accounts_endpoint(function (): array {
    $db = production_db();
    $accountId = (int)($_GET['account_id'] ?? 0);
    if ($accountId <= 0) accounts_fail('ACCOUNT_REQUIRED');

    $page = max(1, (int)($_GET['page'] ?? 1));
    $pageSize = min(100, max(10, (int)($_GET['page_size'] ?? 50)));
    $offset = ($page - 1) * $pageSize;
    $dateFrom = trim((string)($_GET['date_from'] ?? ''));
    $dateTo = trim((string)($_GET['date_to'] ?? ''));
    if ($dateFrom !== '') $dateFrom = accounts_date($dateFrom);
    if ($dateTo !== '') $dateTo = accounts_date($dateTo);
    if ($dateFrom !== '' && $dateTo !== '' && $dateFrom > $dateTo) accounts_fail('INVALID_DATE_RANGE');

    $dimensions = [
        'project_id' => (int)($_GET['project_id'] ?? 0),
        'mixer_id' => (int)($_GET['mixer_id'] ?? 0),
        'client_id' => (int)($_GET['client_id'] ?? 0),
        'cost_centre_id' => (int)($_GET['cost_centre_id'] ?? 0),
    ];
    $account = $db->prepare('SELECT id,code,name,account_type FROM qbook_accounts_chart WHERE id=?');
    $account->execute([$accountId]);
    $accountRow = $account->fetch();
    if (!$accountRow) accounts_fail('ACCOUNT_NOT_FOUND', 404);

    $baseWhere = ['l.account_id=?'];
    $baseParams = [$accountId];
    foreach ($dimensions as $column => $value) {
        if ($value > 0) {
            $baseWhere[] = "l.{$column}=?";
            $baseParams[] = $value;
        }
    }
    $openingWhere = $baseWhere;
    $openingParams = $baseParams;
    if ($dateFrom !== '') {
        $openingWhere[] = 'j.transaction_date<?';
        $openingParams[] = $dateFrom;
    } else {
        $openingWhere[] = '1=0';
    }
    $openingSql = 'SELECT COALESCE(SUM(l.debit-l.credit),0) FROM qbook_financial_journal_lines l JOIN qbook_financial_journals j ON j.id=l.journal_id WHERE ' . implode(' AND ', $openingWhere);
    $openingStmt = $db->prepare($openingSql);
    $openingStmt->execute($openingParams);
    $opening = (string)$openingStmt->fetchColumn();

    $rangeWhere = $baseWhere;
    $rangeParams = $baseParams;
    if ($dateFrom !== '') { $rangeWhere[] = 'j.transaction_date>=?'; $rangeParams[] = $dateFrom; }
    if ($dateTo !== '') { $rangeWhere[] = 'j.transaction_date<=?'; $rangeParams[] = $dateTo; }
    $whereSql = implode(' AND ', $rangeWhere);
    $count = $db->prepare('SELECT COUNT(*) FROM qbook_financial_journal_lines l JOIN qbook_financial_journals j ON j.id=l.journal_id WHERE ' . $whereSql);
    $count->execute($rangeParams);
    $total = (int)$count->fetchColumn();

    $sql = "SELECT x.*,(CAST(? AS DECIMAL(18,2))+x.range_balance) AS running_balance FROM (
        SELECT l.id,l.journal_id,l.line_no,j.reference_no AS journal_reference,j.transaction_date,j.description AS journal_description,
               j.source_module,j.source_record_id,j.entry_kind,j.status,l.description,l.debit,l.credit,
               cc.code AS cost_centre_code,cc.name AS cost_centre_name,c.name AS client_name,p.name AS project_name,m.code AS mixer_code,
               SUM(l.debit-l.credit) OVER (ORDER BY j.transaction_date,j.id,l.line_no,l.id) AS range_balance
        FROM qbook_financial_journal_lines l
        JOIN qbook_financial_journals j ON j.id=l.journal_id
        LEFT JOIN qbook_cost_centres cc ON cc.id=l.cost_centre_id
        LEFT JOIN qbook_clients c ON c.id=l.client_id
        LEFT JOIN qbook_projects p ON p.id=l.project_id
        LEFT JOIN qbook_mixers m ON m.id=l.mixer_id
        WHERE {$whereSql}
    ) x ORDER BY x.transaction_date,x.journal_id,x.line_no,x.id LIMIT {$pageSize} OFFSET {$offset}";
    $stmt = $db->prepare($sql);
    $stmt->execute(array_merge([$opening], $rangeParams));

    return [
        'account' => $accountRow,
        'opening_balance' => $opening,
        'entries' => $stmt->fetchAll(),
        'pagination' => ['page'=>$page,'page_size'=>$pageSize,'total'=>$total,'total_pages'=>(int)ceil($total/$pageSize)],
    ];
});
