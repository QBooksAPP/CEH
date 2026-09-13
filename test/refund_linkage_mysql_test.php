<?php
// Run only against a disposable loopback MySQL instance on port 33317.
declare(strict_types=1);
require_once __DIR__.'/../Server/general_expense_refunds_common.php';
restore_exception_handler();
function connection(): PDO {
    $port=(int)(getenv('CEH_LOCAL_TEST_PORT')?:33317);
    if(!in_array($port,[33317,33318],true))throw new RuntimeException('Local test port required');
    return new PDO('mysql:host=127.0.0.1;port='.$port.';dbname=ceh_refund_test;charset=utf8mb4', 'root', '',
        [PDO::ATTR_ERRMODE=>PDO::ERRMODE_EXCEPTION, PDO::ATTR_DEFAULT_FETCH_MODE=>PDO::FETCH_ASSOC, PDO::ATTR_EMULATE_PREPARES=>false]);
}
if (($argv[1] ?? '') === 'worker') {
    try { general_expense_link_refund(connection(), ['id'=>1], (int)$argv[2], (int)$argv[3]); echo 'LINKED'; }
    catch (AccountsApiError $e) { echo $e->errorCode; }
    exit;
}
$db = connection();
$assertions = 0;
function check(bool $condition, string $label): void {
    global $assertions;
    if (!$condition) throw new RuntimeException('FAIL: '.$label);
    $assertions++;
}
function rejects(PDO $db, int $expense, int $row, string $code): void {
    try { general_expense_link_refund($db, ['id'=>1], $expense, $row); throw new RuntimeException('Expected '.$code); }
    catch (AccountsApiError $e) { check($e->errorCode === $code, $code); }
}
function simultaneous(PDO $db, array $attempts): array {
    // Hold the expense lock while both worker requests start, then release it.
    $db->beginTransaction();
    $db->query('SELECT id FROM qbook_general_expenses WHERE id IN (2,3,4) FOR UPDATE')->fetchAll();
    $jobs = [];
    foreach ($attempts as [$expense,$row]) {
        $command = [PHP_BINARY, '-d', 'extension_dir='.ini_get('extension_dir'), '-d', 'extension=pdo_mysql', __FILE__, 'worker', (string)$expense, (string)$row];
        $process = proc_open($command, [1=>['pipe','w'],2=>['pipe','w']], $pipes);
        if (!is_resource($process)) throw new RuntimeException('Worker launch failed');
        $jobs[] = [$process,$pipes];
    }
    usleep(400000); $db->commit();
    $results = [];
    foreach ($jobs as [$process,$pipes]) {
        $results[] = trim(stream_get_contents($pipes[1]));
        $error = stream_get_contents($pipes[2]);
        fclose($pipes[1]); fclose($pipes[2]);
        check(proc_close($process) === 0 && $error === '', 'worker completed: '.$error);
    }
    sort($results); return $results;
}
try {
    check($db->query('SELECT DATABASE()')->fetchColumn() === 'ceh_refund_test', 'isolated database');
    check((int)$db->query('SELECT COUNT(*) FROM information_schema.tables WHERE table_schema=DATABASE()')->fetchColumn() === 0, 'empty test schema required');
    $schema = [
      'CREATE TABLE qbook_users(id BIGINT PRIMARY KEY,full_name VARCHAR(100)) ENGINE=InnoDB',
      'CREATE TABLE qbook_bank_accounts(id BIGINT PRIMARY KEY,name VARCHAR(100)) ENGINE=InnoDB',
      'CREATE TABLE qbook_general_expenses(id BIGINT PRIMARY KEY,amount DECIMAL(18,2),bank_account_id BIGINT,status VARCHAR(30),journal_id BIGINT) ENGINE=InnoDB',
      'CREATE TABLE qbook_general_expense_references(expense_id BIGINT PRIMARY KEY,reference_no INT) ENGINE=InnoDB',
      'CREATE TABLE qbook_bank_statement_rows(id BIGINT PRIMARY KEY,bank_account_id BIGINT,amount DECIMAL(18,2),transaction_date DATE,bank_reference VARCHAR(150),narration VARCHAR(500),status VARCHAR(30)) ENGINE=InnoDB',
      'CREATE TABLE qbook_general_expense_refunds(id BIGINT PRIMARY KEY AUTO_INCREMENT,expense_id BIGINT,statement_row_id BIGINT UNIQUE,amount DECIMAL(18,2),linked_by BIGINT,linked_at DATETIME DEFAULT CURRENT_TIMESTAMP) ENGINE=InnoDB',
      'CREATE TABLE qbook_financial_audit(id BIGINT PRIMARY KEY AUTO_INCREMENT,event_type VARCHAR(100),source_type VARCHAR(100),source_record_id BIGINT,actor_user_id BIGINT,details_json JSON) ENGINE=InnoDB',
      'CREATE TABLE qbook_financial_journals(id BIGINT PRIMARY KEY,description VARCHAR(100)) ENGINE=InnoDB',
      'CREATE TABLE qbook_financial_journal_lines(id BIGINT PRIMARY KEY,debit DECIMAL(18,2),credit DECIMAL(18,2)) ENGINE=InnoDB'
    ];
    foreach ($schema as $sql) $db->exec($sql);
    $db->exec("INSERT INTO qbook_users VALUES(1,'Test Admin'); INSERT INTO qbook_bank_accounts VALUES(1,'Test Bank'),(2,'Other Bank')");
    $db->exec("INSERT INTO qbook_general_expenses VALUES(1,100000,1,'APPROVED',1),(2,1000,1,'APPROVED',2),(3,1000,1,'APPROVED',3),(4,1000,1,'APPROVED',4),(5,1000,1,'DRAFT',NULL)");
    $db->exec('ALTER TABLE qbook_general_expenses ADD created_from_statement_row_id BIGINT NULL UNIQUE');
    $db->exec('CREATE TABLE qbook_bank_matches(statement_row_id BIGINT PRIMARY KEY,source_type VARCHAR(60),source_record_id BIGINT) ENGINE=InnoDB');
    $db->exec('CREATE TABLE qbook_customer_receipts(id BIGINT PRIMARY KEY,statement_row_id BIGINT UNIQUE,status VARCHAR(30),journal_id BIGINT NULL) ENGINE=InnoDB');
    $db->exec('INSERT INTO qbook_general_expense_references VALUES(1,1)');
    $db->exec("INSERT INTO qbook_financial_journals VALUES(1,'Original immutable journal'); INSERT INTO qbook_financial_journal_lines VALUES(1,100000,0),(2,0,100000)");
    $insert = $db->prepare("INSERT INTO qbook_bank_statement_rows VALUES(?,?,?,'2026-09-01',?,?,'UNMATCHED')");
    foreach ([[1,1,40000],[2,1,60000],[3,1,-100],[4,2,100],[5,1,60001],[6,1,600],[7,1,600],[8,1,500]] as [$id,$bank,$amount]) $insert->execute([$id,$bank,$amount,'BANK-'.$id,'Refund '.$id]);
    for ($id=100; $id<351; $id++) $insert->execute([$id,1,1,'LARGE-'.$id,'Searchable refund '.$id]);
    $bankBefore = $db->query('SELECT * FROM qbook_bank_statement_rows ORDER BY id')->fetchAll();
    $journalBefore = $db->query('SELECT * FROM qbook_financial_journals')->fetchAll();
    $linesBefore = $db->query('SELECT * FROM qbook_financial_journal_lines')->fetchAll();
    $initial = general_expense_refunds_read($db,1,[]);
    check($initial['expense']['refund_status'] === 'NONE', 'none');
    rejects($db,1,3,'ACTUAL_BANK_CREDIT_REQUIRED'); rejects($db,1,4,'ACTUAL_BANK_CREDIT_REQUIRED');
    rejects($db,5,1,'EXPENSE_NOT_REFUNDABLE'); rejects($db,1,9999,'BANK_ROW_NOT_FOUND');
    general_expense_link_refund($db,['id'=>1],1,1);
    $partial = general_expense_refunds_read($db,1,[]);
    check($partial['expense']['refund_status'] === 'PARTIAL' && $partial['expense']['remaining_amount'] === '60000.00', 'partial totals');
    check($partial['total'] === 1 && $partial['rows'][0]['linked_by_name'] === 'Test Admin', 'history');
    rejects($db,1,1,'REFUND_ALREADY_LINKED'); rejects($db,1,5,'REFUND_EXCEEDS_EXPENSE');
    $eligible = general_expense_refunds_read($db,1,['view'=>'eligible','page_size'=>100]);
    $ids = array_column($eligible['rows'],'statement_row_id');
    check(!in_array(1,$ids) && !in_array(3,$ids) && !in_array(4,$ids) && !in_array(5,$ids), 'ineligible excluded');
    $page1 = general_expense_refunds_read($db,1,['view'=>'eligible','search'=>'LARGE-','page'=>1]);
    $page2 = general_expense_refunds_read($db,1,['view'=>'eligible','search'=>'LARGE-','page'=>2]);
    check($page1['total'] === 251 && count($page1['rows']) === 25 && $page1['total_pages'] === 11, 'large pagination');
    check(!array_intersect(array_column($page1['rows'],'statement_row_id'),array_column($page2['rows'],'statement_row_id')), 'pages disjoint');
    check($page2['expense']['remaining_amount'] === '60000.00', 'summary independent of page');
    check(general_expense_refunds_read($db,1,['view'=>'eligible','date_from'=>'2026-09-02'])['total'] === 0, 'date filter');
    general_expense_link_refund($db,['id'=>1],1,2);
    $full = general_expense_refunds_read($db,1,[]);
    check($full['expense']['refund_status'] === 'FULL' && !$full['expense']['can_link'] && $full['expense']['remaining_amount'] === '0.00', 'multiple partial exact full');
    check($full['total'] === 2 && $full['expense']['linked_amount'] === '100000.00', 'full history total');
    check(general_expense_refunds_read($db,1,['view'=>'eligible'])['total'] === 0, 'full no eligible');
    check(simultaneous($db,[[2,6],[2,7]]) === ['LINKED','REFUND_EXCEEDS_EXPENSE'], 'concurrent over-refund rejected');
    check(simultaneous($db,[[3,8],[4,8]]) === ['LINKED','REFUND_ALREADY_LINKED'], 'concurrent reuse rejected');
    check($bankBefore === $db->query('SELECT * FROM qbook_bank_statement_rows ORDER BY id')->fetchAll(), 'bank immutable');
    check($journalBefore === $db->query('SELECT * FROM qbook_financial_journals')->fetchAll() && $linesBefore === $db->query('SELECT * FROM qbook_financial_journal_lines')->fetchAll(), 'journals unchanged');
    check((int)$db->query("SELECT COUNT(*) FROM qbook_financial_audit WHERE event_type='GENERAL_EXPENSE_REFUND_LINKED'")->fetchColumn() === 4, 'successful links audited once');
    echo "REFUND_MYSQL_TESTS_PASSED assertions={$assertions}\n";
} catch (Throwable $e) { fwrite(STDERR,$e->getMessage()."\n"); exit(1); }
