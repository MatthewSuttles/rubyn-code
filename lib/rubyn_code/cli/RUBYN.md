# CLI Layer

Terminal interface. Entry point → REPL → rendering.

## Classes

- **`App`** — Parses ARGV into commands (`:version`, `:auth`, `:help`, `:run`, `:repl`) and dispatches.
  `App.start(ARGV)` is the gem's entry point from `exe/rubyn-code`.

- **`REPL`** — Read-eval-print loop. Wires up InputHandler for parsing, Agent::Loop for execution,
  Renderer for output. Handles `/slash` commands and multi-line input.

- **`InputHandler`** — Maps user input to `Command` structs (a `Data.define`). Recognizes
  slash commands like `/quit`, `/compact`, `/cost`, `/clear`, `/undo`, `/tasks`, `/budget`.

- **`Renderer`** — Renders LLM responses to the terminal. Uses Pastel for colors,
  Rouge (Monokai theme) for syntax highlighting. Has a `yolo` writer for permission bypass display.

- **`Spinner`** — TTY::Spinner wrapper for thinking/working indicators.

- **`StreamFormatter`** — Handles real-time streaming output from the LLM, buffering partial
  markdown and flushing complete lines with syntax highlighting.
