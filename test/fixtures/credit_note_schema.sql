
/*!40101 SET @OLD_CHARACTER_SET_CLIENT=@@CHARACTER_SET_CLIENT */;
/*!40101 SET @OLD_CHARACTER_SET_RESULTS=@@CHARACTER_SET_RESULTS */;
/*!40101 SET @OLD_COLLATION_CONNECTION=@@COLLATION_CONNECTION */;
/*!50503 SET NAMES utf8mb4 */;
/*!40103 SET @OLD_TIME_ZONE=@@TIME_ZONE */;
/*!40103 SET TIME_ZONE='+00:00' */;
/*!40014 SET @OLD_UNIQUE_CHECKS=@@UNIQUE_CHECKS, UNIQUE_CHECKS=0 */;
/*!40014 SET @OLD_FOREIGN_KEY_CHECKS=@@FOREIGN_KEY_CHECKS, FOREIGN_KEY_CHECKS=0 */;
/*!40101 SET @OLD_SQL_MODE=@@SQL_MODE, SQL_MODE='NO_AUTO_VALUE_ON_ZERO' */;
/*!40111 SET @OLD_SQL_NOTES=@@SQL_NOTES, SQL_NOTES=0 */;
/*!40101 SET @saved_cs_client     = @@character_set_client */;
/*!50503 SET character_set_client = utf8mb4 */;
CREATE TABLE `petty_cash_batches` (
  `id` bigint unsigned NOT NULL AUTO_INCREMENT,
  `operator_user_id` bigint unsigned NOT NULL,
  `batch_date` date NOT NULL,
  `opening_cash` decimal(18,2) NOT NULL DEFAULT '0.00',
  `additional_cash` decimal(18,2) NOT NULL DEFAULT '0.00',
  `expected_closing_cash` decimal(18,2) DEFAULT NULL,
  `actual_closing_cash` decimal(18,2) DEFAULT NULL,
  `variance` decimal(18,2) DEFAULT NULL,
  `status` varchar(30) CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci NOT NULL DEFAULT 'DRAFT',
  `submitted_at` datetime DEFAULT NULL,
  `approved_by` bigint unsigned DEFAULT NULL,
  `approved_at` datetime DEFAULT NULL,
  `approval_note` text CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci,
  `created_at` timestamp NOT NULL DEFAULT CURRENT_TIMESTAMP,
  `updated_at` timestamp NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
  PRIMARY KEY (`id`),
  KEY `idx_petty_batch_operator` (`operator_user_id`),
  KEY `idx_petty_batch_date` (`batch_date`),
  KEY `idx_petty_batch_status` (`status`),
  KEY `fk_petty_batch_approver` (`approved_by`),
  CONSTRAINT `fk_petty_batch_approver` FOREIGN KEY (`approved_by`) REFERENCES `qbook_users` (`id`) ON DELETE SET NULL,
  CONSTRAINT `fk_petty_batch_operator` FOREIGN KEY (`operator_user_id`) REFERENCES `qbook_users` (`id`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;
/*!40101 SET character_set_client = @saved_cs_client */;
/*!40101 SET @saved_cs_client     = @@character_set_client */;
/*!50503 SET character_set_client = utf8mb4 */;
CREATE TABLE `petty_cash_entries` (
  `id` bigint unsigned NOT NULL AUTO_INCREMENT,
  `batch_id` bigint unsigned NOT NULL,
  `transaction_date` date NOT NULL,
  `reference_no` varchar(20) CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci DEFAULT NULL,
  `payee` varchar(190) CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci NOT NULL,
  `description` varchar(500) CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci NOT NULL,
  `amount` decimal(18,2) NOT NULL,
  `account_name` varchar(190) CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci DEFAULT NULL,
  `status` varchar(30) CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci NOT NULL DEFAULT 'DRAFT',
  `submitted_by` bigint unsigned NOT NULL,
  `approved_by` bigint unsigned DEFAULT NULL,
  `approved_at` datetime DEFAULT NULL,
  `rejection_reason` text CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci,
  `qbo_id` varchar(100) CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci DEFAULT NULL,
  `qbo_posted_at` datetime DEFAULT NULL,
  `created_at` timestamp NOT NULL DEFAULT CURRENT_TIMESTAMP,
  `updated_at` timestamp NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
  PRIMARY KEY (`id`),
  KEY `idx_petty_entry_batch` (`batch_id`),
  KEY `idx_petty_entry_status` (`status`),
  KEY `idx_petty_entry_date` (`transaction_date`),
  KEY `idx_petty_entry_reference` (`reference_no`),
  KEY `fk_petty_entry_submitter` (`submitted_by`),
  KEY `fk_petty_entry_approver` (`approved_by`),
  CONSTRAINT `fk_petty_entry_approver` FOREIGN KEY (`approved_by`) REFERENCES `qbook_users` (`id`) ON DELETE SET NULL,
  CONSTRAINT `fk_petty_entry_batch` FOREIGN KEY (`batch_id`) REFERENCES `petty_cash_batches` (`id`) ON DELETE CASCADE,
  CONSTRAINT `fk_petty_entry_submitter` FOREIGN KEY (`submitted_by`) REFERENCES `qbook_users` (`id`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;
/*!40101 SET character_set_client = @saved_cs_client */;
/*!40101 SET @saved_cs_client     = @@character_set_client */;
/*!50503 SET character_set_client = utf8mb4 */;
CREATE TABLE `qbook_accounts_chart` (
  `id` bigint unsigned NOT NULL AUTO_INCREMENT,
  `code` varchar(20) CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci NOT NULL,
  `name` varchar(150) CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci NOT NULL,
  `account_type` enum('ASSET','LIABILITY','EQUITY','INCOME','EXPENSE') CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci NOT NULL,
  `parent_id` bigint unsigned DEFAULT NULL,
  `is_postable` tinyint(1) NOT NULL DEFAULT '1',
  `is_active` tinyint(1) NOT NULL DEFAULT '1',
  `created_at` datetime NOT NULL DEFAULT CURRENT_TIMESTAMP,
  PRIMARY KEY (`id`),
  UNIQUE KEY `uq_accounts_chart_code` (`code`),
  KEY `idx_accounts_chart_parent` (`parent_id`),
  CONSTRAINT `fk_accounts_chart_parent` FOREIGN KEY (`parent_id`) REFERENCES `qbook_accounts_chart` (`id`) ON DELETE RESTRICT ON UPDATE RESTRICT
) ENGINE=InnoDB AUTO_INCREMENT=33 DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;
/*!40101 SET character_set_client = @saved_cs_client */;
/*!40101 SET @saved_cs_client     = @@character_set_client */;
/*!50503 SET character_set_client = utf8mb4 */;
CREATE TABLE `qbook_advance_applications` (
  `id` bigint unsigned NOT NULL AUTO_INCREMENT,
  `receipt_id` bigint unsigned NOT NULL,
  `invoice_id` bigint unsigned NOT NULL,
  `amount` decimal(18,2) NOT NULL,
  `journal_id` bigint unsigned DEFAULT NULL,
  `applied_by` bigint unsigned NOT NULL,
  `applied_at` datetime NOT NULL DEFAULT CURRENT_TIMESTAMP,
  PRIMARY KEY (`id`),
  UNIQUE KEY `uq_advance_receipt_invoice` (`receipt_id`,`invoice_id`),
  UNIQUE KEY `uq_advance_application_journal` (`journal_id`),
  KEY `idx_advance_invoice` (`invoice_id`),
  KEY `fk_advance_user` (`applied_by`),
  CONSTRAINT `fk_advance_invoice` FOREIGN KEY (`invoice_id`) REFERENCES `qbook_invoices` (`id`) ON DELETE RESTRICT ON UPDATE RESTRICT,
  CONSTRAINT `fk_advance_journal` FOREIGN KEY (`journal_id`) REFERENCES `qbook_financial_journals` (`id`) ON DELETE RESTRICT ON UPDATE RESTRICT,
  CONSTRAINT `fk_advance_receipt` FOREIGN KEY (`receipt_id`) REFERENCES `qbook_customer_receipts` (`id`) ON DELETE RESTRICT ON UPDATE RESTRICT,
  CONSTRAINT `fk_advance_user` FOREIGN KEY (`applied_by`) REFERENCES `qbook_users` (`id`) ON DELETE RESTRICT ON UPDATE RESTRICT
) ENGINE=InnoDB AUTO_INCREMENT=2 DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;
/*!40101 SET character_set_client = @saved_cs_client */;
/*!40101 SET @saved_cs_client     = @@character_set_client */;
/*!50503 SET character_set_client = utf8mb4 */;
CREATE TABLE `qbook_approval_log` (
  `id` bigint unsigned NOT NULL AUTO_INCREMENT,
  `source_type` varchar(40) CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci NOT NULL,
  `source_id` bigint unsigned NOT NULL,
  `action` varchar(30) CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci NOT NULL,
  `action_by` bigint unsigned DEFAULT NULL,
  `note` text CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci,
  `created_at` timestamp NOT NULL DEFAULT CURRENT_TIMESTAMP,
  PRIMARY KEY (`id`),
  KEY `idx_approval_source` (`source_type`,`source_id`),
  KEY `idx_approval_action` (`action`),
  KEY `fk_approval_user` (`action_by`),
  CONSTRAINT `fk_approval_user` FOREIGN KEY (`action_by`) REFERENCES `qbook_users` (`id`) ON DELETE SET NULL
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;
/*!40101 SET character_set_client = @saved_cs_client */;
/*!40101 SET @saved_cs_client     = @@character_set_client */;
/*!50503 SET character_set_client = utf8mb4 */;
CREATE TABLE `qbook_attachments` (
  `id` bigint unsigned NOT NULL AUTO_INCREMENT,
  `source_type` varchar(40) CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci NOT NULL,
  `source_id` bigint unsigned NOT NULL,
  `original_filename` varchar(255) CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci NOT NULL,
  `stored_filename` varchar(255) CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci NOT NULL,
  `mime_type` varchar(120) CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci DEFAULT NULL,
  `file_size` bigint unsigned DEFAULT NULL,
  `storage_path` varchar(500) CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci NOT NULL,
  `uploaded_by` bigint unsigned DEFAULT NULL,
  `created_at` timestamp NOT NULL DEFAULT CURRENT_TIMESTAMP,
  PRIMARY KEY (`id`),
  KEY `idx_attachment_source` (`source_type`,`source_id`),
  KEY `fk_attachment_uploader` (`uploaded_by`),
  CONSTRAINT `fk_attachment_uploader` FOREIGN KEY (`uploaded_by`) REFERENCES `qbook_users` (`id`) ON DELETE SET NULL
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;
/*!40101 SET character_set_client = @saved_cs_client */;
/*!40101 SET @saved_cs_client     = @@character_set_client */;
/*!50503 SET character_set_client = utf8mb4 */;
CREATE TABLE `qbook_audit_log` (
  `id` bigint unsigned NOT NULL AUTO_INCREMENT,
  `user_id` bigint unsigned DEFAULT NULL,
  `event_type` varchar(80) CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci NOT NULL,
  `source_type` varchar(40) CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci DEFAULT NULL,
  `source_id` bigint unsigned DEFAULT NULL,
  `details` json DEFAULT NULL,
  `ip_address` varchar(45) CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci DEFAULT NULL,
  `created_at` timestamp NOT NULL DEFAULT CURRENT_TIMESTAMP,
  PRIMARY KEY (`id`),
  KEY `idx_audit_user` (`user_id`),
  KEY `idx_audit_event` (`event_type`),
  KEY `idx_audit_created` (`created_at`),
  CONSTRAINT `fk_audit_user` FOREIGN KEY (`user_id`) REFERENCES `qbook_users` (`id`) ON DELETE SET NULL
) ENGINE=InnoDB AUTO_INCREMENT=113 DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;
/*!40101 SET character_set_client = @saved_cs_client */;
/*!40101 SET @saved_cs_client     = @@character_set_client */;
/*!50503 SET character_set_client = utf8mb4 */;
CREATE TABLE `qbook_auth_tokens` (
  `id` bigint unsigned NOT NULL AUTO_INCREMENT,
  `user_id` bigint unsigned NOT NULL,
  `token_hash` char(64) CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci NOT NULL,
  `expires_at` datetime NOT NULL,
  `revoked_at` datetime DEFAULT NULL,
  `created_ip` varchar(45) CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci DEFAULT NULL,
  `user_agent` varchar(255) CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci DEFAULT NULL,
  `created_at` timestamp NOT NULL DEFAULT CURRENT_TIMESTAMP,
  PRIMARY KEY (`id`),
  UNIQUE KEY `uq_auth_token_hash` (`token_hash`),
  KEY `idx_auth_user` (`user_id`),
  KEY `idx_auth_expiry` (`expires_at`),
  CONSTRAINT `fk_auth_token_user` FOREIGN KEY (`user_id`) REFERENCES `qbook_users` (`id`) ON DELETE CASCADE
) ENGINE=InnoDB AUTO_INCREMENT=20 DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;
/*!40101 SET character_set_client = @saved_cs_client */;
/*!40101 SET @saved_cs_client     = @@character_set_client */;
/*!50503 SET character_set_client = utf8mb4 */;
CREATE TABLE `qbook_bank_accounts` (
  `id` bigint unsigned NOT NULL AUTO_INCREMENT,
  `name` varchar(150) CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci NOT NULL,
  `bank_name` varchar(150) CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci NOT NULL,
  `account_reference` varchar(100) CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci DEFAULT NULL,
  `currency` char(3) CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci NOT NULL DEFAULT 'NGN',
  `ledger_account_id` bigint unsigned NOT NULL,
  `is_active` tinyint(1) NOT NULL DEFAULT '1',
  `created_by` bigint unsigned DEFAULT NULL,
  `created_at` datetime NOT NULL DEFAULT CURRENT_TIMESTAMP,
  PRIMARY KEY (`id`),
  UNIQUE KEY `uq_bank_accounts_ledger` (`ledger_account_id`),
  KEY `idx_bank_accounts_created_by` (`created_by`),
  CONSTRAINT `fk_bank_accounts_created_by` FOREIGN KEY (`created_by`) REFERENCES `qbook_users` (`id`) ON DELETE RESTRICT ON UPDATE RESTRICT,
  CONSTRAINT `fk_bank_accounts_ledger` FOREIGN KEY (`ledger_account_id`) REFERENCES `qbook_accounts_chart` (`id`) ON DELETE RESTRICT ON UPDATE RESTRICT
) ENGINE=InnoDB AUTO_INCREMENT=2 DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;
/*!40101 SET character_set_client = @saved_cs_client */;
/*!40101 SET @saved_cs_client     = @@character_set_client */;
/*!50503 SET character_set_client = utf8mb4 */;
CREATE TABLE `qbook_bank_import_batches` (
  `id` bigint unsigned NOT NULL AUTO_INCREMENT,
  `bank_account_id` bigint unsigned NOT NULL,
  `original_filename` varchar(255) CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci NOT NULL,
  `file_type` enum('CSV','XLSX') CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci NOT NULL,
  `file_sha256` char(64) CHARACTER SET ascii COLLATE ascii_bin NOT NULL,
  `statement_from` date DEFAULT NULL,
  `statement_to` date DEFAULT NULL,
  `opening_balance` decimal(18,2) DEFAULT NULL,
  `closing_balance` decimal(18,2) DEFAULT NULL,
  `imported_by` bigint unsigned NOT NULL,
  `imported_at` datetime NOT NULL DEFAULT CURRENT_TIMESTAMP,
  PRIMARY KEY (`id`),
  UNIQUE KEY `uq_bank_import_file` (`bank_account_id`,`file_sha256`),
  KEY `idx_bank_import_imported_by` (`imported_by`),
  CONSTRAINT `fk_bank_import_bank` FOREIGN KEY (`bank_account_id`) REFERENCES `qbook_bank_accounts` (`id`) ON DELETE RESTRICT ON UPDATE RESTRICT,
  CONSTRAINT `fk_bank_import_imported_by` FOREIGN KEY (`imported_by`) REFERENCES `qbook_users` (`id`) ON DELETE RESTRICT ON UPDATE RESTRICT
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;
/*!40101 SET character_set_client = @saved_cs_client */;
/*!40101 SET @saved_cs_client     = @@character_set_client */;
/*!50503 SET character_set_client = utf8mb4 */;
CREATE TABLE `qbook_bank_matches` (
  `id` bigint unsigned NOT NULL AUTO_INCREMENT,
  `statement_row_id` bigint unsigned NOT NULL,
  `source_type` varchar(60) CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci NOT NULL,
  `source_record_id` bigint unsigned NOT NULL,
  `match_method` enum('ADMIN_CONFIRMED','EXACT_REFERENCE') CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci NOT NULL DEFAULT 'ADMIN_CONFIRMED',
  `matched_by` bigint unsigned NOT NULL,
  `matched_at` datetime NOT NULL DEFAULT CURRENT_TIMESTAMP,
  PRIMARY KEY (`id`),
  UNIQUE KEY `uq_bank_match_statement_row` (`statement_row_id`),
  UNIQUE KEY `uq_bank_match_source` (`source_type`,`source_record_id`),
  KEY `idx_bank_match_user` (`matched_by`),
  CONSTRAINT `fk_bank_match_row` FOREIGN KEY (`statement_row_id`) REFERENCES `qbook_bank_statement_rows` (`id`) ON DELETE RESTRICT ON UPDATE RESTRICT,
  CONSTRAINT `fk_bank_match_user` FOREIGN KEY (`matched_by`) REFERENCES `qbook_users` (`id`) ON DELETE RESTRICT ON UPDATE RESTRICT
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;
/*!40101 SET character_set_client = @saved_cs_client */;
/*!40101 SET @saved_cs_client     = @@character_set_client */;
/*!50503 SET character_set_client = utf8mb4 */;
CREATE TABLE `qbook_bank_statement_rows` (
  `id` bigint unsigned NOT NULL AUTO_INCREMENT,
  `import_batch_id` bigint unsigned NOT NULL,
  `bank_account_id` bigint unsigned NOT NULL,
  `transaction_date` date NOT NULL,
  `amount` decimal(18,2) NOT NULL,
  `bank_reference` varchar(150) CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci DEFAULT NULL,
  `narration` varchar(500) CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci NOT NULL,
  `row_fingerprint` char(64) CHARACTER SET ascii COLLATE ascii_bin NOT NULL,
  `status` enum('UNMATCHED','POTENTIAL_MATCH','POSSIBLE_DUPLICATE','MATCHED','RECONCILED') CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci NOT NULL DEFAULT 'UNMATCHED',
  `potential_source_type` varchar(60) CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci DEFAULT NULL,
  `potential_source_id` bigint unsigned DEFAULT NULL,
  `created_at` datetime NOT NULL DEFAULT CURRENT_TIMESTAMP,
  PRIMARY KEY (`id`),
  UNIQUE KEY `uq_bank_statement_fingerprint` (`bank_account_id`,`row_fingerprint`),
  KEY `idx_bank_statement_batch` (`import_batch_id`),
  KEY `idx_bank_statement_match_state` (`bank_account_id`,`status`,`transaction_date`),
  CONSTRAINT `fk_bank_statement_bank` FOREIGN KEY (`bank_account_id`) REFERENCES `qbook_bank_accounts` (`id`) ON DELETE RESTRICT ON UPDATE RESTRICT,
  CONSTRAINT `fk_bank_statement_batch` FOREIGN KEY (`import_batch_id`) REFERENCES `qbook_bank_import_batches` (`id`) ON DELETE RESTRICT ON UPDATE RESTRICT
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;
/*!40101 SET character_set_client = @saved_cs_client */;
/*!40101 SET @saved_cs_client     = @@character_set_client */;
/*!50503 SET character_set_client = utf8mb4 */;
CREATE TABLE `qbook_calibration_results` (
  `id` bigint unsigned NOT NULL AUTO_INCREMENT,
  `calibration_id` bigint unsigned NOT NULL,
  `material` varchar(20) CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci NOT NULL,
  `gate_cm` decimal(6,3) DEFAULT NULL,
  `avg_total_weight_kg` decimal(14,6) DEFAULT NULL,
  `avg_counts` decimal(14,6) DEFAULT NULL,
  `moisture_pct` decimal(8,4) NOT NULL DEFAULT '0.0000',
  `net_dry_weight_kg` decimal(14,6) DEFAULT NULL,
  `kg_per_count` decimal(14,9) DEFAULT NULL,
  `calculated_at` datetime NOT NULL,
  PRIMARY KEY (`id`),
  UNIQUE KEY `uq_qbook_cal_result` (`calibration_id`,`material`,`gate_cm`),
  KEY `idx_qbook_result_cal` (`calibration_id`),
  CONSTRAINT `fk_qbook_result_cal` FOREIGN KEY (`calibration_id`) REFERENCES `qbook_calibrations` (`id`) ON DELETE CASCADE
) ENGINE=InnoDB AUTO_INCREMENT=474 DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;
/*!40101 SET character_set_client = @saved_cs_client */;
/*!40101 SET @saved_cs_client     = @@character_set_client */;
/*!50503 SET character_set_client = utf8mb4 */;
CREATE TABLE `qbook_calibration_revision_snapshots` (
  `id` bigint unsigned NOT NULL AUTO_INCREMENT,
  `calibration_id` bigint unsigned NOT NULL,
  `revision_no` int NOT NULL,
  `status` varchar(20) CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci NOT NULL,
  `snapshot_json` json NOT NULL,
  `reason` varchar(500) CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci DEFAULT NULL,
  `captured_by` bigint unsigned NOT NULL,
  `captured_at` datetime NOT NULL,
  PRIMARY KEY (`id`),
  UNIQUE KEY `uq_calibration_revision_snapshot` (`calibration_id`,`revision_no`),
  KEY `idx_calibration_revision_captured_by` (`captured_by`),
  CONSTRAINT `fk_calibration_revision_calibration` FOREIGN KEY (`calibration_id`) REFERENCES `qbook_calibrations` (`id`) ON DELETE RESTRICT ON UPDATE RESTRICT,
  CONSTRAINT `fk_calibration_revision_captured_by` FOREIGN KEY (`captured_by`) REFERENCES `qbook_users` (`id`) ON DELETE RESTRICT ON UPDATE RESTRICT
) ENGINE=InnoDB AUTO_INCREMENT=3 DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;
/*!40101 SET character_set_client = @saved_cs_client */;
/*!40101 SET @saved_cs_client     = @@character_set_client */;
/*!50503 SET character_set_client = utf8mb4 */;
CREATE TABLE `qbook_calibration_trials` (
  `id` bigint unsigned NOT NULL AUTO_INCREMENT,
  `calibration_id` bigint unsigned NOT NULL,
  `material` varchar(20) CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci NOT NULL,
  `gate_cm` decimal(6,3) DEFAULT NULL,
  `trial_no` tinyint unsigned NOT NULL,
  `total_weight_kg` decimal(12,4) DEFAULT NULL,
  `counts` decimal(12,4) DEFAULT NULL,
  `created_at` timestamp NOT NULL DEFAULT CURRENT_TIMESTAMP,
  `updated_at` timestamp NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
  PRIMARY KEY (`id`),
  UNIQUE KEY `uq_qbook_cal_trial` (`calibration_id`,`material`,`gate_cm`,`trial_no`),
  KEY `idx_qbook_trial_cal` (`calibration_id`),
  CONSTRAINT `fk_qbook_trial_cal` FOREIGN KEY (`calibration_id`) REFERENCES `qbook_calibrations` (`id`) ON DELETE CASCADE
) ENGINE=InnoDB AUTO_INCREMENT=387 DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;
/*!40101 SET character_set_client = @saved_cs_client */;
/*!40101 SET @saved_cs_client     = @@character_set_client */;
/*!50503 SET character_set_client = utf8mb4 */;
CREATE TABLE `qbook_calibrations` (
  `id` bigint unsigned NOT NULL AUTO_INCREMENT,
  `mixer_id` bigint unsigned NOT NULL,
  `client_id` bigint unsigned DEFAULT NULL,
  `project_id` bigint unsigned DEFAULT NULL,
  `client_name_snapshot` varchar(150) CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci DEFAULT NULL,
  `project_name_snapshot` varchar(200) CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci DEFAULT NULL,
  `stone_size` varchar(20) CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci DEFAULT NULL,
  `calibration_date` date NOT NULL,
  `calibration_notes` text CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci,
  `container_weight_kg` decimal(10,4) NOT NULL DEFAULT '0.0000',
  `stone_moisture_pct` decimal(8,4) NOT NULL DEFAULT '0.0000',
  `sand_moisture_pct` decimal(8,4) NOT NULL DEFAULT '0.0000',
  `cement_safety_factor_pct` decimal(8,4) NOT NULL DEFAULT '0.0000',
  `status` varchar(20) CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci NOT NULL DEFAULT 'DRAFT',
  `archived_at` datetime DEFAULT NULL,
  `archived_by` bigint unsigned DEFAULT NULL,
  `entered_by` bigint unsigned NOT NULL,
  `submitted_at` datetime DEFAULT NULL,
  `reviewed_by` bigint unsigned DEFAULT NULL,
  `reviewed_at` datetime DEFAULT NULL,
  `rejection_reason` text CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci,
  `revision_no` int unsigned NOT NULL DEFAULT '1',
  `created_at` timestamp NOT NULL DEFAULT CURRENT_TIMESTAMP,
  `updated_at` timestamp NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
  PRIMARY KEY (`id`),
  KEY `idx_qbook_cal_mixer` (`mixer_id`),
  KEY `idx_qbook_cal_status` (`status`),
  KEY `idx_qbook_cal_entered_by` (`entered_by`),
  KEY `idx_qbook_cal_date` (`calibration_date`),
  KEY `fk_qbook_cal_reviewed_by` (`reviewed_by`),
  KEY `idx_calibrations_job_context` (`client_id`,`project_id`,`mixer_id`,`stone_size`,`status`),
  KEY `fk_calibrations_project` (`project_id`),
  KEY `idx_calibrations_archive_context` (`archived_at`,`client_id`,`project_id`,`mixer_id`,`stone_size`,`status`),
  KEY `idx_calibrations_archived_by` (`archived_by`),
  CONSTRAINT `fk_calibrations_archived_by` FOREIGN KEY (`archived_by`) REFERENCES `qbook_users` (`id`) ON DELETE RESTRICT ON UPDATE RESTRICT,
  CONSTRAINT `fk_calibrations_client` FOREIGN KEY (`client_id`) REFERENCES `qbook_clients` (`id`) ON DELETE RESTRICT ON UPDATE RESTRICT,
  CONSTRAINT `fk_calibrations_project` FOREIGN KEY (`project_id`) REFERENCES `qbook_projects` (`id`) ON DELETE RESTRICT ON UPDATE RESTRICT,
  CONSTRAINT `fk_qbook_cal_entered_by` FOREIGN KEY (`entered_by`) REFERENCES `qbook_users` (`id`),
  CONSTRAINT `fk_qbook_cal_mixer` FOREIGN KEY (`mixer_id`) REFERENCES `qbook_mixers` (`id`),
  CONSTRAINT `fk_qbook_cal_reviewed_by` FOREIGN KEY (`reviewed_by`) REFERENCES `qbook_users` (`id`) ON DELETE SET NULL
) ENGINE=InnoDB AUTO_INCREMENT=10 DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;
/*!40101 SET character_set_client = @saved_cs_client */;
/*!40101 SET @saved_cs_client     = @@character_set_client */;
/*!50503 SET character_set_client = utf8mb4 */;
CREATE TABLE `qbook_clients` (
  `id` bigint unsigned NOT NULL AUTO_INCREMENT,
  `name` varchar(150) CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci NOT NULL,
  `is_active` tinyint(1) NOT NULL DEFAULT '1',
  `archived_at` datetime DEFAULT NULL,
  `archived_by` bigint unsigned DEFAULT NULL,
  `created_at` datetime NOT NULL DEFAULT CURRENT_TIMESTAMP,
  `updated_at` datetime NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
  PRIMARY KEY (`id`),
  UNIQUE KEY `uq_clients_name` (`name`),
  KEY `idx_clients_active_name` (`is_active`,`name`),
  KEY `idx_clients_archive_name` (`archived_at`,`name`),
  KEY `idx_clients_archived_by` (`archived_by`),
  CONSTRAINT `fk_clients_archived_by` FOREIGN KEY (`archived_by`) REFERENCES `qbook_users` (`id`) ON DELETE RESTRICT ON UPDATE RESTRICT
) ENGINE=InnoDB AUTO_INCREMENT=3 DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;
/*!40101 SET character_set_client = @saved_cs_client */;
/*!40101 SET @saved_cs_client     = @@character_set_client */;
/*!50503 SET character_set_client = utf8mb4 */;
CREATE TABLE `qbook_companies` (
  `id` bigint unsigned NOT NULL AUTO_INCREMENT,
  `company_code` varchar(30) COLLATE utf8mb4_unicode_ci NOT NULL,
  `display_name` varchar(200) COLLATE utf8mb4_unicode_ci NOT NULL,
  `is_active` tinyint(1) NOT NULL DEFAULT '1',
  `created_by` bigint unsigned DEFAULT NULL,
  `updated_by` bigint unsigned DEFAULT NULL,
  `created_at` datetime NOT NULL DEFAULT CURRENT_TIMESTAMP,
  `updated_at` datetime NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
  PRIMARY KEY (`id`),
  UNIQUE KEY `uq_company_code` (`company_code`),
  KEY `fk_company_created_by` (`created_by`),
  KEY `fk_company_updated_by` (`updated_by`),
  CONSTRAINT `fk_company_created_by` FOREIGN KEY (`created_by`) REFERENCES `qbook_users` (`id`) ON DELETE RESTRICT ON UPDATE RESTRICT,
  CONSTRAINT `fk_company_updated_by` FOREIGN KEY (`updated_by`) REFERENCES `qbook_users` (`id`) ON DELETE RESTRICT ON UPDATE RESTRICT,
  CONSTRAINT `chk_company_active` CHECK ((`is_active` in (0,1)))
) ENGINE=InnoDB AUTO_INCREMENT=1000 DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;
/*!40101 SET character_set_client = @saved_cs_client */;
/*!40101 SET @saved_cs_client     = @@character_set_client */;
/*!50503 SET character_set_client = utf8mb4 */;
CREATE TABLE `qbook_company_regional_settings` (
  `company_id` bigint unsigned NOT NULL,
  `time_zone` varchar(64) COLLATE utf8mb4_unicode_ci NOT NULL,
  `date_format` enum('DD-MM-YYYY','MM-DD-YYYY','YYYY-MM-DD') COLLATE utf8mb4_unicode_ci NOT NULL,
  `time_format` enum('24_HOUR','12_HOUR') COLLATE utf8mb4_unicode_ci NOT NULL,
  `base_currency` char(3) COLLATE utf8mb4_unicode_ci NOT NULL,
  `updated_by` bigint unsigned DEFAULT NULL,
  `updated_at` datetime NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
  PRIMARY KEY (`company_id`),
  KEY `fk_regional_updated_by` (`updated_by`),
  CONSTRAINT `fk_regional_company` FOREIGN KEY (`company_id`) REFERENCES `qbook_companies` (`id`) ON DELETE RESTRICT ON UPDATE RESTRICT,
  CONSTRAINT `fk_regional_updated_by` FOREIGN KEY (`updated_by`) REFERENCES `qbook_users` (`id`) ON DELETE RESTRICT ON UPDATE RESTRICT,
  CONSTRAINT `chk_regional_currency` CHECK ((`base_currency` in (_cp850'NGN',_cp850'GBP',_cp850'USD',_cp850'EUR',_cp850'AED')))
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;
/*!40101 SET character_set_client = @saved_cs_client */;
/*!40101 SET @saved_cs_client     = @@character_set_client */;
/*!50503 SET character_set_client = utf8mb4 */;
CREATE TABLE `qbook_company_regional_settings_audit` (
  `id` bigint unsigned NOT NULL AUTO_INCREMENT,
  `company_id` bigint unsigned NOT NULL,
  `changed_by` bigint unsigned NOT NULL,
  `changed_at` datetime NOT NULL DEFAULT CURRENT_TIMESTAMP,
  `old_time_zone` varchar(64) COLLATE utf8mb4_unicode_ci NOT NULL,
  `new_time_zone` varchar(64) COLLATE utf8mb4_unicode_ci NOT NULL,
  `old_date_format` enum('DD-MM-YYYY','MM-DD-YYYY','YYYY-MM-DD') COLLATE utf8mb4_unicode_ci NOT NULL,
  `new_date_format` enum('DD-MM-YYYY','MM-DD-YYYY','YYYY-MM-DD') COLLATE utf8mb4_unicode_ci NOT NULL,
  `old_time_format` enum('24_HOUR','12_HOUR') COLLATE utf8mb4_unicode_ci NOT NULL,
  `new_time_format` enum('24_HOUR','12_HOUR') COLLATE utf8mb4_unicode_ci NOT NULL,
  `old_base_currency` char(3) COLLATE utf8mb4_unicode_ci NOT NULL,
  `new_base_currency` char(3) COLLATE utf8mb4_unicode_ci NOT NULL,
  `change_reason` varchar(500) COLLATE utf8mb4_unicode_ci DEFAULT NULL,
  PRIMARY KEY (`id`),
  KEY `idx_regional_audit_company` (`company_id`,`changed_at`),
  KEY `idx_regional_audit_actor` (`changed_by`,`changed_at`),
  CONSTRAINT `fk_regional_audit_company` FOREIGN KEY (`company_id`) REFERENCES `qbook_companies` (`id`) ON DELETE RESTRICT ON UPDATE RESTRICT,
  CONSTRAINT `fk_regional_audit_user` FOREIGN KEY (`changed_by`) REFERENCES `qbook_users` (`id`) ON DELETE RESTRICT ON UPDATE RESTRICT,
  CONSTRAINT `chk_regional_audit_new_currency` CHECK ((`new_base_currency` in (_cp850'NGN',_cp850'GBP',_cp850'USD',_cp850'EUR',_cp850'AED'))),
  CONSTRAINT `chk_regional_audit_old_currency` CHECK ((`old_base_currency` in (_cp850'NGN',_cp850'GBP',_cp850'USD',_cp850'EUR',_cp850'AED')))
) ENGINE=InnoDB AUTO_INCREMENT=2 DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;
/*!40101 SET character_set_client = @saved_cs_client */;
/*!40101 SET @saved_cs_client     = @@character_set_client */;
/*!50503 SET character_set_client = utf8mb4 */;
CREATE TABLE `qbook_cost_centres` (
  `id` bigint unsigned NOT NULL AUTO_INCREMENT,
  `code` varchar(60) CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci NOT NULL,
  `name` varchar(120) CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci NOT NULL,
  `description` varchar(500) CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci DEFAULT NULL,
  `display_order` int unsigned NOT NULL DEFAULT '0',
  `is_active` tinyint(1) NOT NULL DEFAULT '1',
  `created_at` datetime NOT NULL DEFAULT CURRENT_TIMESTAMP,
  `updated_at` datetime NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
  PRIMARY KEY (`id`),
  UNIQUE KEY `uq_cost_centre_code` (`code`),
  UNIQUE KEY `uq_cost_centre_name` (`name`),
  KEY `idx_cost_centre_active_order` (`is_active`,`display_order`,`name`)
) ENGINE=InnoDB AUTO_INCREMENT=4 DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;
/*!40101 SET character_set_client = @saved_cs_client */;
/*!40101 SET @saved_cs_client     = @@character_set_client */;
/*!50503 SET character_set_client = utf8mb4 */;
CREATE TABLE `qbook_credit_note_allocations` (
  `id` bigint unsigned NOT NULL AUTO_INCREMENT,
  `credit_note_id` bigint unsigned NOT NULL,
  `invoice_id` bigint unsigned NOT NULL,
  `amount` decimal(18,2) NOT NULL,
  `allocated_at` datetime NOT NULL DEFAULT CURRENT_TIMESTAMP,
  PRIMARY KEY (`id`),
  UNIQUE KEY `credit_note_id` (`credit_note_id`),
  KEY `idx_credit_allocation_invoice` (`invoice_id`),
  CONSTRAINT `fk_credit_allocation_invoice` FOREIGN KEY (`invoice_id`) REFERENCES `qbook_invoices` (`id`) ON DELETE RESTRICT ON UPDATE RESTRICT,
  CONSTRAINT `fk_credit_allocation_note` FOREIGN KEY (`credit_note_id`) REFERENCES `qbook_credit_notes` (`id`) ON DELETE RESTRICT ON UPDATE RESTRICT
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;
/*!40101 SET character_set_client = @saved_cs_client */;
/*!40101 SET @saved_cs_client     = @@character_set_client */;
/*!50503 SET character_set_client = utf8mb4 */;
CREATE TABLE `qbook_credit_note_lines` (
  `id` bigint unsigned NOT NULL AUTO_INCREMENT,
  `credit_note_id` bigint unsigned NOT NULL,
  `invoice_line_id` bigint unsigned NOT NULL,
  `line_no` int unsigned NOT NULL,
  `description` varchar(500) CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci NOT NULL,
  `revenue_account_id` bigint unsigned NOT NULL,
  `net_amount` decimal(18,2) NOT NULL,
  `vat_amount` decimal(18,2) NOT NULL,
  `gross_amount` decimal(18,2) NOT NULL,
  `project_id` bigint unsigned DEFAULT NULL,
  `mixer_id` bigint unsigned DEFAULT NULL,
  PRIMARY KEY (`id`),
  UNIQUE KEY `uq_credit_line` (`credit_note_id`,`line_no`),
  KEY `idx_credit_line_invoice_line` (`invoice_line_id`),
  KEY `fk_credit_line_account` (`revenue_account_id`),
  KEY `fk_credit_line_project` (`project_id`),
  KEY `fk_credit_line_mixer` (`mixer_id`),
  CONSTRAINT `fk_credit_line_account` FOREIGN KEY (`revenue_account_id`) REFERENCES `qbook_accounts_chart` (`id`) ON DELETE RESTRICT ON UPDATE RESTRICT,
  CONSTRAINT `fk_credit_line_invoice` FOREIGN KEY (`invoice_line_id`) REFERENCES `qbook_invoice_lines` (`id`) ON DELETE RESTRICT ON UPDATE RESTRICT,
  CONSTRAINT `fk_credit_line_mixer` FOREIGN KEY (`mixer_id`) REFERENCES `qbook_mixers` (`id`) ON DELETE RESTRICT ON UPDATE RESTRICT,
  CONSTRAINT `fk_credit_line_note` FOREIGN KEY (`credit_note_id`) REFERENCES `qbook_credit_notes` (`id`) ON DELETE RESTRICT ON UPDATE RESTRICT,
  CONSTRAINT `fk_credit_line_project` FOREIGN KEY (`project_id`) REFERENCES `qbook_projects` (`id`) ON DELETE RESTRICT ON UPDATE RESTRICT
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;
/*!40101 SET character_set_client = @saved_cs_client */;
/*!40101 SET @saved_cs_client     = @@character_set_client */;
/*!50503 SET character_set_client = utf8mb4 */;
CREATE TABLE `qbook_credit_note_production_releases` (
  `id` bigint unsigned NOT NULL AUTO_INCREMENT,
  `credit_note_line_id` bigint unsigned NOT NULL,
  `invoice_production_allocation_id` bigint unsigned NOT NULL,
  `released_m3` decimal(10,2) NOT NULL,
  `created_at` datetime NOT NULL DEFAULT CURRENT_TIMESTAMP,
  PRIMARY KEY (`id`),
  UNIQUE KEY `uq_credit_release_line_allocation` (`credit_note_line_id`,`invoice_production_allocation_id`),
  KEY `idx_credit_release_allocation` (`invoice_production_allocation_id`),
  CONSTRAINT `fk_credit_release_allocation` FOREIGN KEY (`invoice_production_allocation_id`) REFERENCES `qbook_invoice_production_allocations` (`id`) ON DELETE RESTRICT ON UPDATE RESTRICT,
  CONSTRAINT `fk_credit_release_line` FOREIGN KEY (`credit_note_line_id`) REFERENCES `qbook_credit_note_lines` (`id`) ON DELETE RESTRICT ON UPDATE RESTRICT
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;
/*!40101 SET character_set_client = @saved_cs_client */;
/*!40101 SET @saved_cs_client     = @@character_set_client */;
/*!50503 SET character_set_client = utf8mb4 */;
CREATE TABLE `qbook_credit_note_references` (
  `reference_no` bigint unsigned NOT NULL AUTO_INCREMENT,
  `allocated_at` datetime NOT NULL DEFAULT CURRENT_TIMESTAMP,
  PRIMARY KEY (`reference_no`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_general_ci;
/*!40101 SET character_set_client = @saved_cs_client */;
/*!40101 SET @saved_cs_client     = @@character_set_client */;
/*!50503 SET character_set_client = utf8mb4 */;
CREATE TABLE `qbook_credit_notes` (
  `id` bigint unsigned NOT NULL AUTO_INCREMENT,
  `reference_no` bigint unsigned NOT NULL,
  `invoice_id` bigint unsigned NOT NULL,
  `credit_date` date NOT NULL,
  `reason` varchar(500) CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci NOT NULL,
  `net_amount` decimal(18,2) NOT NULL,
  `vat_amount` decimal(18,2) NOT NULL,
  `total_amount` decimal(18,2) NOT NULL,
  `status` enum('DRAFT','ISSUED') CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci NOT NULL DEFAULT 'DRAFT',
  `journal_id` bigint unsigned DEFAULT NULL,
  `created_by` bigint unsigned NOT NULL,
  `issued_by` bigint unsigned DEFAULT NULL,
  `created_at` datetime NOT NULL DEFAULT CURRENT_TIMESTAMP,
  `issued_at` datetime DEFAULT NULL,
  PRIMARY KEY (`id`),
  UNIQUE KEY `uq_credit_reference` (`reference_no`),
  UNIQUE KEY `uq_credit_journal` (`journal_id`),
  KEY `idx_credit_invoice` (`invoice_id`,`status`),
  KEY `fk_credit_creator` (`created_by`),
  KEY `fk_credit_issuer` (`issued_by`),
  CONSTRAINT `fk_credit_creator` FOREIGN KEY (`created_by`) REFERENCES `qbook_users` (`id`) ON DELETE RESTRICT ON UPDATE RESTRICT,
  CONSTRAINT `fk_credit_invoice` FOREIGN KEY (`invoice_id`) REFERENCES `qbook_invoices` (`id`) ON DELETE RESTRICT ON UPDATE RESTRICT,
  CONSTRAINT `fk_credit_issuer` FOREIGN KEY (`issued_by`) REFERENCES `qbook_users` (`id`) ON DELETE RESTRICT ON UPDATE RESTRICT,
  CONSTRAINT `fk_credit_journal` FOREIGN KEY (`journal_id`) REFERENCES `qbook_financial_journals` (`id`) ON DELETE RESTRICT ON UPDATE RESTRICT,
  CONSTRAINT `fk_credit_reference` FOREIGN KEY (`reference_no`) REFERENCES `qbook_credit_note_references` (`reference_no`) ON DELETE RESTRICT ON UPDATE RESTRICT
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;
/*!40101 SET character_set_client = @saved_cs_client */;
/*!40101 SET @saved_cs_client     = @@character_set_client */;
/*!50503 SET character_set_client = utf8mb4 */;
CREATE TABLE `qbook_customer_receipt_allocation_wht` (
  `id` bigint unsigned NOT NULL AUTO_INCREMENT,
  `receipt_allocation_id` bigint unsigned NOT NULL,
  `tax_code_id` bigint unsigned NOT NULL,
  `rate_snapshot` decimal(9,6) NOT NULL,
  `calculation_base_snapshot` enum('NET','GROSS','MANUAL') CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci NOT NULL,
  `calculation_base_amount` decimal(18,2) NOT NULL,
  `suggested_amount` decimal(18,2) DEFAULT NULL,
  `accepted_amount` decimal(18,2) NOT NULL,
  `override_reason` varchar(500) CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci DEFAULT NULL,
  `certificate_status` enum('CERTIFICATE_PENDING','CERTIFICATE_RECEIVED') CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci NOT NULL,
  `certificate_evidence_id` bigint unsigned DEFAULT NULL,
  `certificate_received_at` datetime DEFAULT NULL,
  `created_at` datetime NOT NULL DEFAULT CURRENT_TIMESTAMP,
  PRIMARY KEY (`id`),
  UNIQUE KEY `uq_receipt_allocation_wht` (`receipt_allocation_id`),
  UNIQUE KEY `uq_allocation_wht_evidence` (`certificate_evidence_id`),
  KEY `idx_allocation_wht_tax_code` (`tax_code_id`),
  KEY `idx_allocation_wht_certificate` (`certificate_status`),
  CONSTRAINT `fk_allocation_wht_allocation` FOREIGN KEY (`receipt_allocation_id`) REFERENCES `qbook_customer_receipt_allocations` (`id`) ON DELETE RESTRICT ON UPDATE RESTRICT,
  CONSTRAINT `fk_allocation_wht_evidence` FOREIGN KEY (`certificate_evidence_id`) REFERENCES `qbook_financial_evidence` (`id`) ON DELETE RESTRICT ON UPDATE RESTRICT,
  CONSTRAINT `fk_allocation_wht_tax_code` FOREIGN KEY (`tax_code_id`) REFERENCES `qbook_tax_codes` (`id`) ON DELETE RESTRICT ON UPDATE RESTRICT
) ENGINE=InnoDB AUTO_INCREMENT=2 DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;
/*!40101 SET character_set_client = @saved_cs_client */;
/*!40101 SET @saved_cs_client     = @@character_set_client */;
/*!50503 SET character_set_client = utf8mb4 */;
CREATE TABLE `qbook_customer_receipt_allocations` (
  `id` bigint unsigned NOT NULL AUTO_INCREMENT,
  `receipt_id` bigint unsigned NOT NULL,
  `invoice_id` bigint unsigned NOT NULL,
  `cash_amount` decimal(18,2) NOT NULL DEFAULT '0.00',
  `wht_amount` decimal(18,2) NOT NULL DEFAULT '0.00',
  `allocated_by` bigint unsigned NOT NULL,
  `allocated_at` datetime NOT NULL DEFAULT CURRENT_TIMESTAMP,
  PRIMARY KEY (`id`),
  UNIQUE KEY `uq_receipt_invoice` (`receipt_id`,`invoice_id`),
  KEY `idx_allocation_invoice` (`invoice_id`),
  KEY `fk_allocation_user` (`allocated_by`),
  CONSTRAINT `fk_allocation_invoice` FOREIGN KEY (`invoice_id`) REFERENCES `qbook_invoices` (`id`) ON DELETE RESTRICT ON UPDATE RESTRICT,
  CONSTRAINT `fk_allocation_receipt` FOREIGN KEY (`receipt_id`) REFERENCES `qbook_customer_receipts` (`id`) ON DELETE RESTRICT ON UPDATE RESTRICT,
  CONSTRAINT `fk_allocation_user` FOREIGN KEY (`allocated_by`) REFERENCES `qbook_users` (`id`) ON DELETE RESTRICT ON UPDATE RESTRICT
) ENGINE=InnoDB AUTO_INCREMENT=4 DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;
/*!40101 SET character_set_client = @saved_cs_client */;
/*!40101 SET @saved_cs_client     = @@character_set_client */;
/*!50503 SET character_set_client = utf8mb4 */;
CREATE TABLE `qbook_customer_receipt_references` (
  `reference_no` bigint unsigned NOT NULL AUTO_INCREMENT,
  `allocated_at` datetime NOT NULL DEFAULT CURRENT_TIMESTAMP,
  PRIMARY KEY (`reference_no`)
) ENGINE=InnoDB AUTO_INCREMENT=9 DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_general_ci;
/*!40101 SET character_set_client = @saved_cs_client */;
/*!40101 SET @saved_cs_client     = @@character_set_client */;
/*!50503 SET character_set_client = utf8mb4 */;
CREATE TABLE `qbook_customer_receipts` (
  `id` bigint unsigned NOT NULL AUTO_INCREMENT,
  `reference_no` bigint unsigned NOT NULL,
  `client_id` bigint unsigned NOT NULL,
  `client_name_snapshot` varchar(150) CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci NOT NULL,
  `bank_account_id` bigint unsigned NOT NULL,
  `receipt_date` date NOT NULL,
  `cash_amount` decimal(18,2) NOT NULL,
  `bank_reference` varchar(150) CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci DEFAULT NULL,
  `narration` varchar(500) CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci DEFAULT NULL,
  `company_legal_name_snapshot` varchar(200) CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci DEFAULT NULL,
  `company_address_snapshot` varchar(500) CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci DEFAULT NULL,
  `tax_identifier_snapshot` varchar(100) CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci DEFAULT NULL,
  `payment_bank_details_snapshot` varchar(500) CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci DEFAULT NULL,
  `received_into_snapshot` varchar(200) CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci DEFAULT NULL,
  `currency_code_snapshot` char(3) COLLATE utf8mb4_unicode_ci DEFAULT NULL,
  `pdf_template_version` varchar(30) CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci DEFAULT NULL,
  `destination` enum('TRADE_RECEIVABLES','CUSTOMER_ADVANCES') CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci NOT NULL,
  `status` enum('DRAFT','POSTED','VOID') CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci NOT NULL DEFAULT 'DRAFT',
  `journal_id` bigint unsigned DEFAULT NULL,
  `statement_row_id` bigint unsigned DEFAULT NULL,
  `created_by` bigint unsigned NOT NULL,
  `posted_by` bigint unsigned DEFAULT NULL,
  `created_at` datetime NOT NULL DEFAULT CURRENT_TIMESTAMP,
  `posted_at` datetime DEFAULT NULL,
  PRIMARY KEY (`id`),
  UNIQUE KEY `uq_receipt_reference` (`reference_no`),
  UNIQUE KEY `uq_receipt_journal` (`journal_id`),
  UNIQUE KEY `uq_receipt_statement` (`statement_row_id`),
  KEY `idx_receipt_client_date` (`client_id`,`receipt_date`),
  KEY `fk_receipt_bank` (`bank_account_id`),
  KEY `fk_receipt_creator` (`created_by`),
  KEY `fk_receipt_poster` (`posted_by`),
  CONSTRAINT `fk_receipt_bank` FOREIGN KEY (`bank_account_id`) REFERENCES `qbook_bank_accounts` (`id`) ON DELETE RESTRICT ON UPDATE RESTRICT,
  CONSTRAINT `fk_receipt_client` FOREIGN KEY (`client_id`) REFERENCES `qbook_clients` (`id`) ON DELETE RESTRICT ON UPDATE RESTRICT,
  CONSTRAINT `fk_receipt_creator` FOREIGN KEY (`created_by`) REFERENCES `qbook_users` (`id`) ON DELETE RESTRICT ON UPDATE RESTRICT,
  CONSTRAINT `fk_receipt_journal` FOREIGN KEY (`journal_id`) REFERENCES `qbook_financial_journals` (`id`) ON DELETE RESTRICT ON UPDATE RESTRICT,
  CONSTRAINT `fk_receipt_poster` FOREIGN KEY (`posted_by`) REFERENCES `qbook_users` (`id`) ON DELETE RESTRICT ON UPDATE RESTRICT,
  CONSTRAINT `fk_receipt_reference` FOREIGN KEY (`reference_no`) REFERENCES `qbook_customer_receipt_references` (`reference_no`) ON DELETE RESTRICT ON UPDATE RESTRICT,
  CONSTRAINT `fk_receipt_statement` FOREIGN KEY (`statement_row_id`) REFERENCES `qbook_bank_statement_rows` (`id`) ON DELETE RESTRICT ON UPDATE RESTRICT,
  CONSTRAINT `chk_receipt_currency_snapshot` CHECK (((`currency_code_snapshot` is null) or (`currency_code_snapshot` in (_cp850'NGN',_cp850'GBP',_cp850'USD',_cp850'EUR',_cp850'AED'))))
) ENGINE=InnoDB AUTO_INCREMENT=9 DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;
/*!40101 SET character_set_client = @saved_cs_client */;
/*!40101 SET @saved_cs_client     = @@character_set_client */;
/*!50503 SET character_set_client = utf8mb4 */;
CREATE TABLE `qbook_estimate_acceptance_evidence` (
  `id` bigint unsigned NOT NULL AUTO_INCREMENT,
  `estimate_id` bigint unsigned NOT NULL,
  `original_filename` varchar(255) CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci NOT NULL,
  `mime_type` varchar(100) CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci NOT NULL,
  `byte_size` bigint unsigned NOT NULL,
  `sha256` char(64) CHARACTER SET ascii COLLATE ascii_bin NOT NULL,
  `evidence_data` longblob NOT NULL,
  `uploaded_by` bigint unsigned NOT NULL,
  `uploaded_at` datetime NOT NULL DEFAULT CURRENT_TIMESTAMP,
  PRIMARY KEY (`id`),
  UNIQUE KEY `uq_estimate_acceptance_hash` (`estimate_id`,`sha256`),
  KEY `fk_estimate_acceptance_uploader` (`uploaded_by`),
  CONSTRAINT `fk_estimate_acceptance_estimate` FOREIGN KEY (`estimate_id`) REFERENCES `qbook_estimates` (`id`) ON DELETE RESTRICT ON UPDATE RESTRICT,
  CONSTRAINT `fk_estimate_acceptance_uploader` FOREIGN KEY (`uploaded_by`) REFERENCES `qbook_users` (`id`) ON DELETE RESTRICT ON UPDATE RESTRICT
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;
/*!40101 SET character_set_client = @saved_cs_client */;
/*!40101 SET @saved_cs_client     = @@character_set_client */;
/*!50503 SET character_set_client = utf8mb4 */;
CREATE TABLE `qbook_estimate_invoice_conversions` (
  `id` bigint unsigned NOT NULL AUTO_INCREMENT,
  `estimate_line_id` bigint unsigned NOT NULL,
  `invoice_line_id` bigint unsigned NOT NULL,
  `converted_quantity` decimal(14,4) DEFAULT NULL,
  `converted_entered_amount` decimal(18,2) NOT NULL,
  `converted_net_amount` decimal(18,2) NOT NULL,
  `status` enum('DRAFT','COMMITTED','RELEASED') CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci NOT NULL DEFAULT 'DRAFT',
  `created_by` bigint unsigned NOT NULL,
  `created_at` datetime NOT NULL DEFAULT CURRENT_TIMESTAMP,
  `committed_at` datetime DEFAULT NULL,
  `released_at` datetime DEFAULT NULL,
  PRIMARY KEY (`id`),
  UNIQUE KEY `uq_estimate_conversion_invoice_line` (`invoice_line_id`),
  KEY `idx_estimate_conversion_line_status` (`estimate_line_id`,`status`),
  KEY `fk_estimate_conversion_creator` (`created_by`),
  CONSTRAINT `fk_estimate_conversion_creator` FOREIGN KEY (`created_by`) REFERENCES `qbook_users` (`id`) ON DELETE RESTRICT ON UPDATE RESTRICT,
  CONSTRAINT `fk_estimate_conversion_invoice_line` FOREIGN KEY (`invoice_line_id`) REFERENCES `qbook_invoice_lines` (`id`) ON DELETE RESTRICT ON UPDATE RESTRICT,
  CONSTRAINT `fk_estimate_conversion_line` FOREIGN KEY (`estimate_line_id`) REFERENCES `qbook_estimate_lines` (`id`) ON DELETE RESTRICT ON UPDATE RESTRICT
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;
/*!40101 SET character_set_client = @saved_cs_client */;
/*!40101 SET @saved_cs_client     = @@character_set_client */;
/*!50503 SET character_set_client = utf8mb4 */;
CREATE TABLE `qbook_estimate_lines` (
  `id` bigint unsigned NOT NULL AUTO_INCREMENT,
  `estimate_id` bigint unsigned NOT NULL,
  `line_no` int unsigned NOT NULL,
  `description` varchar(500) CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci NOT NULL,
  `quantity` decimal(14,4) DEFAULT NULL,
  `unit_name` varchar(30) CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci DEFAULT NULL,
  `unit_price` decimal(18,2) DEFAULT NULL,
  `entered_amount` decimal(18,2) NOT NULL,
  `taxable` tinyint(1) NOT NULL DEFAULT '1',
  `net_amount` decimal(18,2) NOT NULL,
  `vat_amount` decimal(18,2) NOT NULL,
  `gross_amount` decimal(18,2) NOT NULL,
  `revenue_account_id` bigint unsigned NOT NULL,
  `project_id` bigint unsigned DEFAULT NULL,
  `project_snapshot` varchar(200) CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci DEFAULT NULL,
  `mixer_id` bigint unsigned DEFAULT NULL,
  `mixer_snapshot` varchar(200) CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci DEFAULT NULL,
  PRIMARY KEY (`id`),
  UNIQUE KEY `uq_estimate_line` (`estimate_id`,`line_no`),
  KEY `idx_estimate_line_account` (`revenue_account_id`),
  KEY `idx_estimate_line_project` (`project_id`),
  KEY `idx_estimate_line_mixer` (`mixer_id`),
  CONSTRAINT `fk_estimate_line_account` FOREIGN KEY (`revenue_account_id`) REFERENCES `qbook_accounts_chart` (`id`) ON DELETE RESTRICT ON UPDATE RESTRICT,
  CONSTRAINT `fk_estimate_line_header` FOREIGN KEY (`estimate_id`) REFERENCES `qbook_estimates` (`id`) ON DELETE RESTRICT ON UPDATE RESTRICT,
  CONSTRAINT `fk_estimate_line_mixer` FOREIGN KEY (`mixer_id`) REFERENCES `qbook_mixers` (`id`) ON DELETE RESTRICT ON UPDATE RESTRICT,
  CONSTRAINT `fk_estimate_line_project` FOREIGN KEY (`project_id`) REFERENCES `qbook_projects` (`id`) ON DELETE RESTRICT ON UPDATE RESTRICT
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;
/*!40101 SET character_set_client = @saved_cs_client */;
/*!40101 SET @saved_cs_client     = @@character_set_client */;
/*!50503 SET character_set_client = utf8mb4 */;
CREATE TABLE `qbook_estimate_references` (
  `reference_no` bigint unsigned NOT NULL AUTO_INCREMENT,
  `allocated_at` datetime NOT NULL DEFAULT CURRENT_TIMESTAMP,
  PRIMARY KEY (`reference_no`)
) ENGINE=InnoDB AUTO_INCREMENT=1000000 DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_general_ci;
/*!40101 SET character_set_client = @saved_cs_client */;
/*!40101 SET @saved_cs_client     = @@character_set_client */;
/*!50503 SET character_set_client = utf8mb4 */;
CREATE TABLE `qbook_estimates` (
  `id` bigint unsigned NOT NULL AUTO_INCREMENT,
  `reference_no` bigint unsigned NOT NULL,
  `revision_of_estimate_id` bigint unsigned DEFAULT NULL,
  `client_id` bigint unsigned NOT NULL,
  `client_name_snapshot` varchar(150) CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci NOT NULL,
  `estimate_date` date DEFAULT NULL,
  `valid_until` date DEFAULT NULL,
  `vat_mode` enum('NONE','VAT_EXCLUSIVE','VAT_INCLUSIVE') CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci NOT NULL DEFAULT 'NONE',
  `vat_tax_code_id` bigint unsigned DEFAULT NULL,
  `vat_rate_snapshot` decimal(9,6) DEFAULT NULL,
  `net_amount` decimal(18,2) DEFAULT NULL,
  `vat_amount` decimal(18,2) DEFAULT NULL,
  `total_amount` decimal(18,2) DEFAULT NULL,
  `notes` text CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci,
  `terms_snapshot` varchar(500) CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci DEFAULT NULL,
  `status` enum('DRAFT','SENT','ACCEPTED','DECLINED','EXPIRED') CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci NOT NULL DEFAULT 'DRAFT',
  `company_legal_name_snapshot` varchar(200) CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci DEFAULT NULL,
  `company_address_snapshot` varchar(500) CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci DEFAULT NULL,
  `tax_identifier_snapshot` varchar(100) CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci DEFAULT NULL,
  `payment_bank_details_snapshot` varchar(500) CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci DEFAULT NULL,
  `currency_code_snapshot` char(3) COLLATE utf8mb4_unicode_ci DEFAULT NULL,
  `pdf_template_version` varchar(30) CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci DEFAULT NULL,
  `created_by` bigint unsigned NOT NULL,
  `created_at` datetime NOT NULL DEFAULT CURRENT_TIMESTAMP,
  `updated_at` datetime NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
  `sent_by` bigint unsigned DEFAULT NULL,
  `sent_at` datetime DEFAULT NULL,
  `accepted_by` bigint unsigned DEFAULT NULL,
  `accepted_at` datetime DEFAULT NULL,
  `acceptance_note` varchar(500) CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci DEFAULT NULL,
  `declined_by` bigint unsigned DEFAULT NULL,
  `declined_at` datetime DEFAULT NULL,
  `decline_reason` varchar(500) CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci DEFAULT NULL,
  `expired_by` bigint unsigned DEFAULT NULL,
  `expired_at` datetime DEFAULT NULL,
  PRIMARY KEY (`id`),
  UNIQUE KEY `uq_estimate_reference` (`reference_no`),
  KEY `idx_estimate_client_status` (`client_id`,`status`,`estimate_date`),
  KEY `idx_estimate_revision` (`revision_of_estimate_id`),
  KEY `fk_estimate_vat_code` (`vat_tax_code_id`),
  KEY `fk_estimate_creator` (`created_by`),
  KEY `fk_estimate_sender` (`sent_by`),
  KEY `fk_estimate_accepter` (`accepted_by`),
  KEY `fk_estimate_decliner` (`declined_by`),
  KEY `fk_estimate_expirer` (`expired_by`),
  CONSTRAINT `fk_estimate_accepter` FOREIGN KEY (`accepted_by`) REFERENCES `qbook_users` (`id`) ON DELETE RESTRICT ON UPDATE RESTRICT,
  CONSTRAINT `fk_estimate_client` FOREIGN KEY (`client_id`) REFERENCES `qbook_clients` (`id`) ON DELETE RESTRICT ON UPDATE RESTRICT,
  CONSTRAINT `fk_estimate_creator` FOREIGN KEY (`created_by`) REFERENCES `qbook_users` (`id`) ON DELETE RESTRICT ON UPDATE RESTRICT,
  CONSTRAINT `fk_estimate_decliner` FOREIGN KEY (`declined_by`) REFERENCES `qbook_users` (`id`) ON DELETE RESTRICT ON UPDATE RESTRICT,
  CONSTRAINT `fk_estimate_expirer` FOREIGN KEY (`expired_by`) REFERENCES `qbook_users` (`id`) ON DELETE RESTRICT ON UPDATE RESTRICT,
  CONSTRAINT `fk_estimate_reference` FOREIGN KEY (`reference_no`) REFERENCES `qbook_estimate_references` (`reference_no`) ON DELETE RESTRICT ON UPDATE RESTRICT,
  CONSTRAINT `fk_estimate_revision` FOREIGN KEY (`revision_of_estimate_id`) REFERENCES `qbook_estimates` (`id`) ON DELETE RESTRICT ON UPDATE RESTRICT,
  CONSTRAINT `fk_estimate_sender` FOREIGN KEY (`sent_by`) REFERENCES `qbook_users` (`id`) ON DELETE RESTRICT ON UPDATE RESTRICT,
  CONSTRAINT `fk_estimate_vat_code` FOREIGN KEY (`vat_tax_code_id`) REFERENCES `qbook_tax_codes` (`id`) ON DELETE RESTRICT ON UPDATE RESTRICT,
  CONSTRAINT `chk_estimate_currency_snapshot` CHECK (((`currency_code_snapshot` is null) or (`currency_code_snapshot` in (_cp850'NGN',_cp850'GBP',_cp850'USD',_cp850'EUR',_cp850'AED'))))
) ENGINE=InnoDB AUTO_INCREMENT=3 DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;
/*!40101 SET character_set_client = @saved_cs_client */;
/*!40101 SET @saved_cs_client     = @@character_set_client */;
/*!50503 SET character_set_client = utf8mb4 */;
CREATE TABLE `qbook_financial_account_roles` (
  `role_code` varchar(50) CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci NOT NULL,
  `account_id` bigint unsigned NOT NULL,
  `is_active` tinyint(1) NOT NULL DEFAULT '1',
  `updated_by` bigint unsigned DEFAULT NULL,
  `updated_at` datetime NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
  PRIMARY KEY (`role_code`),
  KEY `idx_account_roles_account` (`account_id`),
  KEY `fk_account_roles_user` (`updated_by`),
  CONSTRAINT `fk_account_roles_account` FOREIGN KEY (`account_id`) REFERENCES `qbook_accounts_chart` (`id`) ON DELETE RESTRICT ON UPDATE RESTRICT,
  CONSTRAINT `fk_account_roles_user` FOREIGN KEY (`updated_by`) REFERENCES `qbook_users` (`id`) ON DELETE RESTRICT ON UPDATE RESTRICT
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;
/*!40101 SET character_set_client = @saved_cs_client */;
/*!40101 SET @saved_cs_client     = @@character_set_client */;
/*!50503 SET character_set_client = utf8mb4 */;
CREATE TABLE `qbook_financial_audit` (
  `id` bigint unsigned NOT NULL AUTO_INCREMENT,
  `event_type` varchar(80) CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci NOT NULL,
  `source_type` varchar(60) CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci NOT NULL,
  `source_record_id` bigint unsigned NOT NULL,
  `actor_user_id` bigint unsigned NOT NULL,
  `details_json` json DEFAULT NULL,
  `created_at` datetime NOT NULL DEFAULT CURRENT_TIMESTAMP,
  PRIMARY KEY (`id`),
  KEY `idx_financial_audit_source` (`source_type`,`source_record_id`,`created_at`),
  KEY `idx_financial_audit_actor` (`actor_user_id`,`created_at`),
  CONSTRAINT `fk_financial_audit_actor` FOREIGN KEY (`actor_user_id`) REFERENCES `qbook_users` (`id`) ON DELETE RESTRICT ON UPDATE RESTRICT
) ENGINE=InnoDB AUTO_INCREMENT=112 DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;
/*!40101 SET character_set_client = @saved_cs_client */;
/*!40101 SET @saved_cs_client     = @@character_set_client */;
/*!50503 SET character_set_client = utf8mb4 */;
CREATE TABLE `qbook_financial_evidence` (
  `id` bigint unsigned NOT NULL AUTO_INCREMENT,
  `source_type` enum('PETTY_CASH_FUNDING','PETTY_CASH_EXPENSE','GENERAL_EXPENSE','SUPPLIER_PURCHASE','PAYROLL','INVOICE','CUSTOMER_RECEIPT','WHT_CERTIFICATE','CREDIT_NOTE') CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci NOT NULL,
  `source_record_id` bigint unsigned NOT NULL,
  `original_filename` varchar(255) CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci NOT NULL,
  `mime_type` varchar(100) CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci NOT NULL,
  `byte_size` bigint unsigned NOT NULL,
  `sha256` char(64) CHARACTER SET ascii COLLATE ascii_bin NOT NULL,
  `storage_driver` enum('MYSQL_BLOB','PRIVATE_FILE','OBJECT_STORAGE') CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci NOT NULL DEFAULT 'MYSQL_BLOB',
  `storage_key` varchar(500) CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci DEFAULT NULL,
  `evidence_data` longblob,
  `uploaded_by` bigint unsigned NOT NULL,
  `uploaded_at` datetime NOT NULL DEFAULT CURRENT_TIMESTAMP,
  PRIMARY KEY (`id`),
  UNIQUE KEY `uq_financial_evidence_source_hash` (`source_type`,`source_record_id`,`sha256`),
  KEY `idx_financial_evidence_uploader` (`uploaded_by`),
  CONSTRAINT `fk_financial_evidence_uploader` FOREIGN KEY (`uploaded_by`) REFERENCES `qbook_users` (`id`) ON DELETE RESTRICT ON UPDATE RESTRICT
) ENGINE=InnoDB AUTO_INCREMENT=2 DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;
/*!40101 SET character_set_client = @saved_cs_client */;
/*!40101 SET @saved_cs_client     = @@character_set_client */;
/*!50503 SET character_set_client = utf8mb4 */;
CREATE TABLE `qbook_financial_journal_lines` (
  `id` bigint unsigned NOT NULL AUTO_INCREMENT,
  `journal_id` bigint unsigned NOT NULL,
  `line_no` int unsigned NOT NULL,
  `account_id` bigint unsigned NOT NULL,
  `description` varchar(500) CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci DEFAULT NULL,
  `debit` decimal(18,2) NOT NULL DEFAULT '0.00',
  `credit` decimal(18,2) NOT NULL DEFAULT '0.00',
  `cost_centre_id` bigint unsigned DEFAULT NULL,
  `client_id` bigint unsigned DEFAULT NULL,
  `project_id` bigint unsigned DEFAULT NULL,
  `mixer_id` bigint unsigned DEFAULT NULL,
  `custodian_user_id` bigint unsigned DEFAULT NULL,
  PRIMARY KEY (`id`),
  UNIQUE KEY `uq_financial_journal_line` (`journal_id`,`line_no`),
  KEY `idx_financial_line_account` (`account_id`),
  KEY `idx_financial_line_client` (`client_id`),
  KEY `idx_financial_line_project` (`project_id`),
  KEY `idx_financial_line_mixer` (`mixer_id`),
  KEY `idx_financial_line_custodian` (`custodian_user_id`),
  KEY `idx_financial_line_cost_centre` (`cost_centre_id`),
  CONSTRAINT `fk_financial_line_account` FOREIGN KEY (`account_id`) REFERENCES `qbook_accounts_chart` (`id`) ON DELETE RESTRICT ON UPDATE RESTRICT,
  CONSTRAINT `fk_financial_line_client` FOREIGN KEY (`client_id`) REFERENCES `qbook_clients` (`id`) ON DELETE RESTRICT ON UPDATE RESTRICT,
  CONSTRAINT `fk_financial_line_cost_centre` FOREIGN KEY (`cost_centre_id`) REFERENCES `qbook_cost_centres` (`id`) ON DELETE RESTRICT ON UPDATE RESTRICT,
  CONSTRAINT `fk_financial_line_custodian` FOREIGN KEY (`custodian_user_id`) REFERENCES `qbook_users` (`id`) ON DELETE RESTRICT ON UPDATE RESTRICT,
  CONSTRAINT `fk_financial_line_journal` FOREIGN KEY (`journal_id`) REFERENCES `qbook_financial_journals` (`id`) ON DELETE RESTRICT ON UPDATE RESTRICT,
  CONSTRAINT `fk_financial_line_mixer` FOREIGN KEY (`mixer_id`) REFERENCES `qbook_mixers` (`id`) ON DELETE RESTRICT ON UPDATE RESTRICT,
  CONSTRAINT `fk_financial_line_project` FOREIGN KEY (`project_id`) REFERENCES `qbook_projects` (`id`) ON DELETE RESTRICT ON UPDATE RESTRICT
) ENGINE=InnoDB AUTO_INCREMENT=55 DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;
/*!40101 SET character_set_client = @saved_cs_client */;
/*!40101 SET @saved_cs_client     = @@character_set_client */;
/*!50503 SET character_set_client = utf8mb4 */;
CREATE TABLE `qbook_financial_journals` (
  `id` bigint unsigned NOT NULL AUTO_INCREMENT,
  `reference_no` varchar(40) CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci NOT NULL,
  `transaction_date` date NOT NULL,
  `description` varchar(500) CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci NOT NULL,
  `source_module` varchar(60) CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci NOT NULL,
  `source_record_id` bigint unsigned NOT NULL,
  `entry_kind` enum('ORIGINAL','REVERSAL','REPLACEMENT') CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci NOT NULL DEFAULT 'ORIGINAL',
  `status` enum('POSTED','REVERSED') CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci NOT NULL DEFAULT 'POSTED',
  `reversal_of_id` bigint unsigned DEFAULT NULL,
  `created_by` bigint unsigned NOT NULL,
  `approved_by` bigint unsigned DEFAULT NULL,
  `created_at` datetime NOT NULL DEFAULT CURRENT_TIMESTAMP,
  `posted_at` datetime NOT NULL DEFAULT CURRENT_TIMESTAMP,
  `reversed_at` datetime DEFAULT NULL,
  PRIMARY KEY (`id`),
  UNIQUE KEY `uq_financial_journal_reference` (`reference_no`),
  UNIQUE KEY `uq_financial_journal_source` (`source_module`,`source_record_id`,`entry_kind`),
  UNIQUE KEY `uq_financial_journal_reversal` (`reversal_of_id`),
  KEY `idx_financial_journal_created_by` (`created_by`),
  KEY `idx_financial_journal_approved_by` (`approved_by`),
  CONSTRAINT `fk_financial_journal_approved_by` FOREIGN KEY (`approved_by`) REFERENCES `qbook_users` (`id`) ON DELETE RESTRICT ON UPDATE RESTRICT,
  CONSTRAINT `fk_financial_journal_created_by` FOREIGN KEY (`created_by`) REFERENCES `qbook_users` (`id`) ON DELETE RESTRICT ON UPDATE RESTRICT,
  CONSTRAINT `fk_financial_journal_reversal` FOREIGN KEY (`reversal_of_id`) REFERENCES `qbook_financial_journals` (`id`) ON DELETE RESTRICT ON UPDATE RESTRICT
) ENGINE=InnoDB AUTO_INCREMENT=24 DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;
/*!40101 SET character_set_client = @saved_cs_client */;
/*!40101 SET @saved_cs_client     = @@character_set_client */;
/*!50503 SET character_set_client = utf8mb4 */;
CREATE TABLE `qbook_general_expense_line_reclassifications` (
  `id` bigint unsigned NOT NULL AUTO_INCREMENT,
  `expense_id` bigint unsigned NOT NULL,
  `line_id` bigint unsigned NOT NULL,
  `version_no` int unsigned NOT NULL,
  `before_snapshot` json NOT NULL,
  `after_snapshot` json NOT NULL,
  `journal_id` bigint unsigned DEFAULT NULL,
  `reversal_journal_id` bigint unsigned DEFAULT NULL,
  `reason` varchar(500) CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci NOT NULL,
  `reclassified_by` bigint unsigned NOT NULL,
  `reclassified_at` datetime NOT NULL DEFAULT CURRENT_TIMESTAMP,
  PRIMARY KEY (`id`),
  UNIQUE KEY `uq_general_line_reclass_version` (`line_id`,`version_no`),
  UNIQUE KEY `uq_general_line_reclass_journal` (`journal_id`),
  UNIQUE KEY `uq_general_line_reclass_reversal` (`reversal_journal_id`),
  KEY `fk_general_line_reclass_expense` (`expense_id`),
  KEY `fk_general_line_reclass_actor` (`reclassified_by`),
  CONSTRAINT `fk_general_line_reclass_actor` FOREIGN KEY (`reclassified_by`) REFERENCES `qbook_users` (`id`) ON DELETE RESTRICT ON UPDATE RESTRICT,
  CONSTRAINT `fk_general_line_reclass_expense` FOREIGN KEY (`expense_id`) REFERENCES `qbook_general_expenses` (`id`) ON DELETE RESTRICT ON UPDATE RESTRICT,
  CONSTRAINT `fk_general_line_reclass_journal` FOREIGN KEY (`journal_id`) REFERENCES `qbook_financial_journals` (`id`) ON DELETE RESTRICT ON UPDATE RESTRICT,
  CONSTRAINT `fk_general_line_reclass_line` FOREIGN KEY (`line_id`) REFERENCES `qbook_general_expense_lines` (`id`) ON DELETE RESTRICT ON UPDATE RESTRICT,
  CONSTRAINT `fk_general_line_reclass_reversal` FOREIGN KEY (`reversal_journal_id`) REFERENCES `qbook_financial_journals` (`id`) ON DELETE RESTRICT ON UPDATE RESTRICT
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;
/*!40101 SET character_set_client = @saved_cs_client */;
/*!40101 SET @saved_cs_client     = @@character_set_client */;
/*!50503 SET character_set_client = utf8mb4 */;
CREATE TABLE `qbook_general_expense_lines` (
  `id` bigint unsigned NOT NULL AUTO_INCREMENT,
  `expense_id` bigint unsigned NOT NULL,
  `line_no` int unsigned NOT NULL,
  `item_description` varchar(500) CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci NOT NULL,
  `expense_account_id` bigint unsigned NOT NULL,
  `amount` decimal(18,2) NOT NULL,
  `quantity` decimal(18,4) DEFAULT NULL,
  `unit_price` decimal(18,2) DEFAULT NULL,
  `cost_centre_id` bigint unsigned DEFAULT NULL,
  `client_id` bigint unsigned DEFAULT NULL,
  `project_id` bigint unsigned DEFAULT NULL,
  `mixer_id` bigint unsigned DEFAULT NULL,
  PRIMARY KEY (`id`),
  UNIQUE KEY `uq_general_expense_line_no` (`expense_id`,`line_no`),
  KEY `idx_general_line_account` (`expense_account_id`),
  KEY `idx_general_line_client` (`client_id`),
  KEY `idx_general_line_project` (`project_id`),
  KEY `idx_general_line_mixer` (`mixer_id`),
  KEY `idx_general_line_cost_centre` (`cost_centre_id`),
  CONSTRAINT `fk_general_line_account` FOREIGN KEY (`expense_account_id`) REFERENCES `qbook_accounts_chart` (`id`) ON DELETE RESTRICT ON UPDATE RESTRICT,
  CONSTRAINT `fk_general_line_client` FOREIGN KEY (`client_id`) REFERENCES `qbook_clients` (`id`) ON DELETE RESTRICT ON UPDATE RESTRICT,
  CONSTRAINT `fk_general_line_cost_centre` FOREIGN KEY (`cost_centre_id`) REFERENCES `qbook_cost_centres` (`id`) ON DELETE RESTRICT ON UPDATE RESTRICT,
  CONSTRAINT `fk_general_line_expense` FOREIGN KEY (`expense_id`) REFERENCES `qbook_general_expenses` (`id`) ON DELETE RESTRICT ON UPDATE RESTRICT,
  CONSTRAINT `fk_general_line_mixer` FOREIGN KEY (`mixer_id`) REFERENCES `qbook_mixers` (`id`) ON DELETE RESTRICT ON UPDATE RESTRICT,
  CONSTRAINT `fk_general_line_project` FOREIGN KEY (`project_id`) REFERENCES `qbook_projects` (`id`) ON DELETE RESTRICT ON UPDATE RESTRICT
) ENGINE=InnoDB AUTO_INCREMENT=12 DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;
/*!40101 SET character_set_client = @saved_cs_client */;
/*!40101 SET @saved_cs_client     = @@character_set_client */;
/*!50503 SET character_set_client = utf8mb4 */;
CREATE TABLE `qbook_general_expense_references` (
  `reference_no` bigint unsigned NOT NULL AUTO_INCREMENT,
  `expense_id` bigint unsigned DEFAULT NULL,
  `issued_at` datetime NOT NULL DEFAULT CURRENT_TIMESTAMP,
  PRIMARY KEY (`reference_no`),
  UNIQUE KEY `uq_general_expense_reference_expense` (`expense_id`),
  CONSTRAINT `fk_general_expense_reference_expense` FOREIGN KEY (`expense_id`) REFERENCES `qbook_general_expenses` (`id`) ON DELETE SET NULL ON UPDATE RESTRICT
) ENGINE=InnoDB AUTO_INCREMENT=8 DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;
/*!40101 SET character_set_client = @saved_cs_client */;
/*!40101 SET @saved_cs_client     = @@character_set_client */;
/*!50503 SET character_set_client = utf8mb4 */;
CREATE TABLE `qbook_general_expense_refunds` (
  `id` bigint unsigned NOT NULL AUTO_INCREMENT,
  `expense_id` bigint unsigned NOT NULL,
  `statement_row_id` bigint unsigned NOT NULL,
  `amount` decimal(18,2) NOT NULL,
  `linked_by` bigint unsigned NOT NULL,
  `linked_at` datetime NOT NULL DEFAULT CURRENT_TIMESTAMP,
  PRIMARY KEY (`id`),
  UNIQUE KEY `uq_general_refund_statement` (`statement_row_id`),
  KEY `idx_general_refund_expense` (`expense_id`),
  KEY `fk_general_refund_actor` (`linked_by`),
  CONSTRAINT `fk_general_refund_actor` FOREIGN KEY (`linked_by`) REFERENCES `qbook_users` (`id`) ON DELETE RESTRICT ON UPDATE RESTRICT,
  CONSTRAINT `fk_general_refund_expense` FOREIGN KEY (`expense_id`) REFERENCES `qbook_general_expenses` (`id`) ON DELETE RESTRICT ON UPDATE RESTRICT,
  CONSTRAINT `fk_general_refund_statement` FOREIGN KEY (`statement_row_id`) REFERENCES `qbook_bank_statement_rows` (`id`) ON DELETE RESTRICT ON UPDATE RESTRICT
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;
/*!40101 SET character_set_client = @saved_cs_client */;
/*!40101 SET @saved_cs_client     = @@character_set_client */;
/*!50503 SET character_set_client = utf8mb4 */;
CREATE TABLE `qbook_general_expenses` (
  `id` bigint unsigned NOT NULL AUTO_INCREMENT,
  `bank_account_id` bigint unsigned DEFAULT NULL,
  `expense_date` date DEFAULT NULL,
  `amount` decimal(18,2) DEFAULT NULL,
  `supplier_id` bigint unsigned DEFAULT NULL,
  `supplier_name_snapshot` varchar(200) CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci DEFAULT NULL,
  `description` varchar(500) CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci DEFAULT NULL,
  `bank_reference` varchar(150) CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci DEFAULT NULL,
  `no_receipt_reason` varchar(500) CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci DEFAULT NULL,
  `status` enum('DRAFT','SUBMITTED','CORRECTION_REQUIRED','APPROVED','CANCELLED_NOT_SPENT','VOIDED') CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci NOT NULL DEFAULT 'DRAFT',
  `journal_id` bigint unsigned DEFAULT NULL,
  `reversal_journal_id` bigint unsigned DEFAULT NULL,
  `created_by` bigint unsigned NOT NULL,
  `submitted_at` datetime DEFAULT NULL,
  `reviewed_by` bigint unsigned DEFAULT NULL,
  `reviewed_at` datetime DEFAULT NULL,
  `review_reason` varchar(500) CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci DEFAULT NULL,
  `voided_by` bigint unsigned DEFAULT NULL,
  `voided_at` datetime DEFAULT NULL,
  `void_reason` varchar(500) CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci DEFAULT NULL,
  `created_from_statement_row_id` bigint unsigned DEFAULT NULL,
  `created_at` datetime NOT NULL DEFAULT CURRENT_TIMESTAMP,
  `updated_at` datetime NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
  PRIMARY KEY (`id`),
  UNIQUE KEY `uq_general_expense_journal` (`journal_id`),
  UNIQUE KEY `uq_general_expense_reversal` (`reversal_journal_id`),
  UNIQUE KEY `uq_general_expense_statement_source` (`created_from_statement_row_id`),
  KEY `idx_general_expense_status_date` (`status`,`expense_date`),
  KEY `idx_general_expense_bank_reference` (`bank_account_id`,`expense_date`,`bank_reference`,`amount`),
  KEY `fk_general_expense_supplier` (`supplier_id`),
  KEY `fk_general_expense_creator` (`created_by`),
  KEY `fk_general_expense_reviewer` (`reviewed_by`),
  KEY `fk_general_expense_voider` (`voided_by`),
  CONSTRAINT `fk_general_expense_bank` FOREIGN KEY (`bank_account_id`) REFERENCES `qbook_bank_accounts` (`id`) ON DELETE RESTRICT ON UPDATE RESTRICT,
  CONSTRAINT `fk_general_expense_creator` FOREIGN KEY (`created_by`) REFERENCES `qbook_users` (`id`) ON DELETE RESTRICT ON UPDATE RESTRICT,
  CONSTRAINT `fk_general_expense_journal` FOREIGN KEY (`journal_id`) REFERENCES `qbook_financial_journals` (`id`) ON DELETE RESTRICT ON UPDATE RESTRICT,
  CONSTRAINT `fk_general_expense_reversal` FOREIGN KEY (`reversal_journal_id`) REFERENCES `qbook_financial_journals` (`id`) ON DELETE RESTRICT ON UPDATE RESTRICT,
  CONSTRAINT `fk_general_expense_reviewer` FOREIGN KEY (`reviewed_by`) REFERENCES `qbook_users` (`id`) ON DELETE RESTRICT ON UPDATE RESTRICT,
  CONSTRAINT `fk_general_expense_statement_source` FOREIGN KEY (`created_from_statement_row_id`) REFERENCES `qbook_bank_statement_rows` (`id`) ON DELETE RESTRICT ON UPDATE RESTRICT,
  CONSTRAINT `fk_general_expense_supplier` FOREIGN KEY (`supplier_id`) REFERENCES `qbook_suppliers` (`id`) ON DELETE RESTRICT ON UPDATE RESTRICT,
  CONSTRAINT `fk_general_expense_voider` FOREIGN KEY (`voided_by`) REFERENCES `qbook_users` (`id`) ON DELETE RESTRICT ON UPDATE RESTRICT
) ENGINE=InnoDB AUTO_INCREMENT=8 DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;
/*!40101 SET character_set_client = @saved_cs_client */;
/*!40101 SET @saved_cs_client     = @@character_set_client */;
/*!50503 SET character_set_client = utf8mb4 */;
CREATE TABLE `qbook_invoice_lines` (
  `id` bigint unsigned NOT NULL AUTO_INCREMENT,
  `invoice_id` bigint unsigned NOT NULL,
  `line_no` int unsigned NOT NULL,
  `source_type` enum('PRODUCTION_REPORT','SERVICE','EQUIPMENT_HIRE','MANUAL') CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci NOT NULL,
  `description` varchar(500) CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci NOT NULL,
  `quantity` decimal(14,4) DEFAULT NULL,
  `unit_name` varchar(30) CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci DEFAULT NULL,
  `unit_price` decimal(18,2) DEFAULT NULL,
  `entered_amount` decimal(18,2) NOT NULL,
  `taxable` tinyint(1) NOT NULL DEFAULT '1',
  `net_amount` decimal(18,2) DEFAULT NULL,
  `vat_amount` decimal(18,2) DEFAULT NULL,
  `gross_amount` decimal(18,2) DEFAULT NULL,
  `revenue_account_id` bigint unsigned NOT NULL,
  `project_id` bigint unsigned DEFAULT NULL,
  `project_snapshot` varchar(200) CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci DEFAULT NULL,
  `mixer_id` bigint unsigned DEFAULT NULL,
  `mixer_snapshot` varchar(200) CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci DEFAULT NULL,
  PRIMARY KEY (`id`),
  UNIQUE KEY `uq_invoice_line` (`invoice_id`,`line_no`),
  KEY `idx_invoice_line_account` (`revenue_account_id`),
  KEY `idx_invoice_line_project` (`project_id`),
  KEY `idx_invoice_line_mixer` (`mixer_id`),
  CONSTRAINT `fk_invoice_line_account` FOREIGN KEY (`revenue_account_id`) REFERENCES `qbook_accounts_chart` (`id`) ON DELETE RESTRICT ON UPDATE RESTRICT,
  CONSTRAINT `fk_invoice_line_invoice` FOREIGN KEY (`invoice_id`) REFERENCES `qbook_invoices` (`id`) ON DELETE RESTRICT ON UPDATE RESTRICT,
  CONSTRAINT `fk_invoice_line_mixer` FOREIGN KEY (`mixer_id`) REFERENCES `qbook_mixers` (`id`) ON DELETE RESTRICT ON UPDATE RESTRICT,
  CONSTRAINT `fk_invoice_line_project` FOREIGN KEY (`project_id`) REFERENCES `qbook_projects` (`id`) ON DELETE RESTRICT ON UPDATE RESTRICT
) ENGINE=InnoDB AUTO_INCREMENT=6 DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;
/*!40101 SET character_set_client = @saved_cs_client */;
/*!40101 SET @saved_cs_client     = @@character_set_client */;
/*!50503 SET character_set_client = utf8mb4 */;
CREATE TABLE `qbook_invoice_production_allocations` (
  `id` bigint unsigned NOT NULL AUTO_INCREMENT,
  `invoice_line_id` bigint unsigned NOT NULL,
  `production_session_id` bigint unsigned NOT NULL,
  `production_report_no` bigint unsigned NOT NULL,
  `report_reference_snapshot` varchar(30) CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci NOT NULL,
  `signed_m3_snapshot` decimal(10,2) NOT NULL,
  `billed_m3` decimal(10,2) NOT NULL,
  `rate_snapshot` decimal(18,2) NOT NULL,
  `status` enum('DRAFT','COMMITTED','REVERSED') CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci NOT NULL DEFAULT 'DRAFT',
  `created_at` datetime NOT NULL DEFAULT CURRENT_TIMESTAMP,
  PRIMARY KEY (`id`),
  UNIQUE KEY `uq_invoice_line_production` (`invoice_line_id`,`production_session_id`),
  KEY `idx_production_billed` (`production_session_id`,`status`),
  KEY `fk_invoice_production_report` (`production_report_no`),
  CONSTRAINT `fk_invoice_production_line` FOREIGN KEY (`invoice_line_id`) REFERENCES `qbook_invoice_lines` (`id`) ON DELETE RESTRICT ON UPDATE RESTRICT,
  CONSTRAINT `fk_invoice_production_report` FOREIGN KEY (`production_report_no`) REFERENCES `qbook_production_reports` (`report_no`) ON DELETE RESTRICT ON UPDATE RESTRICT,
  CONSTRAINT `fk_invoice_production_session` FOREIGN KEY (`production_session_id`) REFERENCES `qbook_production_sessions` (`id`) ON DELETE RESTRICT ON UPDATE RESTRICT
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;
/*!40101 SET character_set_client = @saved_cs_client */;
/*!40101 SET @saved_cs_client     = @@character_set_client */;
/*!50503 SET character_set_client = utf8mb4 */;
CREATE TABLE `qbook_invoice_references` (
  `reference_no` bigint unsigned NOT NULL AUTO_INCREMENT,
  `allocated_at` datetime NOT NULL DEFAULT CURRENT_TIMESTAMP,
  PRIMARY KEY (`reference_no`)
) ENGINE=InnoDB AUTO_INCREMENT=6 DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_general_ci;
/*!40101 SET character_set_client = @saved_cs_client */;
/*!40101 SET @saved_cs_client     = @@character_set_client */;
/*!50503 SET character_set_client = utf8mb4 */;
CREATE TABLE `qbook_invoice_settings` (
  `id` tinyint unsigned NOT NULL,
  `company_legal_name` varchar(200) CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci DEFAULT NULL,
  `company_address` varchar(500) CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci DEFAULT NULL,
  `tax_identifier` varchar(100) CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci DEFAULT NULL,
  `payment_bank_details` varchar(500) CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci DEFAULT NULL,
  `default_terms` enum('ADVANCE_PAYMENT','DUE_ON_ISSUE','NET_DAYS','FIXED_DUE_DATE','CUSTOM') CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci NOT NULL DEFAULT 'ADVANCE_PAYMENT',
  `default_terms_text` varchar(500) CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci NOT NULL DEFAULT 'Advance Payment',
  `updated_by` bigint unsigned DEFAULT NULL,
  `updated_at` datetime NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
  PRIMARY KEY (`id`),
  KEY `fk_invoice_settings_user` (`updated_by`),
  CONSTRAINT `fk_invoice_settings_user` FOREIGN KEY (`updated_by`) REFERENCES `qbook_users` (`id`) ON DELETE RESTRICT ON UPDATE RESTRICT
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;
/*!40101 SET character_set_client = @saved_cs_client */;
/*!40101 SET @saved_cs_client     = @@character_set_client */;
/*!50503 SET character_set_client = utf8mb4 */;
CREATE TABLE `qbook_invoices` (
  `id` bigint unsigned NOT NULL AUTO_INCREMENT,
  `reference_no` bigint unsigned NOT NULL,
  `origin_estimate_id` bigint unsigned DEFAULT NULL,
  `client_id` bigint unsigned NOT NULL,
  `client_name_snapshot` varchar(150) CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci NOT NULL,
  `invoice_date` date DEFAULT NULL,
  `payment_term` enum('ADVANCE_PAYMENT','DUE_ON_ISSUE','NET_DAYS','FIXED_DUE_DATE','CUSTOM') CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci NOT NULL DEFAULT 'ADVANCE_PAYMENT',
  `terms_snapshot` varchar(500) CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci DEFAULT NULL,
  `company_legal_name_snapshot` varchar(200) CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci DEFAULT NULL,
  `company_address_snapshot` varchar(500) CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci DEFAULT NULL,
  `tax_identifier_snapshot` varchar(100) CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci DEFAULT NULL,
  `payment_bank_details_snapshot` varchar(500) CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci DEFAULT NULL,
  `currency_code_snapshot` char(3) COLLATE utf8mb4_unicode_ci DEFAULT NULL,
  `due_date` date DEFAULT NULL,
  `vat_mode` enum('NONE','VAT_EXCLUSIVE','VAT_INCLUSIVE') CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci NOT NULL DEFAULT 'NONE',
  `vat_tax_code_id` bigint unsigned DEFAULT NULL,
  `vat_rate_snapshot` decimal(9,6) DEFAULT NULL,
  `net_amount` decimal(18,2) DEFAULT NULL,
  `vat_amount` decimal(18,2) DEFAULT NULL,
  `total_amount` decimal(18,2) DEFAULT NULL,
  `status` enum('DRAFT','ISSUED','VOID') CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci NOT NULL DEFAULT 'DRAFT',
  `journal_id` bigint unsigned DEFAULT NULL,
  `notes` text CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci,
  `issued_at` datetime DEFAULT NULL,
  `issued_by` bigint unsigned DEFAULT NULL,
  `voided_at` datetime DEFAULT NULL,
  `voided_by` bigint unsigned DEFAULT NULL,
  `void_reason` varchar(500) CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci DEFAULT NULL,
  `created_by` bigint unsigned NOT NULL,
  `created_at` datetime NOT NULL DEFAULT CURRENT_TIMESTAMP,
  `updated_at` datetime NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
  PRIMARY KEY (`id`),
  UNIQUE KEY `uq_invoice_reference` (`reference_no`),
  UNIQUE KEY `uq_invoice_journal` (`journal_id`),
  KEY `idx_invoice_client_status` (`client_id`,`status`,`invoice_date`),
  KEY `idx_invoice_due` (`status`,`due_date`),
  KEY `fk_invoice_vat_code` (`vat_tax_code_id`),
  KEY `fk_invoice_creator` (`created_by`),
  KEY `fk_invoice_issuer` (`issued_by`),
  KEY `fk_invoice_voider` (`voided_by`),
  KEY `idx_invoice_origin_estimate` (`origin_estimate_id`),
  CONSTRAINT `fk_invoice_client` FOREIGN KEY (`client_id`) REFERENCES `qbook_clients` (`id`) ON DELETE RESTRICT ON UPDATE RESTRICT,
  CONSTRAINT `fk_invoice_creator` FOREIGN KEY (`created_by`) REFERENCES `qbook_users` (`id`) ON DELETE RESTRICT ON UPDATE RESTRICT,
  CONSTRAINT `fk_invoice_issuer` FOREIGN KEY (`issued_by`) REFERENCES `qbook_users` (`id`) ON DELETE RESTRICT ON UPDATE RESTRICT,
  CONSTRAINT `fk_invoice_journal` FOREIGN KEY (`journal_id`) REFERENCES `qbook_financial_journals` (`id`) ON DELETE RESTRICT ON UPDATE RESTRICT,
  CONSTRAINT `fk_invoice_origin_estimate` FOREIGN KEY (`origin_estimate_id`) REFERENCES `qbook_estimates` (`id`) ON DELETE RESTRICT ON UPDATE RESTRICT,
  CONSTRAINT `fk_invoice_reference` FOREIGN KEY (`reference_no`) REFERENCES `qbook_invoice_references` (`reference_no`) ON DELETE RESTRICT ON UPDATE RESTRICT,
  CONSTRAINT `fk_invoice_vat_code` FOREIGN KEY (`vat_tax_code_id`) REFERENCES `qbook_tax_codes` (`id`) ON DELETE RESTRICT ON UPDATE RESTRICT,
  CONSTRAINT `fk_invoice_voider` FOREIGN KEY (`voided_by`) REFERENCES `qbook_users` (`id`) ON DELETE RESTRICT ON UPDATE RESTRICT,
  CONSTRAINT `chk_invoice_currency_snapshot` CHECK (((`currency_code_snapshot` is null) or (`currency_code_snapshot` in (_cp850'NGN',_cp850'GBP',_cp850'USD',_cp850'EUR',_cp850'AED'))))
) ENGINE=InnoDB AUTO_INCREMENT=6 DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;
/*!40101 SET character_set_client = @saved_cs_client */;
/*!40101 SET @saved_cs_client     = @@character_set_client */;
/*!50503 SET character_set_client = utf8mb4 */;
CREATE TABLE `qbook_mix_admixtures` (
  `id` bigint unsigned NOT NULL AUTO_INCREMENT,
  `mix_design_id` bigint unsigned NOT NULL,
  `sort_order` int unsigned NOT NULL DEFAULT '1',
  `name` varchar(120) CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci NOT NULL,
  `dosage_cc_per_100kg` decimal(14,6) NOT NULL DEFAULT '0.000000',
  `dilution_factor` decimal(14,6) NOT NULL DEFAULT '1.000000',
  `is_active` tinyint(1) NOT NULL DEFAULT '1',
  `created_at` timestamp NOT NULL DEFAULT CURRENT_TIMESTAMP,
  `updated_at` timestamp NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
  PRIMARY KEY (`id`),
  KEY `idx_qbook_admix_mix` (`mix_design_id`),
  CONSTRAINT `fk_qbook_admix_mix` FOREIGN KEY (`mix_design_id`) REFERENCES `qbook_mix_designs` (`id`) ON DELETE CASCADE
) ENGINE=InnoDB AUTO_INCREMENT=5 DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;
/*!40101 SET character_set_client = @saved_cs_client */;
/*!40101 SET @saved_cs_client     = @@character_set_client */;
/*!50503 SET character_set_client = utf8mb4 */;
CREATE TABLE `qbook_mix_designs` (
  `id` bigint unsigned NOT NULL AUTO_INCREMENT,
  `name` varchar(120) CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci NOT NULL,
  `description` text CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci,
  `design_mode` varchar(20) CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci NOT NULL DEFAULT 'CLIENT',
  `client_id` bigint unsigned DEFAULT NULL,
  `project_id` bigint unsigned DEFAULT NULL,
  `stone_size` varchar(20) CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci DEFAULT NULL,
  `client_validation_status` varchar(24) CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci DEFAULT NULL,
  `client_validated_by` bigint unsigned DEFAULT NULL,
  `client_validated_at` datetime DEFAULT NULL,
  `client_name` varchar(150) CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci DEFAULT NULL,
  `project_name` varchar(150) CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci DEFAULT NULL,
  `cement_kg` decimal(12,4) NOT NULL,
  `granite_kg` decimal(12,4) NOT NULL,
  `water_l` decimal(12,4) NOT NULL,
  `sand_kg` decimal(12,4) NOT NULL,
  `air_pct` decimal(8,5) NOT NULL DEFAULT '0.00000',
  `cement_sg` decimal(8,4) NOT NULL DEFAULT '3.1500',
  `sand_sg` decimal(8,4) NOT NULL DEFAULT '2.6000',
  `granite_sg` decimal(8,4) NOT NULL DEFAULT '2.7000',
  `batch_volume_m3` decimal(8,4) NOT NULL DEFAULT '1.0000',
  `is_active` tinyint(1) NOT NULL DEFAULT '1',
  `archived_at` datetime DEFAULT NULL,
  `archived_by` bigint unsigned DEFAULT NULL,
  `version_no` int unsigned NOT NULL DEFAULT '1',
  `created_by` bigint unsigned NOT NULL,
  `updated_by` bigint unsigned NOT NULL,
  `created_at` timestamp NOT NULL DEFAULT CURRENT_TIMESTAMP,
  `updated_at` timestamp NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
  PRIMARY KEY (`id`),
  KEY `idx_qbook_mix_active` (`is_active`),
  KEY `fk_qbook_mix_created_by` (`created_by`),
  KEY `fk_qbook_mix_updated_by` (`updated_by`),
  KEY `idx_mix_designs_job_context` (`client_id`,`project_id`,`stone_size`,`is_active`),
  KEY `idx_mix_designs_validated_by` (`client_validated_by`),
  KEY `fk_mix_designs_project` (`project_id`),
  KEY `idx_mix_designs_archive_context` (`archived_at`,`client_id`,`project_id`,`stone_size`,`is_active`),
  KEY `idx_mix_designs_archived_by` (`archived_by`),
  CONSTRAINT `fk_mix_designs_archived_by` FOREIGN KEY (`archived_by`) REFERENCES `qbook_users` (`id`) ON DELETE RESTRICT ON UPDATE RESTRICT,
  CONSTRAINT `fk_mix_designs_client` FOREIGN KEY (`client_id`) REFERENCES `qbook_clients` (`id`) ON DELETE RESTRICT ON UPDATE RESTRICT,
  CONSTRAINT `fk_mix_designs_project` FOREIGN KEY (`project_id`) REFERENCES `qbook_projects` (`id`) ON DELETE RESTRICT ON UPDATE RESTRICT,
  CONSTRAINT `fk_mix_designs_validated_by` FOREIGN KEY (`client_validated_by`) REFERENCES `qbook_users` (`id`) ON DELETE RESTRICT ON UPDATE RESTRICT,
  CONSTRAINT `fk_qbook_mix_created_by` FOREIGN KEY (`created_by`) REFERENCES `qbook_users` (`id`),
  CONSTRAINT `fk_qbook_mix_updated_by` FOREIGN KEY (`updated_by`) REFERENCES `qbook_users` (`id`)
) ENGINE=InnoDB AUTO_INCREMENT=11 DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;
/*!40101 SET character_set_client = @saved_cs_client */;
/*!40101 SET @saved_cs_client     = @@character_set_client */;
/*!50503 SET character_set_client = utf8mb4 */;
CREATE TABLE `qbook_mixers` (
  `id` bigint unsigned NOT NULL AUTO_INCREMENT,
  `code` varchar(50) CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci NOT NULL,
  `name` varchar(120) CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci NOT NULL,
  `model` varchar(100) CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci DEFAULT NULL,
  `truck_number` varchar(100) CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci DEFAULT NULL,
  `notes` text CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci,
  `is_active` tinyint(1) NOT NULL DEFAULT '1',
  `created_by` bigint unsigned DEFAULT NULL,
  `created_at` timestamp NOT NULL DEFAULT CURRENT_TIMESTAMP,
  `updated_at` timestamp NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
  PRIMARY KEY (`id`),
  UNIQUE KEY `uq_qbook_mixer_code` (`code`),
  KEY `idx_qbook_mixer_active` (`is_active`),
  KEY `fk_qbook_mixer_created_by` (`created_by`),
  CONSTRAINT `fk_qbook_mixer_created_by` FOREIGN KEY (`created_by`) REFERENCES `qbook_users` (`id`) ON DELETE SET NULL
) ENGINE=InnoDB AUTO_INCREMENT=7 DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;
/*!40101 SET character_set_client = @saved_cs_client */;
/*!40101 SET @saved_cs_client     = @@character_set_client */;
/*!50503 SET character_set_client = utf8mb4 */;
CREATE TABLE `qbook_petty_cash_custodians` (
  `id` bigint unsigned NOT NULL AUTO_INCREMENT,
  `user_id` bigint unsigned NOT NULL,
  `is_active` tinyint(1) NOT NULL DEFAULT '1',
  `designated_by` bigint unsigned NOT NULL,
  `designated_at` datetime NOT NULL DEFAULT CURRENT_TIMESTAMP,
  `updated_by` bigint unsigned NOT NULL,
  `updated_at` datetime NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
  PRIMARY KEY (`id`),
  UNIQUE KEY `uq_petty_custodian_user` (`user_id`),
  KEY `idx_petty_custodian_designated_by` (`designated_by`),
  KEY `idx_petty_custodian_updated_by` (`updated_by`),
  CONSTRAINT `fk_petty_custodian_designated_by` FOREIGN KEY (`designated_by`) REFERENCES `qbook_users` (`id`) ON DELETE RESTRICT ON UPDATE RESTRICT,
  CONSTRAINT `fk_petty_custodian_updated_by` FOREIGN KEY (`updated_by`) REFERENCES `qbook_users` (`id`) ON DELETE RESTRICT ON UPDATE RESTRICT,
  CONSTRAINT `fk_petty_custodian_user` FOREIGN KEY (`user_id`) REFERENCES `qbook_users` (`id`) ON DELETE RESTRICT ON UPDATE RESTRICT
) ENGINE=InnoDB AUTO_INCREMENT=2 DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;
/*!40101 SET character_set_client = @saved_cs_client */;
/*!40101 SET @saved_cs_client     = @@character_set_client */;
/*!50503 SET character_set_client = utf8mb4 */;
CREATE TABLE `qbook_petty_cash_expense_lines` (
  `id` bigint unsigned NOT NULL AUTO_INCREMENT,
  `expense_id` bigint unsigned NOT NULL,
  `line_no` int unsigned NOT NULL,
  `item_description` varchar(500) CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci NOT NULL,
  `expense_account_id` bigint unsigned NOT NULL,
  `amount` decimal(18,2) NOT NULL,
  `quantity` decimal(18,4) DEFAULT NULL,
  `unit_price` decimal(18,2) DEFAULT NULL,
  `cost_centre_id` bigint unsigned DEFAULT NULL,
  `client_id` bigint unsigned DEFAULT NULL,
  `project_id` bigint unsigned DEFAULT NULL,
  `mixer_id` bigint unsigned DEFAULT NULL,
  PRIMARY KEY (`id`),
  UNIQUE KEY `uq_petty_expense_line_no` (`expense_id`,`line_no`),
  KEY `idx_petty_line_account` (`expense_account_id`),
  KEY `idx_petty_line_client` (`client_id`),
  KEY `idx_petty_line_project` (`project_id`),
  KEY `idx_petty_line_mixer` (`mixer_id`),
  KEY `idx_petty_line_cost_centre` (`cost_centre_id`),
  CONSTRAINT `fk_petty_line_account` FOREIGN KEY (`expense_account_id`) REFERENCES `qbook_accounts_chart` (`id`) ON DELETE RESTRICT ON UPDATE RESTRICT,
  CONSTRAINT `fk_petty_line_client` FOREIGN KEY (`client_id`) REFERENCES `qbook_clients` (`id`) ON DELETE RESTRICT ON UPDATE RESTRICT,
  CONSTRAINT `fk_petty_line_cost_centre` FOREIGN KEY (`cost_centre_id`) REFERENCES `qbook_cost_centres` (`id`) ON DELETE RESTRICT ON UPDATE RESTRICT,
  CONSTRAINT `fk_petty_line_expense` FOREIGN KEY (`expense_id`) REFERENCES `qbook_petty_cash_expenses` (`id`) ON DELETE RESTRICT ON UPDATE RESTRICT,
  CONSTRAINT `fk_petty_line_mixer` FOREIGN KEY (`mixer_id`) REFERENCES `qbook_mixers` (`id`) ON DELETE RESTRICT ON UPDATE RESTRICT,
  CONSTRAINT `fk_petty_line_project` FOREIGN KEY (`project_id`) REFERENCES `qbook_projects` (`id`) ON DELETE RESTRICT ON UPDATE RESTRICT
) ENGINE=InnoDB AUTO_INCREMENT=9 DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;
/*!40101 SET character_set_client = @saved_cs_client */;
/*!40101 SET @saved_cs_client     = @@character_set_client */;
/*!50503 SET character_set_client = utf8mb4 */;
CREATE TABLE `qbook_petty_cash_expense_reclassifications` (
  `id` bigint unsigned NOT NULL AUTO_INCREMENT,
  `expense_id` bigint unsigned NOT NULL,
  `prior_expense_account_id` bigint unsigned NOT NULL,
  `new_expense_account_id` bigint unsigned NOT NULL,
  `prior_supplier_paid_to` varchar(200) CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci NOT NULL,
  `new_supplier_paid_to` varchar(200) CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci NOT NULL,
  `prior_description` varchar(500) CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci NOT NULL,
  `new_description` varchar(500) CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci NOT NULL,
  `prior_client_id` bigint unsigned DEFAULT NULL,
  `new_client_id` bigint unsigned DEFAULT NULL,
  `prior_project_id` bigint unsigned DEFAULT NULL,
  `new_project_id` bigint unsigned DEFAULT NULL,
  `prior_mixer_id` bigint unsigned DEFAULT NULL,
  `new_mixer_id` bigint unsigned DEFAULT NULL,
  `journal_id` bigint unsigned DEFAULT NULL,
  `reversal_journal_id` bigint unsigned DEFAULT NULL,
  `reason` varchar(500) CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci NOT NULL,
  `reclassified_by` bigint unsigned NOT NULL,
  `reclassified_at` datetime NOT NULL DEFAULT CURRENT_TIMESTAMP,
  PRIMARY KEY (`id`),
  UNIQUE KEY `uq_petty_expense_reclassification_journal` (`journal_id`),
  UNIQUE KEY `uq_petty_expense_reclassification_reversal` (`reversal_journal_id`),
  KEY `idx_petty_expense_reclassification_expense` (`expense_id`,`id`),
  KEY `idx_petty_expense_reclassification_actor` (`reclassified_by`),
  KEY `fk_petty_expense_reclassification_prior_account` (`prior_expense_account_id`),
  KEY `fk_petty_expense_reclassification_new_account` (`new_expense_account_id`),
  KEY `fk_petty_expense_reclassification_prior_client` (`prior_client_id`),
  KEY `fk_petty_expense_reclassification_new_client` (`new_client_id`),
  KEY `fk_petty_expense_reclassification_prior_project` (`prior_project_id`),
  KEY `fk_petty_expense_reclassification_new_project` (`new_project_id`),
  KEY `fk_petty_expense_reclassification_prior_mixer` (`prior_mixer_id`),
  KEY `fk_petty_expense_reclassification_new_mixer` (`new_mixer_id`),
  CONSTRAINT `fk_petty_expense_reclassification_actor` FOREIGN KEY (`reclassified_by`) REFERENCES `qbook_users` (`id`) ON DELETE RESTRICT ON UPDATE RESTRICT,
  CONSTRAINT `fk_petty_expense_reclassification_expense` FOREIGN KEY (`expense_id`) REFERENCES `qbook_petty_cash_expenses` (`id`) ON DELETE RESTRICT ON UPDATE RESTRICT,
  CONSTRAINT `fk_petty_expense_reclassification_journal` FOREIGN KEY (`journal_id`) REFERENCES `qbook_financial_journals` (`id`) ON DELETE RESTRICT ON UPDATE RESTRICT,
  CONSTRAINT `fk_petty_expense_reclassification_new_account` FOREIGN KEY (`new_expense_account_id`) REFERENCES `qbook_accounts_chart` (`id`) ON DELETE RESTRICT ON UPDATE RESTRICT,
  CONSTRAINT `fk_petty_expense_reclassification_new_client` FOREIGN KEY (`new_client_id`) REFERENCES `qbook_clients` (`id`) ON DELETE RESTRICT ON UPDATE RESTRICT,
  CONSTRAINT `fk_petty_expense_reclassification_new_mixer` FOREIGN KEY (`new_mixer_id`) REFERENCES `qbook_mixers` (`id`) ON DELETE RESTRICT ON UPDATE RESTRICT,
  CONSTRAINT `fk_petty_expense_reclassification_new_project` FOREIGN KEY (`new_project_id`) REFERENCES `qbook_projects` (`id`) ON DELETE RESTRICT ON UPDATE RESTRICT,
  CONSTRAINT `fk_petty_expense_reclassification_prior_account` FOREIGN KEY (`prior_expense_account_id`) REFERENCES `qbook_accounts_chart` (`id`) ON DELETE RESTRICT ON UPDATE RESTRICT,
  CONSTRAINT `fk_petty_expense_reclassification_prior_client` FOREIGN KEY (`prior_client_id`) REFERENCES `qbook_clients` (`id`) ON DELETE RESTRICT ON UPDATE RESTRICT,
  CONSTRAINT `fk_petty_expense_reclassification_prior_mixer` FOREIGN KEY (`prior_mixer_id`) REFERENCES `qbook_mixers` (`id`) ON DELETE RESTRICT ON UPDATE RESTRICT,
  CONSTRAINT `fk_petty_expense_reclassification_prior_project` FOREIGN KEY (`prior_project_id`) REFERENCES `qbook_projects` (`id`) ON DELETE RESTRICT ON UPDATE RESTRICT,
  CONSTRAINT `fk_petty_expense_reclassification_reversal` FOREIGN KEY (`reversal_journal_id`) REFERENCES `qbook_financial_journals` (`id`) ON DELETE RESTRICT ON UPDATE RESTRICT
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;
/*!40101 SET character_set_client = @saved_cs_client */;
/*!40101 SET @saved_cs_client     = @@character_set_client */;
/*!50503 SET character_set_client = utf8mb4 */;
CREATE TABLE `qbook_petty_cash_expense_references` (
  `reference_no` bigint unsigned NOT NULL AUTO_INCREMENT,
  `expense_id` bigint unsigned DEFAULT NULL,
  `issued_at` datetime NOT NULL DEFAULT CURRENT_TIMESTAMP,
  PRIMARY KEY (`reference_no`),
  UNIQUE KEY `uq_petty_cash_expense_reference_expense` (`expense_id`),
  CONSTRAINT `fk_petty_cash_expense_reference_expense` FOREIGN KEY (`expense_id`) REFERENCES `qbook_petty_cash_expenses` (`id`) ON DELETE SET NULL ON UPDATE RESTRICT
) ENGINE=InnoDB AUTO_INCREMENT=10 DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;
/*!40101 SET character_set_client = @saved_cs_client */;
/*!40101 SET @saved_cs_client     = @@character_set_client */;
/*!50503 SET character_set_client = utf8mb4 */;
CREATE TABLE `qbook_petty_cash_expenses` (
  `id` bigint unsigned NOT NULL AUTO_INCREMENT,
  `custodian_user_id` bigint unsigned NOT NULL,
  `expense_date` date DEFAULT NULL,
  `amount` decimal(18,2) DEFAULT NULL,
  `line_model_version` tinyint unsigned NOT NULL DEFAULT '0',
  `expense_account_id` bigint unsigned DEFAULT NULL,
  `supplier_id` bigint unsigned DEFAULT NULL,
  `supplier_paid_to` varchar(200) CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci DEFAULT NULL,
  `description` varchar(500) CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci DEFAULT NULL,
  `client_id` bigint unsigned DEFAULT NULL,
  `project_id` bigint unsigned DEFAULT NULL,
  `mixer_id` bigint unsigned DEFAULT NULL,
  `status` enum('DRAFT','SUBMITTED','CORRECTION_REQUIRED','APPROVED','CANCELLED_NOT_SPENT','VOIDED') CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci NOT NULL DEFAULT 'DRAFT',
  `no_receipt_reason` varchar(500) CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci DEFAULT NULL,
  `journal_id` bigint unsigned DEFAULT NULL,
  `reversal_journal_id` bigint unsigned DEFAULT NULL,
  `created_by` bigint unsigned NOT NULL,
  `submitted_at` datetime DEFAULT NULL,
  `reviewed_by` bigint unsigned DEFAULT NULL,
  `reviewed_at` datetime DEFAULT NULL,
  `review_reason` varchar(500) CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci DEFAULT NULL,
  `voided_by` bigint unsigned DEFAULT NULL,
  `voided_at` datetime DEFAULT NULL,
  `void_reason` varchar(500) CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci DEFAULT NULL,
  `created_at` datetime NOT NULL DEFAULT CURRENT_TIMESTAMP,
  `updated_at` datetime NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
  PRIMARY KEY (`id`),
  UNIQUE KEY `uq_petty_expense_journal` (`journal_id`),
  UNIQUE KEY `uq_petty_expense_reversal_journal` (`reversal_journal_id`),
  KEY `idx_petty_expense_custodian_status` (`custodian_user_id`,`status`,`expense_date`),
  KEY `idx_petty_expense_account` (`expense_account_id`),
  KEY `idx_petty_expense_client` (`client_id`),
  KEY `idx_petty_expense_project` (`project_id`),
  KEY `idx_petty_expense_mixer` (`mixer_id`),
  KEY `idx_petty_expense_created_by` (`created_by`),
  KEY `idx_petty_expense_reviewed_by` (`reviewed_by`),
  KEY `idx_petty_expense_voided_by` (`voided_by`),
  KEY `fk_petty_expense_supplier` (`supplier_id`),
  CONSTRAINT `fk_petty_expense_account` FOREIGN KEY (`expense_account_id`) REFERENCES `qbook_accounts_chart` (`id`) ON DELETE RESTRICT ON UPDATE RESTRICT,
  CONSTRAINT `fk_petty_expense_client` FOREIGN KEY (`client_id`) REFERENCES `qbook_clients` (`id`) ON DELETE RESTRICT ON UPDATE RESTRICT,
  CONSTRAINT `fk_petty_expense_created_by` FOREIGN KEY (`created_by`) REFERENCES `qbook_users` (`id`) ON DELETE RESTRICT ON UPDATE RESTRICT,
  CONSTRAINT `fk_petty_expense_custodian` FOREIGN KEY (`custodian_user_id`) REFERENCES `qbook_users` (`id`) ON DELETE RESTRICT ON UPDATE RESTRICT,
  CONSTRAINT `fk_petty_expense_journal` FOREIGN KEY (`journal_id`) REFERENCES `qbook_financial_journals` (`id`) ON DELETE RESTRICT ON UPDATE RESTRICT,
  CONSTRAINT `fk_petty_expense_mixer` FOREIGN KEY (`mixer_id`) REFERENCES `qbook_mixers` (`id`) ON DELETE RESTRICT ON UPDATE RESTRICT,
  CONSTRAINT `fk_petty_expense_project` FOREIGN KEY (`project_id`) REFERENCES `qbook_projects` (`id`) ON DELETE RESTRICT ON UPDATE RESTRICT,
  CONSTRAINT `fk_petty_expense_reversal_journal` FOREIGN KEY (`reversal_journal_id`) REFERENCES `qbook_financial_journals` (`id`) ON DELETE RESTRICT ON UPDATE RESTRICT,
  CONSTRAINT `fk_petty_expense_reviewed_by` FOREIGN KEY (`reviewed_by`) REFERENCES `qbook_users` (`id`) ON DELETE RESTRICT ON UPDATE RESTRICT,
  CONSTRAINT `fk_petty_expense_supplier` FOREIGN KEY (`supplier_id`) REFERENCES `qbook_suppliers` (`id`) ON DELETE RESTRICT ON UPDATE RESTRICT,
  CONSTRAINT `fk_petty_expense_voided_by` FOREIGN KEY (`voided_by`) REFERENCES `qbook_users` (`id`) ON DELETE RESTRICT ON UPDATE RESTRICT
) ENGINE=InnoDB AUTO_INCREMENT=13 DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;
/*!40101 SET character_set_client = @saved_cs_client */;
/*!40101 SET @saved_cs_client     = @@character_set_client */;
/*!50503 SET character_set_client = utf8mb4 */;
CREATE TABLE `qbook_petty_cash_fundings` (
  `id` bigint unsigned NOT NULL AUTO_INCREMENT,
  `bank_account_id` bigint unsigned NOT NULL,
  `custodian_user_id` bigint unsigned NOT NULL,
  `amount` decimal(18,2) NOT NULL,
  `funding_date` date NOT NULL,
  `bank_reference` varchar(150) CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci NOT NULL,
  `description` varchar(500) CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci DEFAULT NULL,
  `journal_id` bigint unsigned DEFAULT NULL,
  `created_by` bigint unsigned NOT NULL,
  `created_at` datetime NOT NULL DEFAULT CURRENT_TIMESTAMP,
  PRIMARY KEY (`id`),
  UNIQUE KEY `uq_petty_funding_bank_reference` (`bank_account_id`,`funding_date`,`bank_reference`,`amount`),
  UNIQUE KEY `uq_petty_funding_journal` (`journal_id`),
  KEY `idx_petty_funding_bank_date` (`bank_account_id`,`funding_date`),
  KEY `idx_petty_funding_custodian` (`custodian_user_id`,`funding_date`),
  KEY `idx_petty_funding_created_by` (`created_by`),
  CONSTRAINT `fk_petty_funding_bank` FOREIGN KEY (`bank_account_id`) REFERENCES `qbook_bank_accounts` (`id`) ON DELETE RESTRICT ON UPDATE RESTRICT,
  CONSTRAINT `fk_petty_funding_created_by` FOREIGN KEY (`created_by`) REFERENCES `qbook_users` (`id`) ON DELETE RESTRICT ON UPDATE RESTRICT,
  CONSTRAINT `fk_petty_funding_custodian` FOREIGN KEY (`custodian_user_id`) REFERENCES `qbook_users` (`id`) ON DELETE RESTRICT ON UPDATE RESTRICT,
  CONSTRAINT `fk_petty_funding_journal` FOREIGN KEY (`journal_id`) REFERENCES `qbook_financial_journals` (`id`) ON DELETE RESTRICT ON UPDATE RESTRICT
) ENGINE=InnoDB AUTO_INCREMENT=4 DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;
/*!40101 SET character_set_client = @saved_cs_client */;
/*!40101 SET @saved_cs_client     = @@character_set_client */;
/*!50503 SET character_set_client = utf8mb4 */;
CREATE TABLE `qbook_petty_cash_line_reclassifications` (
  `id` bigint unsigned NOT NULL AUTO_INCREMENT,
  `expense_id` bigint unsigned NOT NULL,
  `line_id` bigint unsigned NOT NULL,
  `version_no` int unsigned NOT NULL,
  `before_snapshot` json NOT NULL,
  `after_snapshot` json NOT NULL,
  `journal_id` bigint unsigned DEFAULT NULL,
  `reversal_journal_id` bigint unsigned DEFAULT NULL,
  `reason` varchar(500) CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci NOT NULL,
  `reclassified_by` bigint unsigned NOT NULL,
  `reclassified_at` datetime NOT NULL DEFAULT CURRENT_TIMESTAMP,
  PRIMARY KEY (`id`),
  UNIQUE KEY `uq_petty_line_reclass_version` (`line_id`,`version_no`),
  UNIQUE KEY `uq_petty_line_reclass_journal` (`journal_id`),
  UNIQUE KEY `uq_petty_line_reclass_reversal` (`reversal_journal_id`),
  KEY `idx_petty_line_reclass_expense` (`expense_id`,`id`),
  KEY `fk_petty_line_reclass_actor` (`reclassified_by`),
  CONSTRAINT `fk_petty_line_reclass_actor` FOREIGN KEY (`reclassified_by`) REFERENCES `qbook_users` (`id`) ON DELETE RESTRICT ON UPDATE RESTRICT,
  CONSTRAINT `fk_petty_line_reclass_expense` FOREIGN KEY (`expense_id`) REFERENCES `qbook_petty_cash_expenses` (`id`) ON DELETE RESTRICT ON UPDATE RESTRICT,
  CONSTRAINT `fk_petty_line_reclass_journal` FOREIGN KEY (`journal_id`) REFERENCES `qbook_financial_journals` (`id`) ON DELETE RESTRICT ON UPDATE RESTRICT,
  CONSTRAINT `fk_petty_line_reclass_line` FOREIGN KEY (`line_id`) REFERENCES `qbook_petty_cash_expense_lines` (`id`) ON DELETE RESTRICT ON UPDATE RESTRICT,
  CONSTRAINT `fk_petty_line_reclass_reversal` FOREIGN KEY (`reversal_journal_id`) REFERENCES `qbook_financial_journals` (`id`) ON DELETE RESTRICT ON UPDATE RESTRICT
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;
/*!40101 SET character_set_client = @saved_cs_client */;
/*!40101 SET @saved_cs_client     = @@character_set_client */;
/*!50503 SET character_set_client = utf8mb4 */;
CREATE TABLE `qbook_production_load_revisions` (
  `id` bigint unsigned NOT NULL AUTO_INCREMENT,
  `production_load_id` bigint unsigned NOT NULL,
  `old_volume_m3` decimal(8,2) NOT NULL,
  `new_volume_m3` decimal(8,2) NOT NULL,
  `changed_by` bigint unsigned NOT NULL,
  `changed_at` datetime NOT NULL DEFAULT CURRENT_TIMESTAMP,
  PRIMARY KEY (`id`),
  KEY `idx_load_revision_load` (`production_load_id`,`changed_at`),
  KEY `idx_load_revision_changed_by` (`changed_by`),
  CONSTRAINT `fk_load_revision_load` FOREIGN KEY (`production_load_id`) REFERENCES `qbook_production_loads` (`id`),
  CONSTRAINT `fk_load_revision_user` FOREIGN KEY (`changed_by`) REFERENCES `qbook_users` (`id`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;
/*!40101 SET character_set_client = @saved_cs_client */;
/*!40101 SET @saved_cs_client     = @@character_set_client */;
/*!50503 SET character_set_client = utf8mb4 */;
CREATE TABLE `qbook_production_loads` (
  `id` bigint unsigned NOT NULL AUTO_INCREMENT,
  `production_session_id` bigint unsigned NOT NULL,
  `load_number` int unsigned NOT NULL,
  `volume_m3` decimal(8,2) NOT NULL,
  `recorded_at` datetime NOT NULL DEFAULT CURRENT_TIMESTAMP,
  `recorded_by` bigint unsigned NOT NULL,
  `updated_at` datetime NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
  `updated_by` bigint unsigned DEFAULT NULL,
  PRIMARY KEY (`id`),
  UNIQUE KEY `uq_production_load_number` (`production_session_id`,`load_number`),
  KEY `idx_production_load_recorded_by` (`recorded_by`),
  KEY `idx_production_load_updated_by` (`updated_by`),
  CONSTRAINT `fk_production_load_recorded_by` FOREIGN KEY (`recorded_by`) REFERENCES `qbook_users` (`id`),
  CONSTRAINT `fk_production_load_session` FOREIGN KEY (`production_session_id`) REFERENCES `qbook_production_sessions` (`id`),
  CONSTRAINT `fk_production_load_updated_by` FOREIGN KEY (`updated_by`) REFERENCES `qbook_users` (`id`)
) ENGINE=InnoDB AUTO_INCREMENT=22 DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;
/*!40101 SET character_set_client = @saved_cs_client */;
/*!40101 SET @saved_cs_client     = @@character_set_client */;
/*!50503 SET character_set_client = utf8mb4 */;
CREATE TABLE `qbook_production_reports` (
  `report_no` bigint unsigned NOT NULL AUTO_INCREMENT,
  `production_session_id` bigint unsigned NOT NULL,
  `issued_at` datetime NOT NULL,
  PRIMARY KEY (`report_no`),
  UNIQUE KEY `uq_production_report_session` (`production_session_id`),
  CONSTRAINT `fk_production_report_session` FOREIGN KEY (`production_session_id`) REFERENCES `qbook_production_sessions` (`id`) ON DELETE RESTRICT ON UPDATE RESTRICT
) ENGINE=InnoDB AUTO_INCREMENT=8 DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;
/*!40101 SET character_set_client = @saved_cs_client */;
/*!40101 SET @saved_cs_client     = @@character_set_client */;
/*!50503 SET character_set_client = utf8mb4 */;
CREATE TABLE `qbook_production_sessions` (
  `id` bigint unsigned NOT NULL AUTO_INCREMENT,
  `production_date` date NOT NULL,
  `client_id` bigint unsigned DEFAULT NULL,
  `project_id` bigint unsigned DEFAULT NULL,
  `client_name` varchar(150) CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci NOT NULL,
  `project_site` varchar(200) CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci NOT NULL,
  `mixer_id` bigint unsigned NOT NULL,
  `mixer_code_snapshot` varchar(50) CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci NOT NULL,
  `mixer_name_snapshot` varchar(150) CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci NOT NULL,
  `loading_point` varchar(200) CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci NOT NULL,
  `discharge_point` varchar(200) CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci NOT NULL,
  `operator_id` bigint unsigned NOT NULL,
  `operator_name_snapshot` varchar(150) CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci NOT NULL,
  `notes` text CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci,
  `status` varchar(20) CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci NOT NULL DEFAULT 'OPEN',
  `created_at` datetime NOT NULL DEFAULT CURRENT_TIMESTAMP,
  `updated_at` datetime NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
  `signed_at` datetime DEFAULT NULL,
  PRIMARY KEY (`id`),
  KEY `idx_production_sessions_operator_date` (`operator_id`,`production_date`),
  KEY `idx_production_sessions_status_date` (`status`,`production_date`),
  KEY `idx_production_sessions_mixer_date` (`mixer_id`,`production_date`),
  KEY `idx_production_sessions_client_date` (`client_id`,`production_date`),
  KEY `idx_production_sessions_project_date` (`project_id`,`production_date`),
  CONSTRAINT `fk_production_session_client` FOREIGN KEY (`client_id`) REFERENCES `qbook_clients` (`id`) ON DELETE RESTRICT ON UPDATE RESTRICT,
  CONSTRAINT `fk_production_session_mixer` FOREIGN KEY (`mixer_id`) REFERENCES `qbook_mixers` (`id`),
  CONSTRAINT `fk_production_session_operator` FOREIGN KEY (`operator_id`) REFERENCES `qbook_users` (`id`),
  CONSTRAINT `fk_production_sessions_project` FOREIGN KEY (`project_id`) REFERENCES `qbook_projects` (`id`) ON DELETE RESTRICT ON UPDATE RESTRICT
) ENGINE=InnoDB AUTO_INCREMENT=10 DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;
/*!40101 SET character_set_client = @saved_cs_client */;
/*!40101 SET @saved_cs_client     = @@character_set_client */;
/*!50503 SET character_set_client = utf8mb4 */;
CREATE TABLE `qbook_production_setting_admixtures` (
  `id` bigint unsigned NOT NULL AUTO_INCREMENT,
  `production_setting_id` bigint unsigned NOT NULL,
  `mix_admixture_id` bigint unsigned NOT NULL,
  `flow_lpm` decimal(14,8) NOT NULL,
  PRIMARY KEY (`id`),
  UNIQUE KEY `uq_qbook_setting_admix` (`production_setting_id`,`mix_admixture_id`),
  KEY `fk_qbook_setting_admix_source` (`mix_admixture_id`),
  CONSTRAINT `fk_qbook_setting_admix_setting` FOREIGN KEY (`production_setting_id`) REFERENCES `qbook_production_settings` (`id`) ON DELETE CASCADE,
  CONSTRAINT `fk_qbook_setting_admix_source` FOREIGN KEY (`mix_admixture_id`) REFERENCES `qbook_mix_admixtures` (`id`)
) ENGINE=InnoDB AUTO_INCREMENT=13 DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;
/*!40101 SET character_set_client = @saved_cs_client */;
/*!40101 SET @saved_cs_client     = @@character_set_client */;
/*!50503 SET character_set_client = utf8mb4 */;
CREATE TABLE `qbook_production_settings` (
  `id` bigint unsigned NOT NULL AUTO_INCREMENT,
  `mixer_id` bigint unsigned NOT NULL,
  `calibration_id` bigint unsigned NOT NULL,
  `calibration_revision_no` int NOT NULL DEFAULT '1',
  `mix_design_id` bigint unsigned NOT NULL,
  `mix_version_no` int unsigned NOT NULL DEFAULT '1',
  `mix_name` varchar(120) CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci DEFAULT NULL,
  `client_name` varchar(150) CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci DEFAULT NULL,
  `project_name` varchar(150) CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci DEFAULT NULL,
  `cement_kg` decimal(12,4) DEFAULT NULL,
  `sand_kg` decimal(12,4) DEFAULT NULL,
  `granite_kg` decimal(12,4) DEFAULT NULL,
  `design_water_l` decimal(12,4) DEFAULT NULL,
  `operator_id` bigint unsigned NOT NULL,
  `conveyor_speed` decimal(10,4) NOT NULL,
  `cement_kg_per_count` decimal(14,9) NOT NULL,
  `counts_per_m3` decimal(14,6) NOT NULL,
  `m3_per_min` decimal(14,9) NOT NULL,
  `sand_target_kg_per_count` decimal(14,9) NOT NULL,
  `granite_target_kg_per_count` decimal(14,9) NOT NULL,
  `sand_gate_cm` decimal(10,6) NOT NULL,
  `granite_gate_cm` decimal(10,6) NOT NULL,
  `sand_moisture_l` decimal(14,6) NOT NULL DEFAULT '0.000000',
  `granite_moisture_l` decimal(14,6) NOT NULL DEFAULT '0.000000',
  `water_additional_l` decimal(14,6) NOT NULL,
  `water_flow_lpm` decimal(14,6) NOT NULL,
  `created_at` timestamp NOT NULL DEFAULT CURRENT_TIMESTAMP,
  PRIMARY KEY (`id`),
  KEY `idx_qbook_settings_mixer` (`mixer_id`),
  KEY `idx_qbook_settings_mix` (`mix_design_id`),
  KEY `idx_qbook_settings_cal` (`calibration_id`),
  KEY `idx_qbook_settings_operator` (`operator_id`),
  KEY `idx_qbook_settings_created` (`created_at`),
  CONSTRAINT `fk_qbook_settings_cal` FOREIGN KEY (`calibration_id`) REFERENCES `qbook_calibrations` (`id`),
  CONSTRAINT `fk_qbook_settings_mix` FOREIGN KEY (`mix_design_id`) REFERENCES `qbook_mix_designs` (`id`),
  CONSTRAINT `fk_qbook_settings_mixer` FOREIGN KEY (`mixer_id`) REFERENCES `qbook_mixers` (`id`),
  CONSTRAINT `fk_qbook_settings_operator` FOREIGN KEY (`operator_id`) REFERENCES `qbook_users` (`id`)
) ENGINE=InnoDB AUTO_INCREMENT=14 DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;
/*!40101 SET character_set_client = @saved_cs_client */;
/*!40101 SET @saved_cs_client     = @@character_set_client */;
/*!50503 SET character_set_client = utf8mb4 */;
CREATE TABLE `qbook_production_signoffs` (
  `id` bigint unsigned NOT NULL AUTO_INCREMENT,
  `production_session_id` bigint unsigned NOT NULL,
  `representative_name` varchar(150) CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci NOT NULL,
  `signature_mime` varchar(50) CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci NOT NULL,
  `signature_data` mediumblob NOT NULL,
  `signature_sha256` char(64) CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci NOT NULL,
  `load_count` int unsigned NOT NULL,
  `total_m3` decimal(10,2) NOT NULL,
  `signed_at` datetime NOT NULL,
  `signed_by_user_id` bigint unsigned NOT NULL,
  PRIMARY KEY (`id`),
  UNIQUE KEY `uq_production_signoff_session` (`production_session_id`),
  KEY `idx_production_signoff_signed_by` (`signed_by_user_id`),
  CONSTRAINT `fk_production_signoff_session` FOREIGN KEY (`production_session_id`) REFERENCES `qbook_production_sessions` (`id`),
  CONSTRAINT `fk_production_signoff_user` FOREIGN KEY (`signed_by_user_id`) REFERENCES `qbook_users` (`id`)
) ENGINE=InnoDB AUTO_INCREMENT=9 DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;
/*!40101 SET character_set_client = @saved_cs_client */;
/*!40101 SET @saved_cs_client     = @@character_set_client */;
/*!50503 SET character_set_client = utf8mb4 */;
CREATE TABLE `qbook_project_mixers` (
  `project_id` bigint unsigned NOT NULL,
  `mixer_id` bigint unsigned NOT NULL,
  `is_active` tinyint(1) NOT NULL DEFAULT '1',
  `assigned_by` bigint unsigned NOT NULL,
  `created_at` datetime NOT NULL DEFAULT CURRENT_TIMESTAMP,
  `updated_at` datetime NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
  PRIMARY KEY (`project_id`,`mixer_id`),
  KEY `idx_project_mixers_mixer_active` (`mixer_id`,`is_active`,`project_id`),
  KEY `idx_project_mixers_assigned_by` (`assigned_by`),
  CONSTRAINT `fk_project_mixers_assigned_by` FOREIGN KEY (`assigned_by`) REFERENCES `qbook_users` (`id`) ON DELETE RESTRICT ON UPDATE RESTRICT,
  CONSTRAINT `fk_project_mixers_mixer` FOREIGN KEY (`mixer_id`) REFERENCES `qbook_mixers` (`id`) ON DELETE RESTRICT ON UPDATE RESTRICT,
  CONSTRAINT `fk_project_mixers_project` FOREIGN KEY (`project_id`) REFERENCES `qbook_projects` (`id`) ON DELETE RESTRICT ON UPDATE RESTRICT
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;
/*!40101 SET character_set_client = @saved_cs_client */;
/*!40101 SET @saved_cs_client     = @@character_set_client */;
/*!50503 SET character_set_client = utf8mb4 */;
CREATE TABLE `qbook_projects` (
  `id` bigint unsigned NOT NULL AUTO_INCREMENT,
  `client_id` bigint unsigned NOT NULL,
  `name` varchar(200) CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci NOT NULL,
  `is_active` tinyint(1) NOT NULL DEFAULT '1',
  `archived_at` datetime DEFAULT NULL,
  `archived_by` bigint unsigned DEFAULT NULL,
  `created_at` datetime NOT NULL DEFAULT CURRENT_TIMESTAMP,
  `updated_at` datetime NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
  PRIMARY KEY (`id`),
  UNIQUE KEY `uq_projects_client_name` (`client_id`,`name`),
  KEY `idx_projects_client_active_name` (`client_id`,`is_active`,`name`),
  KEY `idx_projects_archive_client` (`archived_at`,`client_id`,`name`),
  KEY `idx_projects_archived_by` (`archived_by`),
  CONSTRAINT `fk_projects_archived_by` FOREIGN KEY (`archived_by`) REFERENCES `qbook_users` (`id`) ON DELETE RESTRICT ON UPDATE RESTRICT,
  CONSTRAINT `fk_projects_client` FOREIGN KEY (`client_id`) REFERENCES `qbook_clients` (`id`) ON DELETE RESTRICT ON UPDATE RESTRICT
) ENGINE=InnoDB AUTO_INCREMENT=3 DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;
/*!40101 SET character_set_client = @saved_cs_client */;
/*!40101 SET @saved_cs_client     = @@character_set_client */;
/*!50503 SET character_set_client = utf8mb4 */;
CREATE TABLE `qbook_receipt_wht` (
  `id` bigint unsigned NOT NULL AUTO_INCREMENT,
  `receipt_id` bigint unsigned NOT NULL,
  `tax_code_id` bigint unsigned NOT NULL,
  `rate_snapshot` decimal(9,6) NOT NULL,
  `calculation_base_snapshot` enum('NET','GROSS','MANUAL') CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci NOT NULL,
  `accepted_amount` decimal(18,2) NOT NULL,
  `certificate_status` enum('NOT_APPLICABLE','CERTIFICATE_PENDING','CERTIFICATE_RECEIVED') CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci NOT NULL,
  `certificate_received_at` datetime DEFAULT NULL,
  `created_at` datetime NOT NULL DEFAULT CURRENT_TIMESTAMP,
  PRIMARY KEY (`id`),
  UNIQUE KEY `receipt_id` (`receipt_id`),
  KEY `idx_wht_certificate` (`certificate_status`),
  KEY `fk_receipt_wht_code` (`tax_code_id`),
  CONSTRAINT `fk_receipt_wht_code` FOREIGN KEY (`tax_code_id`) REFERENCES `qbook_tax_codes` (`id`) ON DELETE RESTRICT ON UPDATE RESTRICT,
  CONSTRAINT `fk_receipt_wht_receipt` FOREIGN KEY (`receipt_id`) REFERENCES `qbook_customer_receipts` (`id`) ON DELETE RESTRICT ON UPDATE RESTRICT
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;
/*!40101 SET character_set_client = @saved_cs_client */;
/*!40101 SET @saved_cs_client     = @@character_set_client */;
/*!50503 SET character_set_client = utf8mb4 */;
CREATE TABLE `qbook_reference_log` (
  `id` bigint unsigned NOT NULL AUTO_INCREMENT,
  `reference_no` varchar(20) CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci NOT NULL,
  `description` varchar(255) CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci DEFAULT NULL,
  `reference_type` varchar(40) CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci NOT NULL DEFAULT 'STANDARD',
  `generated_by` bigint unsigned DEFAULT NULL,
  `source` varchar(40) CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci NOT NULL DEFAULT 'MOBILE',
  `created_at` timestamp NOT NULL DEFAULT CURRENT_TIMESTAMP,
  PRIMARY KEY (`id`),
  KEY `idx_reference_no` (`reference_no`),
  KEY `idx_reference_created` (`created_at`),
  KEY `fk_reference_generated_by` (`generated_by`),
  CONSTRAINT `fk_reference_generated_by` FOREIGN KEY (`generated_by`) REFERENCES `qbook_users` (`id`) ON DELETE SET NULL
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;
/*!40101 SET character_set_client = @saved_cs_client */;
/*!40101 SET @saved_cs_client     = @@character_set_client */;
/*!50503 SET character_set_client = utf8mb4 */;
CREATE TABLE `qbook_sequences` (
  `sequence_name` varchar(50) CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci NOT NULL,
  `next_value` bigint unsigned NOT NULL,
  `updated_at` timestamp NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
  PRIMARY KEY (`sequence_name`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;
/*!40101 SET character_set_client = @saved_cs_client */;
/*!40101 SET @saved_cs_client     = @@character_set_client */;
/*!50503 SET character_set_client = utf8mb4 */;
CREATE TABLE `qbook_supplier_aliases` (
  `id` bigint unsigned NOT NULL AUTO_INCREMENT,
  `supplier_id` bigint unsigned NOT NULL,
  `alias_name` varchar(200) CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci NOT NULL,
  `normalized_alias` varchar(200) CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci NOT NULL,
  `created_by` bigint unsigned NOT NULL,
  `created_at` datetime NOT NULL DEFAULT CURRENT_TIMESTAMP,
  PRIMARY KEY (`id`),
  UNIQUE KEY `uq_supplier_alias_normalized` (`normalized_alias`),
  KEY `idx_supplier_alias_supplier` (`supplier_id`),
  KEY `fk_supplier_alias_created_by` (`created_by`),
  CONSTRAINT `fk_supplier_alias_created_by` FOREIGN KEY (`created_by`) REFERENCES `qbook_users` (`id`) ON DELETE RESTRICT ON UPDATE RESTRICT,
  CONSTRAINT `fk_supplier_alias_supplier` FOREIGN KEY (`supplier_id`) REFERENCES `qbook_suppliers` (`id`) ON DELETE RESTRICT ON UPDATE RESTRICT
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;
/*!40101 SET character_set_client = @saved_cs_client */;
/*!40101 SET @saved_cs_client     = @@character_set_client */;
/*!50503 SET character_set_client = utf8mb4 */;
CREATE TABLE `qbook_suppliers` (
  `id` bigint unsigned NOT NULL AUTO_INCREMENT,
  `canonical_name` varchar(200) CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci NOT NULL,
  `normalized_name` varchar(200) CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci NOT NULL,
  `contact_person` varchar(200) CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci DEFAULT NULL,
  `phone` varchar(80) CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci DEFAULT NULL,
  `email` varchar(255) CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci DEFAULT NULL,
  `address` varchar(500) CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci DEFAULT NULL,
  `supplier_type` varchar(100) CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci DEFAULT NULL,
  `is_active` tinyint(1) NOT NULL DEFAULT '1',
  `created_by` bigint unsigned NOT NULL,
  `updated_by` bigint unsigned NOT NULL,
  `created_at` datetime NOT NULL DEFAULT CURRENT_TIMESTAMP,
  `updated_at` datetime NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
  PRIMARY KEY (`id`),
  UNIQUE KEY `uq_supplier_normalized_name` (`normalized_name`),
  KEY `idx_supplier_active_name` (`is_active`,`canonical_name`),
  KEY `fk_supplier_created_by` (`created_by`),
  KEY `fk_supplier_updated_by` (`updated_by`),
  CONSTRAINT `fk_supplier_created_by` FOREIGN KEY (`created_by`) REFERENCES `qbook_users` (`id`) ON DELETE RESTRICT ON UPDATE RESTRICT,
  CONSTRAINT `fk_supplier_updated_by` FOREIGN KEY (`updated_by`) REFERENCES `qbook_users` (`id`) ON DELETE RESTRICT ON UPDATE RESTRICT
) ENGINE=InnoDB AUTO_INCREMENT=2 DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;
/*!40101 SET character_set_client = @saved_cs_client */;
/*!40101 SET @saved_cs_client     = @@character_set_client */;
/*!50503 SET character_set_client = utf8mb4 */;
CREATE TABLE `qbook_tax_codes` (
  `id` bigint unsigned NOT NULL AUTO_INCREMENT,
  `code` varchar(40) CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci NOT NULL,
  `name` varchar(150) CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci NOT NULL,
  `tax_type` enum('VAT','WHT') CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci NOT NULL,
  `rate_percent` decimal(9,6) NOT NULL,
  `calculation_base` enum('NET','GROSS','MANUAL') CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci NOT NULL DEFAULT 'NET',
  `account_role_code` varchar(50) CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci NOT NULL,
  `effective_from` date NOT NULL,
  `effective_to` date DEFAULT NULL,
  `is_active` tinyint(1) NOT NULL DEFAULT '1',
  `created_by` bigint unsigned DEFAULT NULL,
  `created_at` datetime NOT NULL DEFAULT CURRENT_TIMESTAMP,
  PRIMARY KEY (`id`),
  UNIQUE KEY `uq_tax_code_effective` (`code`,`effective_from`),
  KEY `idx_tax_type_effective` (`tax_type`,`is_active`,`effective_from`,`effective_to`),
  KEY `fk_tax_account_role` (`account_role_code`),
  KEY `fk_tax_created_by` (`created_by`),
  CONSTRAINT `fk_tax_account_role` FOREIGN KEY (`account_role_code`) REFERENCES `qbook_financial_account_roles` (`role_code`) ON DELETE RESTRICT ON UPDATE RESTRICT,
  CONSTRAINT `fk_tax_created_by` FOREIGN KEY (`created_by`) REFERENCES `qbook_users` (`id`) ON DELETE RESTRICT ON UPDATE RESTRICT
) ENGINE=InnoDB AUTO_INCREMENT=7 DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;
/*!40101 SET character_set_client = @saved_cs_client */;
/*!40101 SET @saved_cs_client     = @@character_set_client */;
/*!50503 SET character_set_client = utf8mb4 */;
CREATE TABLE `qbook_users` (
  `id` bigint unsigned NOT NULL AUTO_INCREMENT,
  `company_id` bigint unsigned NOT NULL,
  `full_name` varchar(150) CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci NOT NULL,
  `username` varchar(100) CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci DEFAULT NULL,
  `email` varchar(190) CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci DEFAULT NULL,
  `phone` varchar(40) CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci DEFAULT NULL,
  `role` varchar(40) CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci NOT NULL DEFAULT 'USER',
  `password_hash` varchar(255) CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci DEFAULT NULL,
  `is_active` tinyint(1) NOT NULL DEFAULT '1',
  `created_at` timestamp NOT NULL DEFAULT CURRENT_TIMESTAMP,
  `updated_at` timestamp NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
  PRIMARY KEY (`id`),
  UNIQUE KEY `uq_qbook_users_email` (`email`),
  UNIQUE KEY `uq_users_username` (`username`),
  KEY `idx_qbook_users_role` (`role`),
  KEY `idx_qbook_users_active` (`is_active`),
  KEY `idx_users_company` (`company_id`),
  CONSTRAINT `fk_users_company` FOREIGN KEY (`company_id`) REFERENCES `qbook_companies` (`id`) ON DELETE RESTRICT ON UPDATE RESTRICT
) ENGINE=InnoDB AUTO_INCREMENT=5 DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;
/*!40101 SET character_set_client = @saved_cs_client */;
/*!40101 SET @saved_cs_client     = @@character_set_client */;
/*!50503 SET character_set_client = utf8mb4 */;
CREATE TABLE `staff_advance_expenses` (
  `id` bigint unsigned NOT NULL AUTO_INCREMENT,
  `advance_id` bigint unsigned NOT NULL,
  `expense_date` date NOT NULL,
  `reference_no` varchar(20) CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci DEFAULT NULL,
  `payee` varchar(190) CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci DEFAULT NULL,
  `description` varchar(500) CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci NOT NULL,
  `amount` decimal(18,2) NOT NULL,
  `account_name` varchar(190) CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci DEFAULT NULL,
  `status` varchar(30) CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci NOT NULL DEFAULT 'DRAFT',
  `created_by` bigint unsigned NOT NULL,
  `approved_by` bigint unsigned DEFAULT NULL,
  `approved_at` datetime DEFAULT NULL,
  `rejection_reason` text CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci,
  `qbo_id` varchar(100) CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci DEFAULT NULL,
  `qbo_posted_at` datetime DEFAULT NULL,
  `created_at` timestamp NOT NULL DEFAULT CURRENT_TIMESTAMP,
  `updated_at` timestamp NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
  PRIMARY KEY (`id`),
  KEY `idx_advance_expense_advance` (`advance_id`),
  KEY `idx_advance_expense_status` (`status`),
  KEY `idx_advance_expense_date` (`expense_date`),
  KEY `fk_advance_expense_creator` (`created_by`),
  KEY `fk_advance_expense_approver` (`approved_by`),
  CONSTRAINT `fk_advance_expense_advance` FOREIGN KEY (`advance_id`) REFERENCES `staff_advances` (`id`) ON DELETE CASCADE,
  CONSTRAINT `fk_advance_expense_approver` FOREIGN KEY (`approved_by`) REFERENCES `qbook_users` (`id`) ON DELETE SET NULL,
  CONSTRAINT `fk_advance_expense_creator` FOREIGN KEY (`created_by`) REFERENCES `qbook_users` (`id`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;
/*!40101 SET character_set_client = @saved_cs_client */;
/*!40101 SET @saved_cs_client     = @@character_set_client */;
/*!50503 SET character_set_client = utf8mb4 */;
CREATE TABLE `staff_advances` (
  `id` bigint unsigned NOT NULL AUTO_INCREMENT,
  `advance_no` varchar(30) CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci DEFAULT NULL,
  `employee_user_id` bigint unsigned NOT NULL,
  `advance_date` date NOT NULL,
  `amount_advanced` decimal(18,2) NOT NULL,
  `purpose` varchar(500) CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci NOT NULL,
  `source_account` varchar(190) CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci NOT NULL DEFAULT 'Zenith Bank',
  `bank_reference` varchar(190) CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci DEFAULT NULL,
  `qbook_bank_row` bigint DEFAULT NULL,
  `amount_accounted` decimal(18,2) NOT NULL DEFAULT '0.00',
  `amount_returned` decimal(18,2) NOT NULL DEFAULT '0.00',
  `amount_due_from_employee` decimal(18,2) NOT NULL DEFAULT '0.00',
  `amount_due_to_employee` decimal(18,2) NOT NULL DEFAULT '0.00',
  `status` varchar(30) CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci NOT NULL DEFAULT 'OPEN',
  `created_by` bigint unsigned DEFAULT NULL,
  `submitted_at` datetime DEFAULT NULL,
  `approved_by` bigint unsigned DEFAULT NULL,
  `approved_at` datetime DEFAULT NULL,
  `approval_note` text CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci,
  `created_at` timestamp NOT NULL DEFAULT CURRENT_TIMESTAMP,
  `updated_at` timestamp NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
  PRIMARY KEY (`id`),
  KEY `idx_advance_employee` (`employee_user_id`),
  KEY `idx_advance_status` (`status`),
  KEY `idx_advance_date` (`advance_date`),
  KEY `idx_advance_bank_ref` (`bank_reference`),
  KEY `fk_advance_creator` (`created_by`),
  KEY `fk_advance_approver` (`approved_by`),
  CONSTRAINT `fk_advance_approver` FOREIGN KEY (`approved_by`) REFERENCES `qbook_users` (`id`) ON DELETE SET NULL,
  CONSTRAINT `fk_advance_creator` FOREIGN KEY (`created_by`) REFERENCES `qbook_users` (`id`) ON DELETE SET NULL,
  CONSTRAINT `fk_advance_employee` FOREIGN KEY (`employee_user_id`) REFERENCES `qbook_users` (`id`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;
/*!40101 SET character_set_client = @saved_cs_client */;
/*!40103 SET TIME_ZONE=@OLD_TIME_ZONE */;

/*!40101 SET SQL_MODE=@OLD_SQL_MODE */;
/*!40014 SET FOREIGN_KEY_CHECKS=@OLD_FOREIGN_KEY_CHECKS */;
/*!40014 SET UNIQUE_CHECKS=@OLD_UNIQUE_CHECKS */;
/*!40101 SET CHARACTER_SET_CLIENT=@OLD_CHARACTER_SET_CLIENT */;
/*!40101 SET CHARACTER_SET_RESULTS=@OLD_CHARACTER_SET_RESULTS */;
/*!40101 SET COLLATION_CONNECTION=@OLD_COLLATION_CONNECTION */;
/*!40111 SET SQL_NOTES=@OLD_SQL_NOTES */;
