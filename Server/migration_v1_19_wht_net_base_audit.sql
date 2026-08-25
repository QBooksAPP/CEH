-- CEH Accounts Phase 3: correct unused Nigerian WHT configurations to the
-- VAT-exclusive invoice value and preserve suggested-versus-accepted WHT.
--
-- Authoritative basis reviewed 2026-08-25:
-- - Deduction of Tax at Source (Withholding) Regulations 2024 (gazetted)
-- - Nigeria Tax Act 2025, section 149 (VAT is added to the supply value)
--
-- Restart states deliberately supported:
-- - PRISTINE: five approved codes are GROSS and both v1.19 columns are absent.
-- - CONFIGURATION_ONLY: five approved codes are NET and both columns are absent.
-- - COMPLETE: five approved codes are NET and both columns are present.
-- Every other mixed/partial state aborts with a descriptive missing-table error.
--
-- Incremental only. No financial posting, historical snapshot rewrite,
-- backfill, deletion, truncation, cascade delete, or destructive rewrite.

SET @ceh_v119_selected_schema := DATABASE();
SET @ceh_v119_required_tables := (
  SELECT COUNT(*)
  FROM information_schema.tables
  WHERE table_schema=@ceh_v119_selected_schema
    AND table_name IN (
      'qbook_tax_codes',
      'qbook_customer_receipts',
      'qbook_customer_receipt_allocations',
      'qbook_receipt_wht',
      'qbook_customer_receipt_allocation_wht'
    )
);
SET @ceh_v119_existing_audit_columns := (
  SELECT COUNT(*)
  FROM information_schema.columns
  WHERE table_schema=@ceh_v119_selected_schema
    AND table_name='qbook_customer_receipt_allocation_wht'
    AND column_name IN ('suggested_amount','override_reason')
);

-- This guard runs before any CEH-table access or persistent write. Dynamic
-- failure statements avoid CHECK-constraint/temp-table assertion behaviour.
SET @ceh_v119_schema_guard_sql := IF(
  @ceh_v119_selected_schema IS NOT NULL
  AND LOWER(@ceh_v119_selected_schema) NOT IN
      ('information_schema','mysql','performance_schema','sys')
  AND @ceh_v119_required_tables=5
  AND @ceh_v119_existing_audit_columns IN (0,2),
  'SELECT ''v1.19 schema guard passed'' AS migration_status',
  'SELECT * FROM CEH_V119_ABORT_INVALID_SCHEMA_OR_PARTIAL_COLUMNS'
);
PREPARE ceh_v119_schema_guard FROM @ceh_v119_schema_guard_sql;
EXECUTE ceh_v119_schema_guard;
DEALLOCATE PREPARE ceh_v119_schema_guard;

SET @ceh_v119_expected_code_count := (
  SELECT COUNT(*)
  FROM qbook_tax_codes
  WHERE code IN (
    'WHT_CONSTRUCTION',
    'WHT_CONSTRUCTION_OTHER',
    'WHT_SERVICES',
    'WHT_PROFESSIONAL',
    'WHT_RENT_HIRE_LEASE'
  )
);
SET @ceh_v119_invalid_static_code_count := (
  SELECT COUNT(*)
  FROM qbook_tax_codes
  WHERE code IN (
    'WHT_CONSTRUCTION',
    'WHT_CONSTRUCTION_OTHER',
    'WHT_SERVICES',
    'WHT_PROFESSIONAL',
    'WHT_RENT_HIRE_LEASE'
  )
  AND NOT (
    tax_type='WHT'
    AND effective_from='2025-01-01'
    AND effective_to IS NULL
    AND is_active=1
    AND calculation_base IN ('GROSS','NET')
    AND account_role_code='WHT_RECEIVABLE'
    AND (
      (code='WHT_CONSTRUCTION' AND name='Construction' AND rate_percent=2.000000)
      OR (code='WHT_CONSTRUCTION_OTHER' AND name='Other Construction / Related Activities' AND rate_percent=5.000000)
      OR (code='WHT_SERVICES' AND name='General Services' AND rate_percent=2.000000)
      OR (code='WHT_PROFESSIONAL' AND name='Consultancy / Technical / Management / Professional' AND rate_percent=5.000000)
      OR (code='WHT_RENT_HIRE_LEASE' AND name='Rent / Hire / Lease' AND rate_percent=10.000000)
    )
  )
);
SET @ceh_v119_gross_code_count := (
  SELECT COUNT(*)
  FROM qbook_tax_codes
  WHERE code IN (
    'WHT_CONSTRUCTION','WHT_CONSTRUCTION_OTHER','WHT_SERVICES',
    'WHT_PROFESSIONAL','WHT_RENT_HIRE_LEASE'
  ) AND calculation_base='GROSS'
);
SET @ceh_v119_net_code_count := (
  SELECT COUNT(*)
  FROM qbook_tax_codes
  WHERE code IN (
    'WHT_CONSTRUCTION','WHT_CONSTRUCTION_OTHER','WHT_SERVICES',
    'WHT_PROFESSIONAL','WHT_RENT_HIRE_LEASE'
  ) AND calculation_base='NET'
);
SET @ceh_v119_legacy_reference_count := (
  SELECT COUNT(*)
  FROM qbook_receipt_wht w
  JOIN qbook_tax_codes t ON t.id=w.tax_code_id
  WHERE t.code IN (
    'WHT_CONSTRUCTION','WHT_CONSTRUCTION_OTHER','WHT_SERVICES',
    'WHT_PROFESSIONAL','WHT_RENT_HIRE_LEASE'
  )
);
SET @ceh_v119_allocation_reference_count := (
  SELECT COUNT(*)
  FROM qbook_customer_receipt_allocation_wht w
  JOIN qbook_tax_codes t ON t.id=w.tax_code_id
  WHERE t.code IN (
    'WHT_CONSTRUCTION','WHT_CONSTRUCTION_OTHER','WHT_SERVICES',
    'WHT_PROFESSIONAL','WHT_RENT_HIRE_LEASE'
  )
);
SET @ceh_v119_posted_wht_without_snapshot := (
  SELECT COUNT(*)
  FROM qbook_customer_receipt_allocations a
  JOIN qbook_customer_receipts r ON r.id=a.receipt_id AND r.status='POSTED'
  LEFT JOIN qbook_customer_receipt_allocation_wht aw
    ON aw.receipt_allocation_id=a.id
  LEFT JOIN qbook_receipt_wht rw ON rw.receipt_id=r.id
  WHERE a.wht_amount>0 AND aw.id IS NULL AND rw.id IS NULL
);

