# 06 `/export` Transcript — Design

## Overview

A single slash command that dumps the current conversation to disk as
either Markdown (default) or JSONL (one JSON object per line, for tooling).
Atomic semantics:

- creates parent directories
- refuses to overwrite without `y/N` confirmation in TTY mode (or
  `--force` for CI / non-TTY)
- bails with a warning when the conversation is empty

## Architecture

```
User: /export path/to/file.md
  │
  ▼
Commands::Export#execute(args, ctx)
  ├── parse_args → {path:, format:, force:}
  ├── messages = ctx.conversation.to_a
  ├── if empty: warning + return
  ├── mkdir_p(File.dirname(path))
  ├── if exists && !force && tty_yes?: info("cancelled") + return
  ├── body = format == 'jsonl' ? render_jsonl : render_markdown
  └── File.write(path, body) + info("Exported N messages to PATH")
```

## Argument parsing

```
/export path/to/file.md                # markdown
/export path/to/file.md --jsonl        # JSONL
/export --format jsonl path/to/file    # same as above
/export path/to/file.md --force        # overwrite existing
```

## Markdown rendering

```
# Rubyn transcript
_Exported at 2026-04-10 14:32:11_

## User

What is in @chart.png?

## Assistant

<details><summary>thinking</summary>

step 1: parse the request
step 2: read the file

</details>

I read the file and saw a chart.

[tool: grep]

```json
{
  "pattern": "ChartPicker"
}
```

## User

thanks

## Assistant
…

### tool result

```
no matches
```
```

- `## User` / `## Assistant` section headings per role
- `_(image attachment)_` placeholder for image blocks
- `<details><summary>thinking</summary>` for thinking content
- `[tool: <name>]` followed by a fenced JSON block for tool_use input
- `### tool result` for `role: 'tool'` messages

## JSONL rendering

```jsonl
{"role":"user","content":"hi","timestamp":"2026-04-10T14:32:11Z"}
{"role":"assistant","content":"[…]","timestamp":"2026-04-10T14:32:11Z"}
```

## Confirm-then-overwrite

```ruby
def tty_yes?(ctx, prompt)
  ctx.renderer.respond_to?(:ask) ? ctx.renderer.ask(prompt, default: false) : true
end
```

`--force` skips even the `default: false` prompt.

## Out-of-scope

- Exporting only the last N turns
- Bundle export (zip + manifest)
- Resume-by-import round-trip
- Compression / encryption