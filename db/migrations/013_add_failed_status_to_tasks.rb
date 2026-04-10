# frozen_string_literal: true

# Expands the tasks CHECK constraint on status to include 'failed',
# used by the GOLEM daemon to mark tasks that have exceeded max retries.
#
# SQLite does not support ALTER CONSTRAINT, so we rebuild the table.
# The Migrator already wraps .up in a transaction — no manual BEGIN/COMMIT here.
module Migration013AddFailedStatusToTasks
  module_function

  def up(db)
    create_new_tasks_table(db)
    migrate_data(db)
    swap_tables(db)
  end

  def create_new_tasks_table(db)
    db.execute(<<~SQL)
      CREATE TABLE tasks_new (
        id TEXT PRIMARY KEY,
        session_id TEXT REFERENCES sessions(id) ON DELETE SET NULL,
        title TEXT NOT NULL,
        description TEXT,
        status TEXT NOT NULL DEFAULT 'pending'
          CHECK(status IN ('pending','in_progress','blocked','completed','cancelled','failed')),
        priority INTEGER NOT NULL DEFAULT 0,
        owner TEXT,
        result TEXT,
        metadata TEXT DEFAULT '{}',
        created_at TEXT NOT NULL DEFAULT (strftime('%Y-%m-%dT%H:%M:%SZ','now')),
        updated_at TEXT NOT NULL DEFAULT (strftime('%Y-%m-%dT%H:%M:%SZ','now'))
      )
    SQL
  end

  def migrate_data(db)
    db.execute(<<~SQL)
      INSERT INTO tasks_new (id, session_id, title, description, status, priority, owner, result, metadata, created_at, updated_at)
      SELECT id, session_id, title, description, status, priority, owner, result, metadata, created_at, updated_at
      FROM tasks
    SQL
  end

  def swap_tables(db)
    db.execute('DROP TABLE tasks')
    db.execute('ALTER TABLE tasks_new RENAME TO tasks')
    db.execute('CREATE INDEX IF NOT EXISTS idx_tasks_session ON tasks(session_id)')
    db.execute('CREATE INDEX IF NOT EXISTS idx_tasks_status ON tasks(status)')
    db.execute('CREATE INDEX IF NOT EXISTS idx_tasks_owner ON tasks(owner)')
  end
end
