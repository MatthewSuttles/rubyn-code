# Phase 4 — Claude Code Feature Parity: Requirements

## Overview

Six small, additive feature gaps that bring rubyn-code to closer parity with
Claude Code's interactive UX. Each ships as its own PR, off-by-default, with
specs and a docs note. None require DB migrations; some touch the LLM adapter
surface.

## Requirements

### R1: Extended thinking / reasoning budget

**User story:** As a user working on a hard reasoning task, I want the model to
spend more time thinking before answering, so that I get higher-quality output
on hard problems.

**Acceptance criteria:**

1. The `LLM::Client#chat` interface SHALL accept a `thinking:` keyword argument
   shaped as `{ budget_tokens: Integer }`.
2. The Anthropic adapter SHALL translate `thinking: {budget_tokens: N}` into
   the Anthropic Messages API `thinking: {type: "enabled", budget_tokens: N}`
   field on the request body. Other adapters SHALL accept and ignore it.
3. When thinking is enabled, `max_tokens` SHALL be raised to be at least
   `budget_tokens + 1024` (Anthropic requirement).
4. A `/think` slash command SHALL toggle thinking on/off per session, with an
   optional integer argument to set the budget. Default budget: 8192 tokens.
5. Thinking state SHALL persist in the REPL context for the lifetime of the
   session. It is NOT persisted across `session/reset` or new REPL launches.
6. A `thinking_budget_tokens` config key SHALL be read at REPL startup as the
   default. Default: 0 (off).
7. Anthropic streaming responses SHALL parse `thinking` content blocks into a
   new `LLM::ThinkingBlock` Data type. The block text SHALL be emitted via
   `on_text` so the REPL can display it with a distinct prefix (e.g. `…`).

### R2: Image / vision input

**User story:** As a user, I want to paste or reference an image in my prompt
(via `@image.png` or a path), so that the model can see it.

**Acceptance criteria:**

1. `LLM::MessageBuilder` SHALL define a new `ImageBlock` Data type
   (`{ source_type, media_type, data, path }`) and a `format_content_blocks`
   branch that emits the Anthropic `image` content-block shape.
2. The Anthropic adapter SHALL accept image content blocks in messages and
   emit them in the request body as
   `{ type: "image", source: { type: "base64", media_type: ..., data: ... } }`.
3. The OpenAI adapter (and `OpenAIMessageTranslator`) SHALL translate image
   blocks into `{ type: "image_url", image_url: { url: "data:...;base64,..." } }`.
4. `CLI::MentionExpander` SHALL recognize `@path/to/image.png` (and `.jpg`,
   `.jpeg`, `.gif`, `.webp`) tokens and expand them into image content blocks
   attached to the user message. The model receives both the file path text and
   the image.
5. Image blocks SHALL never be sent to tool result messages (which can only be
   `text` per the API); they SHALL only appear on user turns.
6. A `read_image(path)` helper SHALL read the file, base64-encode it, detect
   the media type from the extension, and return a Hash suitable for
   `Conversation#add_user_message(content: [...])`.

### R3: TodoWrite live checklist

**User story:** As a user watching the agent work, I want to see a live
checklist of what it's doing right now, so that I can tell at a glance whether
it's making progress.

**Acceptance criteria:**

1. A new tool `TodoWrite` SHALL be registered. Its schema accepts a single
   `todos` array of `{content, status, active_form}` items
   (`status` ∈ `pending|in_progress|completed`).
2. The tool SHALL store the current checklist on the agent loop instance
   (`@todos`) and return a formatted string: lines starting with `[x]` for
   completed, `[~]` for in_progress, `[ ]` for pending, prefixed with the
   `active_form` (or `content`) text.
3. The REPL renderer SHALL display the current checklist above the spinner
   when one exists, refreshing on every TodoWrite call. When todos exist and
   the spinner is active, the checklist is visible in place of (or above) the
   spinner line.
4. The tool result SHALL include the rendered checklist so the model sees what
   it just wrote.
5. The checklist SHALL be cleared when the conversation is reset
   (`/new`, `session/reset`).
6. Each TodoWrite call SHALL fire a `pre_tool_use`/`post_tool_use` hook so
   downstream observers (IDE `tool/result` notifications) see it like any
   other tool.

### R4: Custom-command frontmatter

**User story:** As a user defining custom slash commands, I want to declare
argument hints, allowed tools, and a model override in frontmatter, so that my
custom commands behave like first-class built-ins.

**Acceptance criteria:**

1. `CustomLoader::FRONTMATTER` SHALL be extended to recognize these keys in
   addition to `description`:
   - `argument-hint` (or `argument_hint`) → String
   - `allowed-tools` (or `allowed_tools`) → comma-separated String OR Array
   - `model` → String
2. `CustomCommand` SHALL expose `argument_hint`, `allowed_tools` (Array),
   `model` attributes parsed from frontmatter.
3. When a custom command sets `allowed_tools`, the agent loop SHALL restrict
   the available tool set to exactly those names for the duration of that
   prompt. Built-in tools not in the list SHALL not be callable; the model
   SHALL be told so in the system prompt.
4. When a custom command sets `model`, the loop SHALL temporarily switch the
   `LLM::Client` model for that prompt and restore it after. (The user's
   default model is preserved across the call.)
5. `/help` listing for custom commands SHALL display the argument hint next to
   the name, e.g. `/deploy [env]`.

### R5: `.mcp.json` auto-discovery

**User story:** As a user with MCP servers in my project, I want rubyn-code to
auto-discover `.mcp.json` and connect to them, so that I don't have to
configure them separately.

**Acceptance criteria:**

1. At REPL startup (and on each prompt), the loader SHALL look for
   `.mcp.json` in the project root and parse the top-level `mcpServers` hash.
2. Each entry in `mcpServers` whose config has `command` (stdio transport)
   SHALL be registered with `MCP::Config` and connected on next MCP refresh.
3. HTTP/SSE transports with `url` SHALL be parsed but NOT yet connected (OAuth
   deferred — printed as a one-line warning).
4. The loader SHALL never raise on a malformed `.mcp.json` — it logs a warning
   and continues.
5. The `/mcp` command output SHALL indicate which servers came from
   `.mcp.json` vs the user config, prefixed with `[project]` and `[user]`.

### R6: `/export transcript`

**User story:** As a user, I want to save the current conversation transcript
to a file, so that I can share it, archive it, or import it elsewhere.

**Acceptance criteria:**

1. A new `/export` slash command SHALL be registered.
2. `/export <path>` writes the current conversation to `<path>` as Markdown
   (default). `/export --format jsonl <path>` writes it as JSONL.
3. Markdown format: a `# <session-title>` heading, then alternating
   `## User` and `## Assistant` sections with the message text verbatim.
   Tool calls/responses are rendered as fenced code blocks with a label
   (`[tool: <name>]`).
4. JSONL format: one JSON object per line with keys
   `{role, content, tool_calls?, tool_results?, timestamp}`.
5. The command SHALL respect the path's directory: create parent dirs if
   needed, and overwrite an existing file (with a confirmation prompt in
   TTY mode; force-overwrite in non-TTY).
6. The command SHALL refuse to export an empty conversation and print a
   message.

## Out of scope

- OAuth flow for HTTP/SSE MCP transports (R5)
- Cross-session persistence of `/think` state (R1)
- Edit / undo of past todo states (R3)
- Validation of model names in custom-command frontmatter (R4)
- Export of tool results that contain images or binary data — Markdown falls
  back to a placeholder; JSONL includes base64 only if it was a string
  already (R6)
