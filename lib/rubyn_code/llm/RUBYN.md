# LLM Layer

Provider-neutral LLM facade with Anthropic and OpenAI-compatible adapters.

## Classes

- **`Client`** — Resolves a provider-specific adapter and exposes one chat/stream contract to
  the agent loop. Built-in Anthropic and OpenAI providers coexist with configured compatible
  endpoints such as MiniMax, Groq, Ollama, or vLLM.

- **`AnthropicStreaming` / `OpenAIStreaming`** — Provider-specific SSE parsers that normalize
  text, tool use, stop reasons, and usage into the shared response objects.

- **`MessageBuilder`** — Constructs the messages array for the API. Handles system prompt
  injection, tool result formatting, and context window limits. Knows about Claude's
  internal message format. Wire-format translation belongs to each adapter.

Codex subscription execution is intentionally not an LLM adapter. Hosts embed the official
Codex app server so ChatGPT OAuth, token refresh, model discovery, and the Codex agent lifecycle
remain owned by Codex.
