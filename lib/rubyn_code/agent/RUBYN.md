# Layer 1: Agent

The core agentic loop. This is the heartbeat of the whole system.

## Classes

- **`Loop`** — The main agent loop. Sends conversation to Claude, receives a response.
  If the response contains `tool_use` blocks, dispatches them via `Tools::Executor`,
  appends results, and loops. Stops when Claude returns plain text, budget is exhausted,
  or `MAX_ITERATIONS` is reached. Collaborates with `LoopDetector` to break stalls.

- **`Conversation`** — In-memory conversation state. Holds the messages array (user turns,
  assistant turns, tool results). Supports undo, clear, and context compaction.

- **`LoopDetector`** — Detects when the agent is stuck calling the same tool with the same
  arguments. Uses a sliding window (default: 5) with a threshold (default: 3 identical calls).
  Raises `StallDetectedError` when triggered.
