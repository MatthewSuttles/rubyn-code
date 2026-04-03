# Layer 9: Teams

Persistent named teammate agents with asynchronous mailbox messaging.

## Classes

- **`Manager`** — Spawns and manages persistent teammate agents. Each teammate has a name,
  role, and its own conversation context. Persisted in the `teams` SQLite table.

- **`Teammate`** — Represents a single teammate: name, role, conversation state, status.
  Processes messages from its mailbox and can send messages back.

- **`Mailbox`** — Asynchronous message queue between agents. `send_message` enqueues,
  `read_inbox` dequeues. Messages are typed (`:message`, `:task`, `:result`).
