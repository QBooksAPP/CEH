-- CEH Accounts Phase 3.1: configurable Nigerian tax defaults only.
-- Sources verified 2026-08-23:
-- VAT: FIRS Finance Act 2019 implementation clarification (7.5% from 2020-02-01)
-- https://old.firs.gov.ng/wp-content/uploads/2021/06/CLARIFICATION-ON-THE-IMPLEMENTATION-OF-THE-VALUE-ADDED-TAX-VAT-ACT.pdf
-- WHT: Federal Republic of Nigeria Official Gazette, Deduction of Tax at Source
-- (Withholding) Regulations 2024, S.I. 34 (implementation from 2025-01-01)
-- https://fiscalreforms.ng/wp-content/uploads/2024/10/Deduction-of-Tax-at-Source-Withholding-Regulations-2024_Gazetted.pdf
-- Effective-dated configuration records; never application calculation constants.

INSERT INTO qbook_tax_codes(code,name,tax_type,rate_percent,calculation_base,account_role_code,effective_from,effective_to,is_active,created_by) VALUES('VAT_STD','Standard VAT','VAT',7.500000,'NET','OUTPUT_VAT_PAYABLE','2020-02-01',NULL,1,NULL) ON DUPLICATE KEY UPDATE code=VALUES(code);
INSERT INTO qbook_tax_codes(code,name,tax_type,rate_percent,calculation_base,account_role_code,effective_from,effective_to,is_active,created_by) VALUES('WHT_CONSTRUCTION','Construction','WHT',2.000000,'GROSS','WHT_RECEIVABLE','2025-01-01',NULL,1,NULL) ON DUPLICATE KEY UPDATE code=VALUES(code);
INSERT INTO qbook_tax_codes(code,name,tax_type,rate_percent,calculation_base,account_role_code,effective_from,effective_to,is_active,created_by) VALUES('WHT_CONSTRUCTION_OTHER','Other Construction / Related Activities','WHT',5.000000,'GROSS','WHT_RECEIVABLE','2025-01-01',NULL,1,NULL) ON DUPLICATE KEY UPDATE code=VALUES(code);
INSERT INTO qbook_tax_codes(code,name,tax_type,rate_percent,calculation_base,account_role_code,effective_from,effective_to,is_active,created_by) VALUES('WHT_SERVICES','General Services','WHT',2.000000,'GROSS','WHT_RECEIVABLE','2025-01-01',NULL,1,NULL) ON DUPLICATE KEY UPDATE code=VALUES(code);
INSERT INTO qbook_tax_codes(code,name,tax_type,rate_percent,calculation_base,account_role_code,effective_from,effective_to,is_active,created_by) VALUES('WHT_PROFESSIONAL','Consultancy / Technical / Management / Professional','WHT',5.000000,'GROSS','WHT_RECEIVABLE','2025-01-01',NULL,1,NULL) ON DUPLICATE KEY UPDATE code=VALUES(code);
INSERT INTO qbook_tax_codes(code,name,tax_type,rate_percent,calculation_base,account_role_code,effective_from,effective_to,is_active,created_by) VALUES('WHT_RENT_HIRE_LEASE','Rent / Hire / Lease','WHT',10.000000,'GROSS','WHT_RECEIVABLE','2025-01-01',NULL,1,NULL) ON DUPLICATE KEY UPDATE code=VALUES(code);
