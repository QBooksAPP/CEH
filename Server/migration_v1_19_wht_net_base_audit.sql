-- CEH Accounts Phase 3: correct unused Nigerian WHT configurations to the
-- VAT-exclusive invoice value and preserve suggested-versus-accepted WHT.
--
-- Authoritative basis reviewed 2026-08-25:
-- - Deduction of Tax at Source (Withholding) Regulations 2024 (gazetted)
-- - Nigeria Tax Act 2025, section 149 (VAT is added to the supply value)
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

-- Fail before accessing CEH tables when the selected schema is unsafe or the
-- expected v1.18 contract is incomplete.
DROP TEMPORARY TABLE IF EXISTS ceh_v119_schema_guard;
CREATE TEMPORARY TABLE ceh_v119_schema_guard (
  ok TINYINT NOT NULL,
  CONSTRAINT chk_ceh_v119_schema_guard CHECK(ok=1)
);
INSERT INTO ceh_v119_schema_guard(ok)
VALUES(IF(
  @ceh_v119_selected_schema IS NOT NULL
  AND LOWER(@ceh_v119_selected_schema) NOT IN
      ('information_schema','mysql','performance_schema','sys')
  AND @ceh_v119_required_tables=5
  AND @ceh_v119_existing_audit_columns=0,
  1,0
));
DROP TEMPORARY TABLE ceh_v119_schema_guard;

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
SET @ceh_v119_invalid_code_count := (
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
    AND calculation_base='GROSS'
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

SELECT @ceh_v119_expected_code_count AS expected_code_count,
       @ceh_v119_invalid_code_count AS invalid_code_count,
       @ceh_v119_legacy_reference_count AS legacy_reference_count,
       @ceh_v119_allocation_reference_count AS allocation_reference_count,
       @ceh_v119_posted_wht_without_snapshot AS posted_wht_without_snapshot;

-- All business/configuration/history guards must pass before the first
-- persistent write.
DROP TEMPORARY TABLE IF EXISTS ceh_v119_configuration_guard;
CREATE TEMPORARY TABLE ceh_v119_configuration_guard (
  ok TINYINT NOT NULL,
  CONSTRAINT chk_ceh_v119_configuration_guard CHECK(ok=1)
);
INSERT INTO ceh_v119_configuration_guard(ok)
VALUES(IF(
  @ceh_v119_expected_code_count=5
  AND @ceh_v119_invalid_code_count=0
  AND @ceh_v119_legacy_reference_count=0
  AND @ceh_v119_allocation_reference_count=0
  AND @ceh_v119_posted_wht_without_snapshot=0,
  1,0
));
DROP TEMPORARY TABLE ceh_v119_configuration_guard;

START TRANSACTION;

UPDATE qbook_tax_codes
SET calculation_base='NET'
WHERE code IN (
  'WHT_CONSTRUCTION',
  'WHT_CONSTRUCTION_OTHER',
  'WHT_SERVICES',
  'WHT_PROFESSIONAL',
  'WHT_RENT_HIRE_LEASE'
)
AND tax_type='WHT'
AND effective_from='2025-01-01'
AND effective_to IS NULL
AND is_active=1
AND calculation_base='GROSS'
AND account_role_code='WHT_RECEIVABLE';

SET @ceh_v119_corrected_rows := ROW_COUNT();
DROP TEMPORARY TABLE IF EXISTS ceh_v119_update_guard;
CREATE TEMPORARY TABLE ceh_v119_update_guard (
  ok TINYINT NOT NULL,
  CONSTRAINT chk_ceh_v119_update_guard CHECK(ok=1)
);
INSERT INTO ceh_v119_update_guard(ok)
VALUES(IF(@ceh_v119_corrected_rows=5,1,0));
DROP TEMPORARY TABLE ceh_v119_update_guard;
COMMIT;

ALTER TABLE qbook_customer_receipt_allocation_wht
  ADD COLUMN suggested_amount DECIMAL(18,2) NULL
    AFTER calculation_base_amount,
  ADD COLUMN override_reason VARCHAR(500) NULL
    AFTER accepted_amount;

SELECT code,name,rate_percent,calculation_base,account_role_code,
       effective_from,effective_to,is_active
FROM qbook_tax_codes
WHERE code IN (
  'WHT_CONSTRUCTION',
  'WHT_CONSTRUCTION_OTHER',
  'WHT_SERVICES',
  'WHT_PROFESSIONAL',
  'WHT_RENT_HIRE_LEASE'
)
ORDER BY code;
