# Extending Rubyn Code

This guide covers how to extend Rubyn Code with new tools, slash commands, LLM
adapters, MCP servers, skills, and hooks.

---

## Adding a New Tool

Tools are the primary way the LLM interacts with the outside world. Each tool
inherits from `Tools::Base`, defines a schema, and implements an `execute` method.

### Step 1: Create the tool file

Create `lib/rubyn_code/tools/my_tool.rb`:

```ruby
# frozen_string_literal: true

require_relative 'base'
require_relative 'registry'

module RubynCode
  module Tools
    class MyTool < Base
      TOOL_NAME = 'my_tool'
      DESCRIPTION = 'One-line description of what this tool does'
      PARAMETERS = {
        input: {
          type: :string,
          required: true,
          description: 'The input to process'
        },
        format: {
          type: :string,
          required: false,
          description: 'Output format (json or text)'
        }
      }.freeze
      RISK_LEVEL = :read     # :read, :write, or :external
      REQUIRES_CONFIRMATION = false  # true to prompt user before execution

      def execute(input:, format: 'text')
        # Your implementation here.
        # Use safe_path(path) for file paths to prevent traversal.
        # Use safe_capture3(*cmd) for shell commands.
        # Use truncate(output) for large outputs.
        # Always return a string.

        result = process(input)

        case format
        when 'json'
          JSON.pretty_generate(result)
        else
          result.to_s
        end
      end

      private

      def process(input)
        # implementation
      end
    end

    Registry.register(MyTool)
  end
end
```

### Step 2: Add the autoload entry

In `lib/rubyn_code.rb`, add under the `module Tools` section:

```ruby
autoload :MyTool, 'rubyn_code/tools/my_tool'
```

### Step 3: Add a spec

Create `spec/rubyn_code/tools/my_tool_spec.rb`:

```ruby
# frozen_string_literal: true

require 'spec_helper'

RSpec.describe RubynCode::Tools::MyTool do
  let(:tool) { described_class.new(project_root: Dir.pwd) }

  describe '.tool_name' do
    it 'returns the tool name' do
      expect(described_class.tool_name).to eq('my_tool')
    end
  end

  describe '#execute' do
    it 'processes input and returns a result' do
      result = tool.execute(input: 'hello')
      expect(result).to be_a(String)
    end
  end
end
```

### Key Patterns

- **`safe_path(path)`** -- Resolves a path relative to the project root and
  prevents path traversal. Always use this for file operations.
- **`safe_capture3(*cmd)`** -- Safe replacement for `Open3.capture3` that handles
  Ruby 4.0's IOError race condition on stream closure. Use this for all shell
  commands.
- **`truncate(output, max: 10_000)`** -- Truncates large outputs to keep context
  manageable. Keeps the first and last half, inserts a truncation marker.
- **`RISK_LEVEL`** -- Controls which permission tier is required: `:read` (lowest),
  `:write` (requires edit permissions), `:external` (requires admin/explicit
  approval).
- **`Registry.register(MyTool)`** -- Self-registration at the bottom of the file.
  Called when the file is loaded.

---

## Adding a New Slash Command

Slash commands are handled locally by the CLI -- they never hit the LLM. Each
command inherits from `Commands::Base`.

### Step 1: Create the command file

Create `lib/rubyn_code/cli/commands/my_command.rb`:

```ruby
# frozen_string_literal: true

module RubynCode
  module CLI
    module Commands
      class MyCommand < Base
        class << self
          def command_name
            '/mycommand'
          end

          def description
            'One-line description shown in /help'
          end

          # Optional: additional names that trigger this command
          def aliases
            ['/mc']
          end

          # Optional: hide from /help listing
          # def hidden?
          #   true
          # end
        end

        # @param args [Array<String>] arguments passed after the command name
        # @param ctx [Commands::Context] shared context with REPL dependencies
        def execute(args, ctx)
          # ctx provides access to REPL dependencies:
          #   ctx.formatter    - Output::Formatter for terminal output
          #   ctx.agent_loop   - Agent::Loop instance
          #   ctx.conversation - Agent::Conversation instance
          #   ctx.session_id   - Current session ID

          ctx.formatter.info("MyCommand executed with args: #{args}")

          # Optional: return an action hash to change REPL state
          # { action: :set_plan_mode, enabled: true }
        end
      end
    end
  end
end
```

### Step 2: Add the autoload entry

In `lib/rubyn_code.rb`, add under the `module Commands` section:

```ruby
autoload :MyCommand, 'rubyn_code/cli/commands/my_command'
```

### Step 3: Register in the REPL

In `lib/rubyn_code/cli/repl.rb`, add to the `setup_command_registry!` method:

```ruby
registry.register(Commands::MyCommand)
```

### Step 4: Add a spec

Create `spec/rubyn_code/cli/commands/my_command_spec.rb`:

