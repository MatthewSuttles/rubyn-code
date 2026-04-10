# Rubyn Code VS Code Extension

Comprehensive documentation for the Rubyn Code Visual Studio Code extension — a Ruby & Rails agentic coding assistant, right in your editor.

## Table of Contents

- [Prerequisites](#prerequisites)
- [Installation](#installation)
- [Getting Started](#getting-started)
- [Feature Tour](#feature-tour)
- [Commands](#commands)
- [Keyboard Shortcuts](#keyboard-shortcuts)
- [Configuration Reference](#configuration-reference)
- [YOLO Mode](#yolo-mode)
- [Troubleshooting](#troubleshooting)
- [Development Setup](#development-setup)

---

## Prerequisites

Before installing the extension, make sure you have:

1. **Ruby 4.0+** installed on your system
2. **The `rubyn-code` gem** installed and authenticated:
   ```bash
   gem install rubyn-code
   rubyn-code --setup
   ```
3. **Authentication configured** — Rubyn Code reads your OAuth token from the macOS Keychain automatically (log in once via `claude` in your terminal), or set `ANTHROPIC_API_KEY` as an environment variable. See the [main project README](../README.md#authentication) for all authentication options.
4. **VS Code 1.98+**

---

## Installation

### From the VS Code Marketplace

1. Open VS Code
2. Go to the Extensions view (`Cmd+Shift+X` on macOS / `Ctrl+Shift+X` on Linux/Windows)
3. Search for **Rubyn Code**
4. Click **Install**

### Manual Install (.vsix)

If you have a `.vsix` file (e.g., from a pre-release build or building from source):

1. Open VS Code
2. Open the Command Palette (`Cmd+Shift+P` / `Ctrl+Shift+P`)
3. Run **Extensions: Install from VSIX...**
4. Select the `.vsix` file
5. Reload VS Code when prompted

---

## Getting Started

### Step 1: Verify the gem is available

Open a terminal and run:

```bash
rubyn-code --version
```

You should see the installed version. If not, install it with `gem install rubyn-code`.

### Step 2: Open a Ruby or Rails project

The extension activates automatically when it detects:

- A file with the `.rb` extension
- A `Gemfile` in the workspace root
- A `.rubyn-code` directory in the workspace root

### Step 3: Open the chat panel

Press `Cmd+Shift+R` (macOS) or `Ctrl+Shift+R` (Linux/Windows) to open the Rubyn Code chat panel. You can also click the Rubyn Code icon in the Activity Bar on the left.

<!-- TODO: Screenshot — Activity Bar icon and chat panel open -->

### Step 4: Start coding with Rubyn

Type a prompt in the chat panel. For example:

- "Refactor this controller into service objects"
- "Write specs for the User model"
- "Explain what this method does"

<!-- TODO: Screenshot — Chat panel with a sample conversation -->

---

## Feature Tour

### Chat Panel

The chat panel is your primary interface for interacting with Rubyn Code. It supports:

- **Streaming responses** — see output in real time as the agent works
- **Tool call visibility** — watch as Rubyn reads files, writes code, and runs commands
- **Tool approval flow** — approve or deny each tool call before it executes (unless YOLO mode is enabled)
- **Session history** — browse and resume previous sessions via the Sessions view

<!-- TODO: GIF — Streaming response in the chat panel -->

### Inline Diffs

When Rubyn Code modifies files, changes appear as inline diffs directly in the editor. You can review each change before accepting it.

<!-- TODO: Screenshot — Inline diff showing a code change -->

### Context-Aware Prompts

Rubyn Code automatically enriches your prompts with relevant context from your project:

- **Controllers** — includes models, routes, request specs, services
- **Models** — includes schema, associations, specs, factories
- **Service objects** — includes referenced models and their specs
- **Any file** — checks for `RUBYN.md`, `CLAUDE.md`, or `AGENT.md` instructions

This means you can say "refactor this" and Rubyn already knows the surrounding code structure.

### PR Review

Run a code review against best practices without leaving your editor. The Review PR command diffs your current branch against a base branch and reports issues by severity:

- **[critical]** — security risks, data loss potential
- **[warning]** — N+1 queries, performance issues
- **[suggestion]** — readability improvements, pattern recommendations
- **[nitpick]** — style and formatting

<!-- TODO: Screenshot — PR review output with severity labels -->

### Status Bar

The status bar displays:

- **Agent state** — idle, thinking, or executing tools
- **Cost tracking** — running token cost for the current session

Click the status bar item to open the chat panel.

<!-- TODO: Screenshot — Status bar showing agent state and cost -->

### Sessions View

The Sessions view in the sidebar lets you browse and resume previous conversations. Each session preserves the full conversation history and any learnings extracted from it.

---

## Commands

All commands are available via the Command Palette (`Cmd+Shift+P` / `Ctrl+Shift+P`):

| Command | Description |
|---------|-------------|
| **Rubyn Code: Open Chat** | Focus the chat panel |
| **Rubyn Code: Review PR** | Run a code review against a base branch (prompts for branch name) |
| **Rubyn Code: Refactor Selection** | Refactor the selected code for readability, reduced duplication, and Ruby/Rails best practices |
| **Rubyn Code: Generate Specs** | Generate RSpec specs with thorough coverage for the active file |
| **Rubyn Code: Explain Code** | Explain what the selected code does, including patterns and potential issues |

---

## Keyboard Shortcuts

| Shortcut | Command | Condition |
|----------|---------|-----------|
| `Cmd+Shift+R` (macOS) / `Ctrl+Shift+R` | Open Chat | Always available |
| `Cmd+Shift+E` (macOS) / `Ctrl+Shift+E` | Refactor Selection | When text is selected in the editor |

---

## Configuration Reference

Open VS Code Settings (`Cmd+,` / `Ctrl+,`) and search for "Rubyn Code" to configure the extension.

### `rubyn-code.yoloMode`

| | |
|---|---|
| **Type** | `boolean` |
| **Default** | `false` |
| **Description** | Enable YOLO mode to auto-approve all tool calls without confirmation. See [YOLO Mode](#yolo-mode) for details. |

### `rubyn-code.executablePath`

| | |
|---|---|
| **Type** | `string` |
| **Default** | `"rubyn-code"` |
| **Description** | Path to the `rubyn-code` CLI executable. Change this if the gem is installed in a non-standard location or you want to point to a development build. |

**Examples:**

```
rubyn-code                          # Default — uses PATH lookup
/Users/you/.local/bin/rubyn-code    # Absolute path
/path/to/rubyn-code/exe/rubyn-code  # Development build
```

### `rubyn-code.sessionBudget`

| | |
|---|---|
| **Type** | `number` |
| **Default** | `5.00` |
| **Description** | Maximum dollar budget per session. When the session cost reaches this limit, Rubyn Code pauses and asks before continuing. Prevents runaway costs on long tasks. |

### `rubyn-code.model`

| | |
|---|---|
| **Type** | `string` |
| **Default** | `"claude-sonnet-4-6"` |
| **Allowed values** | `"claude-opus-4-6"`, `"claude-sonnet-4-6"` |
| **Description** | The model used for completions. Opus is more capable for complex tasks; Sonnet is faster and cheaper for everyday coding. |

---

## YOLO Mode

YOLO mode auto-approves every tool call — file reads, file writes, shell commands, git operations — without asking for confirmation.

### When to use it

- You trust the agent and want uninterrupted flow
- You are working on a branch with no risk to production code
- You are running a well-defined task like "write specs for all service objects"
- You want the fastest possible turnaround

### When NOT to use it

- You are working on `main` or a shared branch
- The task involves destructive operations (migrations, database changes)
- You are unfamiliar with the codebase and want to review each change

### How to enable

**Via settings:**

1. Open VS Code Settings
2. Search for "Rubyn Code YOLO"
3. Check the box

**Via `settings.json`:**

```json
{
  "rubyn-code.yoloMode": true
}
```

When YOLO mode is active, the status bar indicator reflects the auto-approve state. You can toggle it off at any time to return to the manual approval flow.

---

## Troubleshooting

### Gem not found

**Symptom:** Error message "Failed to start Rubyn Code" or the extension fails to activate.

**Fix:**

1. Verify the gem is installed:
   ```bash
   rubyn-code --version
   ```
2. If using rbenv/rvm, make sure you ran `rubyn-code --setup` to pin the executable:
   ```bash
   RBENV_VERSION=4.0.2 gem install rubyn-code
   RBENV_VERSION=4.0.2 rubyn-code --setup
   ```
3. If the gem is in a non-standard location, set `rubyn-code.executablePath` in VS Code settings to the full path.

### Authentication failure

**Symptom:** The agent starts but cannot make API calls; you see auth errors in the output channel.

**Fix:**

1. Make sure you have authenticated. The easiest method is logging into the Claude CLI once:
   ```bash
   claude
   ```
   This stores an OAuth token in the macOS Keychain that Rubyn Code reads automatically.

2. Alternatively, set an API key:
   ```bash
   export ANTHROPIC_API_KEY=sk-ant-...
   ```

3. Check `~/.rubyn-code/tokens.yml` exists and is readable.

### Process crash

**Symptom:** The chat panel goes unresponsive or you see "[bridge] Connection closed" in the output.

**Fix:**

1. Open the Output panel (`Cmd+Shift+U` / `Ctrl+Shift+U`)
2. Select **Rubyn Code** from the dropdown
3. Look for error messages — they often indicate the root cause
4. Reload the VS Code window (`Cmd+Shift+P` > "Developer: Reload Window")
5. If the crash is reproducible, file an issue with the output channel logs

### Ruby version mismatch

**Symptom:** The gem fails to start with a Ruby version error.

**Fix:**

Rubyn Code requires Ruby 4.0+. Check your version:

```bash
ruby --version
```

If your project uses an older Ruby via `.ruby-version`, that is fine — the `rubyn-code --setup` command creates a launcher that bypasses version managers. Make sure `~/.local/bin` is in your PATH before rbenv/rvm shims.

### Debug output channel

For detailed diagnostic information:

1. Open the Output panel (`Cmd+Shift+U` / `Ctrl+Shift+U`)
2. Select **Rubyn Code** from the channel dropdown
3. The output channel logs:
   - Extension activation status
   - CLI process spawn details
   - Bridge initialization and server version
   - All errors and warnings

You can also run the CLI directly with debug output to isolate issues:

```bash
rubyn-code --debug
```

---

## Development Setup

To build and run the extension from source:

### Clone and install dependencies

```bash
git clone https://github.com/MatthewSuttles/rubyn-code.git
cd rubyn-code/editors/vscode
npm install
```

### Build

```bash
npm run build        # Production build (webpack)
npm run watch        # Development build with file watching
```

### Run in VS Code (F5 debugging)

1. Open the `editors/vscode` folder in VS Code
2. Press `F5` to launch the Extension Development Host
3. A new VS Code window opens with the extension loaded
4. Open a Ruby/Rails project in that window to test

### Lint and test

```bash
npm run lint              # ESLint
npm run test              # Run tests with Vitest
npm run test:watch        # Watch mode
npm run test:coverage     # Coverage report
```

### Package as .vsix

```bash
npm run package    # Creates a .vsix file via vsce
```

The resulting `.vsix` can be installed manually or distributed for testing.
