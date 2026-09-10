<?php
declare(strict_types=1);
require_once __DIR__.'/bank_row_usage.php';

/** Statement identity is immutable. Resolve outside the transaction so the
 * hint cannot establish an old repeatable-read snapshot before a lock wait.
 * All statement-derived expense updates/reviews acquire row, then expense.
 */
function bank_expense_transaction(PDO $db,int $id,callable $action):mixed {
    if($db->inTransaction())throw new LogicException('Expense lock must be outermost');
    $q=$db->prepare('SELECT created_from_statement_row_id FROM qbook_general_expenses WHERE id=?');
    $q->execute([$id]);$hint=$q->fetch();
    if(!$hint)accounts_fail('EXPENSE_NOT_FOUND',404);
    $row=$hint['created_from_statement_row_id'];
    return bank_ownership_transaction($db,function()use($db,$id,$row,$action){
        if($row!==null){
            $q=$db->prepare('SELECT id FROM qbook_bank_statement_rows WHERE id=? FOR UPDATE');
            $q->execute([$row]);if(!$q->fetch())accounts_fail('BANK_ROW_NOT_FOUND',404);
        }
        $q=$db->prepare('SELECT created_from_statement_row_id FROM qbook_general_expenses WHERE id=? FOR UPDATE');
        $q->execute([$id]);$current=$q->fetch();
        if(!$current||(string)$current['created_from_statement_row_id']!==(string)$row)accounts_fail('EXPENSE_CHANGED_REFRESH',409);
        return $action();
    });
}
