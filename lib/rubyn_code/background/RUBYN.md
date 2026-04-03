# Layer 8: Background

Background job execution for long-running commands.

## Classes

- **`Worker`** — Manages background processes. Spawns commands in subprocesses,
  tracks their PIDs, and collects output when complete.

- **`Job`** — Represents a single background job: command, PID, status, output.

- **`Notifier`** — Delivers background job results back to the agent. Injects completed
  job output into the conversation before the next LLM call.
