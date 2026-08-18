-- NOT APPLIED TO PRODUCTION. Apply before deploying the Build #46
-- username-login and User Management PHP endpoints.
-- Existing users keep their email login and may retain a NULL username.

ALTER TABLE qbook_users
  ADD COLUMN username VARCHAR(100)
    CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci NULL AFTER full_name,
  ADD UNIQUE KEY uq_users_username (username);
