# Changelog

All notable changes to the Rubyn Code VS Code extension will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [0.1.0] - 2026-04-10

### Added

- **Chat panel** with streaming responses — converse with the Rubyn Code agent in a sidebar webview with real-time output
- **Inline diff provider** for code changes — review file modifications as inline diffs before accepting
- **Context-aware commands:**
  - **Refactor Selection** — refactor selected code for readability, reduced duplication, and Ruby/Rails best practices
  - **Generate Specs** — write thorough RSpec specs with edge cases for the active file
  - **Explain Code** — get a plain-language explanation of selected code, including patterns and potential issues
- **PR review integration** — diff your branch against any base branch and get severity-rated feedback (critical, warning, suggestion, nitpick)
- **Status bar** with agent state (idle/thinking/executing) and running session cost tracking
- **Tool approval flow** — approve or deny each tool call (file read, file write, shell command) before execution
- **YOLO mode** — auto-approve all tool calls for uninterrupted workflows (`rubyn-code.yoloMode` setting)
- **Sessions view** — browse and resume previous conversations from the sidebar
- **Keyboard shortcuts:**
  - `Cmd+Shift+R` / `Ctrl+Shift+R` — Open Chat
  - `Cmd+Shift+E` / `Ctrl+Shift+E` — Refactor Selection (when text is selected)
- **Configuration options:** executable path, session budget, model selection, YOLO mode toggle
- **Output channel** (`Rubyn Code`) for diagnostic logging and troubleshooting
- **Automatic activation** on Ruby files, Gemfile presence, or `.rubyn-code` directory
