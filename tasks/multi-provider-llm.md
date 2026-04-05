# Multi-Provider LLM Architecture

> **Goal:** Let users configure and switch between any LLM provider (Anthropic, OpenAI-compatible, local models) via config + a guided wizard.
>
> **Branch:** `feat/multi-provider-llm`
> **Started:** 2025-07-14
> **Status:** 🟡 In Progress

---

## Phase 1: Foundation — Provider Config & Base Adapter
> Extract the adapter interface and the data object that describes a provider.

- [ ] **1.1** Create `LLM::ProviderConfig` Data.define
  - Fields: `name`, `protocol`, `base_url`, `api_key_env`, `api_key`, `models`, `pricing`, `options`
  - File: `lib/rubyn_code/llm/provider_config.rb`
  - Spec: `spec/rubyn_code/llm/provider_config_spec.rb`

- [ ] **1.2** Create `LLM::BaseAdapter` abstract class
  - Methods: `#chat`, `#stream` (delegates to chat), `#model`, `#model=`
  - Defines shared error classes: `RequestError`, `AuthError`, `PromptTooLongError`
  - Stop reason normalization contract: `'end_turn'`, `'tool_use'`, `'max_tokens'`
  - File: `lib/rubyn_code/llm/base_adapter.rb`
  - Spec: `spec/rubyn_code/llm/base_adapter_spec.rb`

- [ ] **1.3** Create `LLM::ProviderRegistry`
  - Maps protocol names → adapter classes
  - `register(protocol_name, adapter_class)` / `resolve(protocol_name)`
  - Ships with `:anthropic` and `:openai` built-in
  - File: `lib/rubyn_code/llm/provider_registry.rb`
  - Spec: `spec/rubyn_code/llm/provider_registry_spec.rb`

---

## Phase 2: Anthropic Adapter Extraction
> Refactor the current `LLM::Client` into `Adapters::Anthropic` without breaking any existing tests.

- [ ] **2.1** Extract `LLM::Adapters::Anthropic` from current `LLM::Client`
  - Inherits `BaseAdapter`
  - Accepts `ProviderConfig` (or falls back to legacy defaults for backward compat)
  - Parameterize: `base_url`, auth strategy (OAuth/env var/inline key)
  - Keep all Anthropic-specific logic: cache control, system prompt format, headers
  - File: `lib/rubyn_code/llm/adapters/anthropic.rb`
  - Spec: `spec/rubyn_code/llm/adapters/anthropic_spec.rb`

- [ ] **2.2** Move `LLM::Streaming` → `LLM::Adapters::AnthropicStreaming`
  - Rename only — no logic changes
  - Update require/autoload paths
  - File: `lib/rubyn_code/llm/adapters/anthropic_streaming.rb`
  - Spec: `spec/rubyn_code/llm/adapters/anthropic_streaming_spec.rb`

- [ ] **2.3** Make `LLM::Client` a factory module
  - `LLM::Client.new` → returns `Adapters::Anthropic` (backward compat)
  - `LLM::Client.for(provider_config)` → returns the right adapter
  - All existing call sites (`LLM::Client.new`, `@llm_client.chat(...)`) still work
  - File: `lib/rubyn_code/llm/client.rb` (rewrite)
  - Spec: `spec/rubyn_code/llm/client_spec.rb` (update)

- [ ] **2.4** Run full spec suite — everything must pass unchanged
  - `bundle exec rspec`
  - `bundle exec rubocop`
  - Zero regressions. This is a pure refactor.

---

## Phase 3: OpenAI-Compatible Adapter
> Add support for OpenAI Chat Completions API (covers OpenAI, Groq, Together, Ollama, vLLM, LM Studio, Azure OpenAI, Minimax OpenAI endpoint).

- [ ] **3.1** Create `LLM::Adapters::OpenAI`
  - Inherits `BaseAdapter`
  - Translates internal message format → OpenAI format (system as role:system, tool_result as role:tool)
  - Translates OpenAI response → `Response`, `TextBlock`, `ToolUseBlock`
  - Normalizes stop reasons: `stop` → `'end_turn'`, `tool_calls` → `'tool_use'`, `length` → `'max_tokens'`
  - Auth: reads from `api_key_env`, `api_key`, or skips (local models)
  - Configurable `base_url`
  - File: `lib/rubyn_code/llm/adapters/openai.rb`
  - Spec: `spec/rubyn_code/llm/adapters/openai_spec.rb`

- [ ] **3.2** Create `LLM::Adapters::OpenAIStreaming`
  - Parses OpenAI SSE format (`data: {"choices":[{"delta":...}]}`)
  - Emits same `on_text` callbacks as Anthropic streaming
  - Assembles tool call chunks into `ToolUseBlock`
  - Handles `[DONE]` sentinel
  - File: `lib/rubyn_code/llm/adapters/openai_streaming.rb`
  - Spec: `spec/rubyn_code/llm/adapters/openai_streaming_spec.rb`

- [ ] **3.3** Register OpenAI adapter in `ProviderRegistry`
  - `registry.register('openai', Adapters::OpenAI)`

- [ ] **3.4** Integration test: OpenAI adapter with mocked HTTP
  - Test: chat, streaming, tool calls, error handling, stop reason normalization
  - Verify `Response` objects are identical in shape to Anthropic ones

---

## Phase 4: Config & Provider Loading
> Wire provider definitions into the config system so users can declare providers in YAML.

