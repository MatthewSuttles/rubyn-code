# LLM Layer

Faraday-based Claude API client with streaming support.

## Classes

- **`Client`** — Sends messages to the Claude API. Handles auth headers (OAuth bearer or API key),
  model selection, system prompts, and tool definitions. Returns parsed response or streams.

- **`Streaming`** — SSE stream parser for Claude's streaming API. Buffers partial events,
  emits content blocks and tool_use blocks as they arrive. Feeds into `CLI::StreamFormatter`.

- **`MessageBuilder`** — Constructs the messages array for the API. Handles system prompt
  injection, tool result formatting, and context window limits. Knows about Claude's
  message format (role/content pairs, tool_use/tool_result blocks).