```ruby
# frozen_string_literal: true

require 'spec_helper'

RSpec.describe RubynCode::CLI::Commands::MyCommand do
  describe '.command_name' do
    it 'returns the command name' do
      expect(described_class.command_name).to eq('/mycommand')
    end
  end

  describe '#execute' do
    it 'executes without error' do
      ctx = instance_double(RubynCode::CLI::Commands::Context,
                            formatter: instance_double(RubynCode::Output::Formatter, info: nil))
      command = described_class.new
      expect { command.execute([], ctx) }.not_to raise_error
    end
  end
end
```

### Action Hashes

Commands can return action hashes to signal REPL state changes:

```ruby
# Toggle plan mode
{ action: :set_plan_mode, enabled: true }

# Switch model
{ action: :set_model, model: 'claude-sonnet-4-6' }

# Set budget
{ action: :set_budget, amount: 5.0 }
```

The REPL processes these action hashes after the command returns.

---

## Adding a New LLM Adapter

LLM adapters enable Rubyn Code to work with different AI providers. All adapters
implement the same interface and return normalized response types.

### Step 1: Create the adapter file

Create `lib/rubyn_code/llm/adapters/my_provider.rb`:

```ruby
# frozen_string_literal: true

require_relative '../message_builder'

module RubynCode
  module LLM
    module Adapters
      class MyProvider < Base
        def initialize(api_key:, base_url: 'https://api.myprovider.com')
          @api_key = api_key
          @base_url = base_url
          @conn = build_connection
        end

        # @param messages [Array<Hash>] Conversation messages
        # @param model [String] Model identifier
        # @param max_tokens [Integer] Max output tokens
        # @param tools [Array<Hash>, nil] Tool schemas
        # @param system [String, nil] System prompt text
        # @param on_text [Proc, nil] Streaming text callback
        # @param task_budget [Hash, nil] Optional task budget context
        # @return [LLM::Response]
        def chat(messages:, model:, max_tokens:, tools: nil,
                 system: nil, on_text: nil, task_budget: nil)
          # 1. Build the request payload for your provider's API
          payload = build_payload(messages, model, max_tokens, tools, system)

          # 2. Make the API call
          raw_response = @conn.post('/v1/chat', payload.to_json)

          # 3. Parse and normalize the response
          parse_response(raw_response)
        end

        def provider_name
          'myprovider'
        end

        def models
          %w[myprovider-small myprovider-large]
        end

        private

        def build_connection
          Faraday.new(url: @base_url) do |f|
            f.request :json
            f.response :json
            f.adapter Faraday.default_adapter
          end
        end

        def build_payload(messages, model, max_tokens, tools, system)
          # Convert to your provider's format
          { model: model, messages: messages, max_tokens: max_tokens }
        end

        def parse_response(raw)
          # Normalize to LLM::Response
          # IMPORTANT: All adapters MUST return these types:
          content = [TextBlock.new(type: 'text', text: raw['choices'][0]['content'])]
          usage = Usage.new(
            input_tokens: raw['usage']['prompt_tokens'],
            output_tokens: raw['usage']['completion_tokens']
          )

          Response.new(
            id: raw['id'],
            model: raw['model'],
            content: content,
            stop_reason: normalize_stop_reason(raw['finish_reason']),
            usage: usage
          )
        end

        # Stop reasons MUST be normalized to these values:
        #   'end_turn'   - normal completion
        #   'tool_use'   - model wants to call a tool
        #   'max_tokens' - output truncated
        def normalize_stop_reason(reason)
          case reason
          when 'stop' then 'end_turn'
          when 'tool_calls' then 'tool_use'
          when 'length' then 'max_tokens'
          else reason
          end
        end
      end
    end
  end
end
```

### Step 2: Add the autoload entry

In `lib/rubyn_code.rb`, add under the `module Adapters` section:

```ruby
autoload :MyProvider, 'rubyn_code/llm/adapters/my_provider'
```

### Step 3: Add a spec with shared examples

Create `spec/rubyn_code/llm/adapters/my_provider_spec.rb`:

```ruby
# frozen_string_literal: true

require 'spec_helper'

RSpec.describe RubynCode::LLM::Adapters::MyProvider do
  it_behaves_like 'an LLM adapter'

  # Provider-specific tests...
end
```

The `it_behaves_like 'an LLM adapter'` shared example (in
`spec/rubyn_code/llm/adapters/shared_examples.rb`) verifies:
- `#chat` returns an `LLM::Response`
- Response contains `TextBlock` and/or `ToolUseBlock` content
- `Usage` has `input_tokens` and `output_tokens`
- Stop reasons are normalized to `end_turn`, `tool_use`, or `max_tokens`
- `#provider_name` returns a string
- `#models` returns an array of strings

### Key Requirements