- [ ] **4.1** Extend `Config::Settings` to load `providers:` section
  - Parse provider hash → array of `ProviderConfig` objects
  - `settings.providers` returns `{ 'name' => ProviderConfig }`
  - `settings.default_provider` returns the name string
  - Backward compat: if no `providers:` key, synthesize a default Anthropic provider

- [ ] **4.2** Extend `Config::ProjectConfig` to support per-project provider overrides
  - Project config can override `default_provider`
  - Project config can add project-scoped providers

- [ ] **4.3** Update `REPL#setup_core_services!` to use provider config
  - Resolve default provider → `ProviderConfig` → `LLM::Client.for(config)`
  - Pass provider info to renderer for display

- [ ] **4.4** Update `DaemonRunner` to use provider config
  - Same pattern as REPL

---

## Phase 5: `/model` Command & Provider Switching
> Update the model command to be provider-aware, add `/provider` command.

- [ ] **5.1** Rewrite `Commands::Model`
  - `/model` → shows `provider/model` (e.g., `anthropic/claude-sonnet-4-20250514`)
  - `/model <model>` → auto-detects provider from configured models
  - `/model <provider>/<model>` → explicit provider + model switch
  - Dynamic model list from config (no more hardcoded `KNOWN_MODELS`)
  - Returns `{ action: :set_model, provider: '...', model: '...' }` action hash
  - Spec updates

- [ ] **5.2** Update `REPL#handle_command_result` for provider switching
  - Handle new `:set_model` action that includes `:provider`
  - Swap `@llm_client` to a new adapter instance when provider changes
  - Update `@tool_executor.llm_client` reference

- [ ] **5.3** (Optional) Add `/provider` slash command
  - `/provider` → list configured providers with their models
  - `/provider <name>` → switch to provider (keep current model logic)
  - Lighter-weight than `/model` for quick switching

---

## Phase 6: Cost Calculator & Pricing Registry
> Make cost tracking work across providers.

- [ ] **6.1** Extend `Observability::CostCalculator` to support custom pricing
  - Load pricing from config (`settings.get('pricing')`)
  - Merge with built-in Anthropic pricing
  - Unknown models → zero cost (local models are free, unknown pricing is better than wrong pricing)
  - Fall back to provider-level pricing if model-specific isn't available

- [ ] **6.2** Update `Hooks::BuiltIn::CostTrackingHook`
  - Pass provider name through to cost records for reporting

- [ ] **6.3** Update `/cost` command
  - Show costs grouped by provider

---

## Phase 7: The Provider Wizard (`--add-provider`)
> Interactive CLI wizard to configure a new provider.

- [ ] **7.1** Create `CLI::ProviderWizard`
  - TTY::Prompt-based interactive flow
  - Steps: name → protocol → base_url → auth → models → pricing → test → save
  - Connection test via `LLM::Client.for(config).chat(...)` with a trivial prompt
  - Error recovery: edit URL, edit auth, save anyway, or abort
  - Writes to `~/.rubyn-code/config.yml` via `Config::Settings`
  - File: `lib/rubyn_code/cli/provider_wizard.rb`
  - Spec: `spec/rubyn_code/cli/provider_wizard_spec.rb`

- [ ] **7.2** Wire `--add-provider` into `CLI::App`
  - Add to `SIMPLE_FLAGS`
  - Add `dispatch_command` case
  - Update `HELP_TEXT`

- [ ] **7.3** Add `--list-providers` flag
  - Quick dump: name, protocol, base_url, model count
  - File: reuse ProviderWizard or standalone

- [ ] **7.4** Add `--remove-provider <name>` flag
  - Confirmation prompt
  - Removes from config, saves
  - Refuses to remove the default provider without switching first

- [ ] **7.5** Add `--provider <name>` flag for REPL startup
  - `rubyn-code --provider ollama` → starts REPL with that provider
  - Pass through to REPL constructor

---

## Phase 8: Documentation & Polish

- [ ] **8.1** Update `RUBYN.md` with multi-provider architecture
- [ ] **8.2** Create `lib/rubyn_code/llm/RUBYN.md` with adapter docs
- [ ] **8.3** Update `Commands::Doctor` to check all configured providers
- [ ] **8.4** Update `ensure_auth!` to be provider-aware (some providers don't need auth)
- [ ] **8.5** Final spec suite pass + RuboCop clean

---

## Decision Log

| Date | Decision | Rationale |
|------|----------|-----------|
| 2025-07-14 | Two protocols only: `anthropic` and `openai` | Covers ~95% of LLM providers. Others can be added later. |
| 2025-07-14 | Normalize stop reasons to Anthropic strings | Agent::Loop already uses these. Less blast radius. |
| 2025-07-14 | `LLM::Client.new` stays backward-compatible | Zero-breakage refactor. Existing code doesn't change. |
| 2025-07-14 | Unknown model pricing → zero cost | Better than wrong pricing. Local models are free anyway. |
| 2025-07-14 | Provider config in YAML, not DB | Config is portable, version-controllable, human-editable. |
| 2025-07-14 | Wizard uses TTY::Prompt | Already a dependency. Native select/mask/validation. |

---

## Notes

- The `MessageBuilder` stays shared — it builds the internal format. Each adapter translates to its wire format.
- OAuth flow remains Anthropic-only. Other providers use API keys.
- The `OAUTH_GATE` and `RUBYN_IDENTITY` stay in the Anthropic adapter only.
- Streaming is opt-in per adapter. If an adapter doesn't support streaming, it falls back to non-streaming with `emit_full_text`.
- Sub-agents and teammates inherit the current provider from the parent REPL.
