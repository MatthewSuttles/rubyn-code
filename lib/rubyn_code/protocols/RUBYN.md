# Layer 10: Protocols

Safety and coordination protocols for agent lifecycle.

## Classes

- **`ShutdownHandshake`** — Graceful shutdown. Waits for the current tool call to complete,
  saves conversation state, and cleans up resources.

- **`InterruptHandler`** — Traps SIGINT (Ctrl+C). First interrupt cancels the current
  operation. Second interrupt within 2 seconds triggers shutdown.