- **Normalized types:** All adapters must return `LLM::Response`, `TextBlock`,
  `ToolUseBlock`, and `Usage` (defined as `Data.define` objects in
  `message_builder.rb`). Any file referencing these types needs
  `require_relative '../message_builder'`.
- **Stop reason normalization:** Map provider-specific stop reasons to `end_turn`,
  `tool_use`, or `max_tokens`.
- **Tool schema format:** Anthropic uses `input_schema` directly. OpenAI wraps in
  `{ type: "function", function: { parameters: ... } }`. If your provider follows
  OpenAI's format, consider inheriting from `Adapters::OpenAI` or
  `Adapters::OpenAICompatible`.

---

## Adding a New MCP Server

MCP (Model Context Protocol) servers extend the tool set dynamically. Rubyn Code
acts as an MCP client, connecting to external tool servers.

### Configuration

MCP servers are configured in `.rubyn-code/mcp.json`:

```json
{
  "mcpServers": {
    "my-server": {
      "command": "npx",
      "args": ["-y", "@myorg/mcp-server"],
      "env": {
        "API_KEY": "${MY_API_KEY}"
      }
    },
    "remote-server": {
      "url": "https://mcp.example.com/sse",
      "headers": {
        "Authorization": "Bearer ${MCP_TOKEN}"
      }
    }
  }
}
```

### Transport Types

- **Stdio:** Launches a subprocess and communicates via stdin/stdout with
  newline-delimited JSON-RPC. Configured with `command` and `args`.
- **SSE:** Connects to an HTTP Server-Sent Events endpoint. Configured with `url`
  and optional `headers`.

### Environment Variable Interpolation

Config values support `${VAR}` syntax for environment variable interpolation. This
keeps secrets out of the config file.

### How MCP Tools Appear

When an MCP server is configured, `MCP::ToolBridge` dynamically creates
`Tools::Base` subclasses for each tool the server exposes. These tools:

- Are prefixed with `mcp_` (e.g., `mcp_search_docs`)
- Have risk level `:external`
- Are registered in `Tools::Registry` like any built-in tool
- Delegate `execute` calls to the MCP client

The LLM can use MCP tools exactly like built-in tools -- no special handling
is needed.

For full MCP documentation, see the MCP layer RUBYN.md at
`lib/rubyn_code/mcp/RUBYN.md`.

---

## Adding Custom Skills

Skills are the simplest extension point -- just drop a markdown file in the right
directory.

### Project Skills

Create `.rubyn-code/skills/my-skill.md` in your project root:

```markdown
---
name: my-skill
description: Description for skill listings
tags: [relevant, tags]
---

# Skill Title

Content that will be injected into the LLM context when this skill is loaded.
Include patterns, code examples, and best practices.
```

The skill is immediately discoverable. Load it with `/skill my-skill` or let the
agent load it when relevant.

### Global Skills

Create `~/.rubyn-code/skills/my-skill.md` for skills available across all projects.

For the complete skills authoring guide, see [SKILLS.md](SKILLS.md).

---

## Adding Custom Hooks

Hooks let you control and observe agent behavior through event-driven callbacks.

### YAML Hooks (Declarative)

Create `.rubyn-code/hooks.yml` in your project root:

```yaml
pre_tool_use:
  - tool: bash
    match: "dangerous-command"
    action: deny
    reason: "This command is blocked by project policy"

post_tool_use:
  - tool: write_file
    action: log
```

Or create `~/.rubyn-code/hooks.yml` for global hooks.

### Programmatic Hooks

For more complex logic, register hooks programmatically:

```ruby
registry = RubynCode::Hooks::Registry.new

# Deny hook with custom logic
registry.on(:pre_tool_use, priority: 20) do |tool_name:, tool_input:, **|
  if tool_name == 'bash' && tool_input[:command]&.match?(/sudo/)
    { deny: true, reason: 'sudo commands require manual execution' }
  end
end

# Output transformation pipeline
registry.on(:post_tool_use, priority: 60) do |tool_name:, result:, **|
  if tool_name == 'read_file' && result.length > 5000
    result[0..5000] + "\n[output truncated by custom hook]"
  else
    result
  end
end
```

For the complete hooks reference, see [HOOKS.md](HOOKS.md).

---

## Extension Points Summary

| What | Where | Complexity | Requires Code? |
|------|-------|------------|----------------|
| Custom skill | `.rubyn-code/skills/*.md` | Low | No |
| YAML hook | `.rubyn-code/hooks.yml` | Low | No |
| MCP server | `.rubyn-code/mcp.json` | Low | No (config only) |
| New tool | `lib/rubyn_code/tools/*.rb` | Medium | Yes |
| New slash command | `lib/rubyn_code/cli/commands/*.rb` | Medium | Yes |
| New LLM adapter | `lib/rubyn_code/llm/adapters/*.rb` | High | Yes |
| Programmatic hook | Ruby code with `Registry#on` | Medium | Yes |
