# 06 `/export` Transcript — Tasks

## Phase 0 — Scaffolding

- [x] Branch: `phase-04-export-transcript`

## Phase 1 — Command

- [x] `Commands::Export` inheriting `Commands::Base`
- [x] `command_name` returns `/export`
- [x] `parse_args` accepts `--format`, `--jsonl`, `--markdown`,
      `--force`, `--md`, `-y`
- [x] `parse_args` returns nil when path is missing
- [x] `execute` early-returns on empty conversation
- [x] `execute` creates parent dirs via `FileUtils.mkdir_p`
- [x] `execute` prompts via `Renderer#ask` on TTY overwrite
- [x] `execute` writes the body via `File.write` and prints info line

## Phase 2 — Renderers

- [x] `render_markdown` — `#` heading, timestamp, role sections,
      `<details>` thinking, fenced JSON for tool_use, `### tool result`
- [x] `render_jsonl` — one JSON object per line, content normalization
- [x] `normalize_content` — String → single text block; nil → empty
- [x] `text_of` / `input_of` / `block_type` helpers

## Phase 3 — Tests

- [x] Markdown round-trip (title, sections, thinking, tool_use, messages info)
- [x] JSONL round-trip
- [x] Parent directories created automatically
- [x] Empty conversation refuses with a warning
- [x] Existing file not overwritten without confirmation
- [x] `--force` overrides the confirmation
- [x] Image attachments render as `_(image attachment)_`

## Phase 4 — Lint & Ship

- [x] `bundle exec rubocop -A`
- [x] `bundle exec rspec` (9 examples, 0 failures)
- [x] Conventional commit
- [x] Push branch & open PR (#137)
- [x] PR squash-merged into main