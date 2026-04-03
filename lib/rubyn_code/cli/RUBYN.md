# CLI Layer

Terminal interface. Entry point → REPL → rendering.

## Classes

- **`App`** — Parses ARGV into commands (`:version`, `:auth`, `:help`, `:run`, `:repl`) and dispatches.
  `App.start(ARGV)` is the gem's entry point from `exe/rubyn-code`.

- **`REPL`** — Read-eval-print loop. Wires up InputHandler for parsing, Agent::Loop for execution,
  Renderer for output. Delegates `/slash` commands to the Commands::Registry.

- **`InputHandler`** — Maps user input to `Command` structs (a `Data.define`). Classifies input
  as `:command`, `:message`, or `:quit`. Registry-driven — no hardcoded command list.

- **`Renderer`** — Renders LLM responses to the terminal. Uses Pastel for colors,
  Rouge (Monokai theme) for syntax highlighting. Has a `yolo` writer for permission bypass display.

- **`Spinner`** — TTY::Spinner wrapper for thinking/working indicators.

- **`StreamFormatter`** — Handles real-time streaming output from the LLM, buffering partial
  markdown and flushing complete lines with syntax highlighting.

## Commands Subsystem

See [`commands/RUBYN.md`](commands/RUBYN.md) for full docs.

19 slash commands, each in its own file under `cli/commands/`. Registry-based dispatch
with tab-completion. Commands return optional **action hashes** for REPL state changes
(model switch, plan mode toggle, budget updates, etc.).
