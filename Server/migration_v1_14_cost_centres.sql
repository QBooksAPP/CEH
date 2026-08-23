-- NOT APPLIED TO PRODUCTION.
-- CEH Accounts Phase 2.2. Apply only after v1.13, a fresh backup and explicit approval.
-- Incremental only: no postings, opening balances, historical backfill, rewrite or deletes.

CREATE TABLE qbook_cost_centres (
  id BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
  code VARCHAR(60) NOT NULL,
  name VARCHAR(120) NOT NULL,
  description VARCHAR(500) NULL,
  display_order INT UNSIGNED NOT NULL DEFAULT 0,
  is_active TINYINT(1) NOT NULL DEFAULT 1,
  created_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
  updated_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
  PRIMARY KEY (id),
  UNIQUE KEY uq_cost_centre_code (code),
  UNIQUE KEY uq_cost_centre_name (name),
  KEY idx_cost_centre_active_order (is_active,display_order,name),
  CONSTRAINT chk_cost_centre_active CHECK (is_active IN (0,1))
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

INSERT INTO qbook_cost_centres(code,name,description,display_order,is_active) VALUES
  ('OFFICE','Office','Administration and office-related activity.',10,1),
  ('WORKSHOP','Workshop','Repair, maintenance, parts and workshop activity.',20,1),
  ('PROJECT_OPERATIONS','Project / Operations','Direct operational or site expenditure.',30,1);

ALTER TABLE qbook_petty_cash_expense_lines
  ADD COLUMN cost_centre_id BIGINT UNSIGNED NULL AFTER unit_price,
  ADD KEY idx_petty_line_cost_centre (cost_centre_id),
  ADD CONSTRAINT fk_petty_line_cost_centre FOREIGN KEY (cost_centre_id)
    REFERENCES qbook_cost_centres(id) ON UPDATE RESTRICT ON DELETE RESTRICT;

ALTER TABLE qbook_general_expense_lines
  ADD COLUMN cost_centre_id BIGINT UNSIGNED NULL AFTER unit_price,
  ADD KEY idx_general_line_cost_centre (cost_centre_id),
  ADD CONSTRAINT fk_general_line_cost_centre FOREIGN KEY (cost_centre_id)
    REFERENCES qbook_cost_centres(id) ON UPDATE RESTRICT ON DELETE RESTRICT;

ALTER TABLE qbook_financial_journal_lines
  ADD COLUMN cost_centre_id BIGINT UNSIGNED NULL AFTER credit,
  ADD KEY idx_financial_line_cost_centre (cost_centre_id),
  ADD CONSTRAINT fk_financial_line_cost_centre FOREIGN KEY (cost_centre_id)
    REFERENCES qbook_cost_centres(id) ON UPDATE RESTRICT ON DELETE RESTRICT;
