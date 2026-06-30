# Phase 4 — Claude Code Feature Parity: Tasks

This umbrella task list rolls up the six per-feature task lists. Each
shipped PR carries its own `docs/04-feature-parity/NN-slug/tasks.md`
with the granular checklist.

## Phase 0 — Plan

- [x] Decide parity gap set (6)
- [x] Branching convention: `phase-NN-slug` per gap
- [x] Doc convention: `docs/04-feature-parity/NN-slug/{requirements,design,tasks}.md`

## Phase 1 — Six feature branches

### 01 Extended thinking + `/think`

- [x] Branch: `phase-04-extended-thinking`
- [x] `LLM::ThinkingBlock` (`Data.define(:text)`)
- [x] `MessageBuilder#format_messages` branch for ThinkingBlock
- [x] `LLM::Client` `thinking:` kwarg; `attr_accessor :thinking_budget_tokens`
- [x] `Adapters::Anthropic#build_request_body` translates to
      `{thinking: {type: 'enabled', budget_tokens}}` and bumps
      `max_tokens` to `budget_tokens + 1024`
- [x] `AnthropicStreaming` parses `thinking` blocks + emits
      `thinking_delta` events
- [x] Config key `thinking_budget_tokens` (Defaults + Settings + schema)
- [x] `Commands::Think` slash command (`/think <budget>` / `off`)
- [x] Specs (23 examples): streaming, request body, command parser

### 02 Image / vision input

- [x] Branch: `phase-04-image-input`
- [x] `LLM::ImageBlock` (`Data.define(:media_type, :data)`)
- [x] `LLM::ImageReader.for_path` / `data_uri` / `image_extension?`
- [x] `MentionExpander#expand_images` returns Array of ImageBlocks
- [x] `Agent::Loop#send_message(user_input, blocks:)`
- [x] `Adapters::OpenAIMessageTranslator#translate_user_content_with_images`
- [x] REPL `🖼  Attached images: N` log
- [x] Specs (14 examples): ImageReader, MentionExpander, OpenAI translator

### 03 TodoWrite live checklist

- [x] Branch: `phase-04-todo-tool`
- [x] `Tools::TodoStore` (MonitorMixin) with `Item` Data type
- [x] `Tools::TodoWrite` registered in `Tools::Registry`
- [x] Status validation: `pending|in_progress|completed`
- [x] `Tools::Executor#build_tool` injects `@store` via constructor
- [x] `Agent::Loop` owns the store, exposes `attr_reader`
- [x] `REPL#render_todo_checklist` prints above the spinner
- [x] Specs (16 examples): store thread-safety, tool parser, summaries

### 04 Custom-command frontmatter

- [x] Branch: `phase-04-cmd-frontmatter`
- [x] `CustomLoader.parse` returns `{meta, body}` shape
- [x] `stringify` / `blank_to_nil` / `list_of_tools` helpers
- [x] CustomCommand recognizes hyphen AND underscore keys
- [x] `help_label` renders hint inline
- [x] Specs (17 examples): YAML formats, parse errors, dispatch
- [x] **Gap-close PR #138**: `Agent::Loop#allowed_tools_override=`,
      `#model_override=`; `build_llm_opts` honors both; reset on
      iteration end; `Context#with_*` hooks drive the overrides

### 05 `.mcp.json` auto-discovery

- [x] Branch: `phase-05-mcp-discovery`
- [x] `MCP::Discovery::Entry` Data.define
- [x] `load_project` parses `.mcp.json` (rescue ParserError /
      SystemCallError — never raises)
- [x] `stdio_servers` / `remote_servers` classifiers
- [x] Specs (8 examples): stdio, url, malformed, source merging
- [x] **Gap-close PR #138**: `REPL#setup_mcp_servers!` switched from
      `MCP::Config.load` to `MCP::Discovery.discover`
- [x] **Gap-close PR #139**: `/mcp` calls Discovery, renders
      `[project]` / `[user]` source tags

### 06 `/export` transcript

- [x] Branch: `phase-04-export-transcript`
- [x] `Commands::Export` argument parser (`--format`, `--jsonl`,
      `--markdown`, `--force`)
- [x] Markdown renderer: title, timestamps, role sections,
      `<details>` thinking, fenced JSON `tool_use`
- [x] JSONL renderer: one JSON object per line
- [x] Parent directories created; overwrite confirms (TTY) or
      `--force`
- [x] Specs (9 examples): md, jsonl, empty, force, parent dirs

## Phase 2 — Audit-discovered sub-gaps

- [x] **PR #138** — wire `allowed-tools` / `model` overrides
- [x] **PR #139** — `/mcp` source tags
- [x] **PR #140** — `ImageReader` autoloads `ImageBlock`
- [x] **PR #141** — autoload all content blocks in `lib/rubyn_code.rb`;
      `ImageReader` self-requires `base64`
- [x] **Smoke + wireformat tests**: `spec/rubyn_code/parity_smoke_spec.rb`
      (16 examples, all six gaps), `spec/rubyn_code/llm/parity_wireformat_spec.rb`
      (3 examples, WebMock integration)

## Phase 3 — Lint + ship

- [x] Every PR passes `bundle exec rubocop -A` and `bundle exec rspec`
- [x] Conventional commit subject + `Co-authored-by: Rubyn` trailer
- [x] All ten PRs squash-merged onto `main`
- [x] Per-PR docs (`design.md`, `tasks.md`) live under
      `docs/04-feature-parity/NN-slug/`

## Final tally

- 6 plan-item PRs (#132 – #137)
- 4 audit-discovered gap-close PRs (#138 – #141)
- ~150 RSpec examples across touched files, all green