SET @ceh_v119_restart_state := CASE
  WHEN @ceh_v119_gross_code_count=5
       AND @ceh_v119_net_code_count=0
       AND @ceh_v119_existing_audit_columns=0 THEN 'PRISTINE'
  WHEN @ceh_v119_gross_code_count=0
       AND @ceh_v119_net_code_count=5
       AND @ceh_v119_existing_audit_columns=0 THEN 'CONFIGURATION_ONLY'
  WHEN @ceh_v119_gross_code_count=0
       AND @ceh_v119_net_code_count=5
       AND @ceh_v119_existing_audit_columns=2 THEN 'COMPLETE'
  ELSE 'INVALID_PARTIAL'
END;

SELECT @ceh_v119_expected_code_count AS expected_code_count,
       @ceh_v119_invalid_static_code_count AS invalid_static_code_count,
       @ceh_v119_gross_code_count AS gross_code_count,
       @ceh_v119_net_code_count AS net_code_count,
       @ceh_v119_existing_audit_columns AS audit_column_count,
       @ceh_v119_legacy_reference_count AS legacy_reference_count,
       @ceh_v119_allocation_reference_count AS allocation_reference_count,
       @ceh_v119_posted_wht_without_snapshot AS posted_wht_without_snapshot,
       @ceh_v119_restart_state AS restart_state;

-- All configuration/history guards pass before the first persistent write.
SET @ceh_v119_prewrite_guard_sql := IF(
  @ceh_v119_expected_code_count=5
  AND @ceh_v119_invalid_static_code_count=0
  AND @ceh_v119_restart_state IN ('PRISTINE','CONFIGURATION_ONLY','COMPLETE')
  AND (
    @ceh_v119_restart_state='COMPLETE'
    OR (
      @ceh_v119_legacy_reference_count=0
      AND @ceh_v119_allocation_reference_count=0
      AND @ceh_v119_posted_wht_without_snapshot=0
    )
  ),
  'SELECT ''v1.19 configuration/history guard passed'' AS migration_status',
  'SELECT * FROM CEH_V119_ABORT_CONFIGURATION_HISTORY_OR_PARTIAL_STATE'
);
PREPARE ceh_v119_prewrite_guard FROM @ceh_v119_prewrite_guard_sql;
EXECUTE ceh_v119_prewrite_guard;
DEALLOCATE PREPARE ceh_v119_prewrite_guard;

START TRANSACTION;

