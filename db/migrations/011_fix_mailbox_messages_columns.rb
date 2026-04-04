# frozen_string_literal: true

# Fix mailbox_messages column mismatch between 009_create_teams.sql and
# Teams::Mailbox. The original migration used from_agent/to_agent/content
# but the Mailbox class expects sender/recipient/payload.
#
# This is a Ruby migration (not SQL) because we need to detect which schema
# the user has before running the appropriate ALTER statements. Pure SQL
# can't branch on column existence without parse errors.
module Migration011FixMailboxMessagesColumns
  module_function

  # @param db [RubynCode::DB::Connection] the database connection
  def up(db)
    columns = db.query("SELECT name FROM pragma_table_info('mailbox_messages')").to_a
    column_names = columns.map { |c| c['name'] }

    if column_names.include?('from_agent')
      # Old schema from 009 migration — rename columns
      db.execute('ALTER TABLE mailbox_messages RENAME COLUMN from_agent TO sender')
      db.execute('ALTER TABLE mailbox_messages RENAME COLUMN to_agent TO recipient')
      db.execute('ALTER TABLE mailbox_messages RENAME COLUMN content TO payload')

      # Remap 'text' message_type to 'message' to match Mailbox default
      db.execute("UPDATE mailbox_messages SET message_type = 'message' WHERE message_type = 'text'")
    end

    # Ensure indexes match regardless of which schema path we took
    db.execute('DROP INDEX IF EXISTS idx_mailbox_to')
    db.execute('DROP INDEX IF EXISTS idx_mailbox_from')
    db.execute('CREATE INDEX IF NOT EXISTS idx_mailbox_recipient_read ON mailbox_messages(recipient, read)')
    db.execute('CREATE INDEX IF NOT EXISTS idx_mailbox_sender ON mailbox_messages(sender)')
    db.execute('CREATE INDEX IF NOT EXISTS idx_mailbox_created ON mailbox_messages(created_at)')
  end
end
