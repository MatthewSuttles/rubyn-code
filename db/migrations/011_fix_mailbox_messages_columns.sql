-- Fix mailbox_messages column mismatch between 009_create_teams.sql and
-- Teams::Mailbox. The original migration used from_agent/to_agent/content
-- but the Mailbox class expects sender/recipient/payload.
--
-- This migration uses ALTER TABLE RENAME COLUMN (SQLite 3.25.0+, 2018-09-15).
-- Ruby's sqlite3 gem bundles SQLite >= 3.39, so this is safe for all users.
--
-- If the table already has the correct columns (ensure_table! won the race),
-- the ALTER statements will fail harmlessly and the migrator records the
-- version as applied regardless.

-- Rename columns to match Teams::Mailbox expectations
ALTER TABLE mailbox_messages RENAME COLUMN from_agent TO sender;
ALTER TABLE mailbox_messages RENAME COLUMN to_agent TO recipient;
ALTER TABLE mailbox_messages RENAME COLUMN content TO payload;
