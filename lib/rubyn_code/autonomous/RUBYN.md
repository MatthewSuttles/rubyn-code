# Layer 11: Autonomous

Daemon mode for hands-off task execution.

## Classes

- **`Daemon`** — Runs the agent in background mode. Polls for unclaimed tasks,
  executes them, and reports results. No human in the loop.

- **`IdlePoller`** — Watches for new tasks at a configurable interval. Wakes the
  daemon when work is available.

- **`TaskClaimer`** — Atomically claims tasks from the DAG to prevent double-execution
  when multiple agents are running.