-- Run the correction only from the exact pristine state. A known
-- configuration-only restart skips this DML and continues to the column DDL.
SET @ceh_v119_update_sql := IF(
  @ceh_v119_restart_state='PRISTINE',
  'UPDATE qbook_tax_codes
     SET calculation_base=''NET''
   WHERE code IN (
     ''WHT_CONSTRUCTION'',
     ''WHT_CONSTRUCTION_OTHER'',
     ''WHT_SERVICES'',
     ''WHT_PROFESSIONAL'',
     ''WHT_RENT_HIRE_LEASE''
   )
   AND tax_type=''WHT''
   AND effective_from=''2025-01-01''
   AND effective_to IS NULL
   AND is_active=1
   AND calculation_base=''GROSS''
   AND account_role_code=''WHT_RECEIVABLE''',
  'SELECT ''v1.19 WHT configuration already NET'' AS migration_status'
);
PREPARE ceh_v119_update FROM @ceh_v119_update_sql;
EXECUTE ceh_v119_update;
DEALLOCATE PREPARE ceh_v119_update;

-- Verify actual transactional table state, not client-reported affected-row
-- metadata. Any failure stops before COMMIT so the correction rolls back.
SET @ceh_v119_verified_net_count := (
  SELECT COUNT(*)
  FROM qbook_tax_codes
  WHERE code IN (
    'WHT_CONSTRUCTION','WHT_CONSTRUCTION_OTHER','WHT_SERVICES',
    'WHT_PROFESSIONAL','WHT_RENT_HIRE_LEASE'
  )
  AND calculation_base='NET'
  AND tax_type='WHT'
  AND effective_from='2025-01-01'
  AND effective_to IS NULL
  AND is_active=1
  AND account_role_code='WHT_RECEIVABLE'
);
SET @ceh_v119_verified_gross_count := (
  SELECT COUNT(*)
  FROM qbook_tax_codes
  WHERE code IN (
    'WHT_CONSTRUCTION','WHT_CONSTRUCTION_OTHER','WHT_SERVICES',
    'WHT_PROFESSIONAL','WHT_RENT_HIRE_LEASE'
  ) AND calculation_base='GROSS'
);
SET @ceh_v119_postupdate_guard_sql := IF(
  @ceh_v119_verified_net_count=5 AND @ceh_v119_verified_gross_count=0,
  'SELECT ''v1.19 five-code NET verification passed'' AS migration_status',
  'SELECT * FROM CEH_V119_ABORT_FIVE_NET_CONFIGURATIONS_NOT_VERIFIED'
);
PREPARE ceh_v119_postupdate_guard FROM @ceh_v119_postupdate_guard_sql;
EXECUTE ceh_v119_postupdate_guard;
DEALLOCATE PREPARE ceh_v119_postupdate_guard;

COMMIT;

-- Re-read the committed configuration rather than carrying forward the
-- transaction-local verification values.
SET @ceh_v119_persisted_net_count := (
  SELECT COUNT(*)
  FROM qbook_tax_codes
  WHERE code IN (
    'WHT_CONSTRUCTION','WHT_CONSTRUCTION_OTHER','WHT_SERVICES',
    'WHT_PROFESSIONAL','WHT_RENT_HIRE_LEASE'
  )
  AND calculation_base='NET'
  AND tax_type='WHT'
  AND effective_from='2025-01-01'
  AND effective_to IS NULL
  AND is_active=1
  AND account_role_code='WHT_RECEIVABLE'
);
SET @ceh_v119_persisted_gross_count := (
  SELECT COUNT(*)
  FROM qbook_tax_codes
  WHERE code IN (
    'WHT_CONSTRUCTION','WHT_CONSTRUCTION_OTHER','WHT_SERVICES',
    'WHT_PROFESSIONAL','WHT_RENT_HIRE_LEASE'
  ) AND calculation_base='GROSS'
);

-- ALTER TABLE implicitly commits in MySQL. It is deliberately executed only
-- after the five-code state has been committed and verified. On a retry after
-- DML success/DDL failure, CONFIGURATION_ONLY skips DML and safely retries DDL.
SET @ceh_v119_alter_sql := IF(
  @ceh_v119_existing_audit_columns=0,
  'ALTER TABLE qbook_customer_receipt_allocation_wht
     ADD COLUMN suggested_amount DECIMAL(18,2) NULL
       AFTER calculation_base_amount,
     ADD COLUMN override_reason VARCHAR(500) NULL
       AFTER accepted_amount',
  'SELECT ''v1.19 audit columns already present'' AS migration_status'
);
PREPARE ceh_v119_alter FROM @ceh_v119_alter_sql;
EXECUTE ceh_v119_alter;
DEALLOCATE PREPARE ceh_v119_alter;

-- Verify both columns and their exact nullable definitions from persisted
-- information_schema metadata.
SET @ceh_v119_verified_audit_columns := (
  SELECT COUNT(*)
  FROM information_schema.columns
  WHERE table_schema=@ceh_v119_selected_schema
    AND table_name='qbook_customer_receipt_allocation_wht'
    AND (
      (column_name='suggested_amount'
       AND data_type='decimal'
       AND numeric_precision=18
       AND numeric_scale=2
       AND is_nullable='YES')
      OR
      (column_name='override_reason'
       AND data_type='varchar'
       AND character_maximum_length=500
       AND is_nullable='YES')
    )
);
SET @ceh_v119_final_guard_sql := IF(
  @ceh_v119_persisted_net_count=5
  AND @ceh_v119_persisted_gross_count=0
  AND @ceh_v119_verified_audit_columns=2,
  'SELECT ''v1.19 complete: five NET codes and two audit columns verified'' AS migration_status',
  'SELECT * FROM CEH_V119_ABORT_FINAL_PERSISTED_STATE_NOT_VERIFIED'
);
PREPARE ceh_v119_final_guard FROM @ceh_v119_final_guard_sql;
EXECUTE ceh_v119_final_guard;
DEALLOCATE PREPARE ceh_v119_final_guard;
