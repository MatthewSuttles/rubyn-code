# frozen_string_literal: true

require_relative 'rubyn_code/version'
require_relative 'rubyn_code/debug'

module RubynCode
  class Error < StandardError; end
  class AuthenticationError < Error; end
  class BudgetExceededError < Error; end
  class PermissionDeniedError < Error; end
  class StallDetectedError < Error; end
  class ToolNotFoundError < Error; end
  class ConfigError < Error; end
  # Raised when the user refuses a tool invocation in IDE mode. Signals the
  # agent loop to surface this as is_error: true so the model sees a refusal
  # rather than a successful tool call returning a string like "denied".
  class UserDeniedError < Error; end

  # Infrastructure
  autoload :Config, 'rubyn_code/config/settings'

  module Config
    autoload :ProjectProfile, 'rubyn_code/config/project_profile'
  end

  # Database
  module DB
    autoload :Connection, 'rubyn_code/db/connection'
    autoload :Migrator, 'rubyn_code/db/migrator'
    autoload :Schema, 'rubyn_code/db/schema'
  end

  # Auth
  module Auth
    autoload :OAuth, 'rubyn_code/auth/oauth'
    autoload :KeyEncryption, 'rubyn_code/auth/key_encryption'
    autoload :TokenStore, 'rubyn_code/auth/token_store'
    autoload :Server, 'rubyn_code/auth/server'
  end

  # LLM
  module LLM
    autoload :Client, 'rubyn_code/llm/client'
    autoload :MessageBuilder, 'rubyn_code/llm/message_builder'
    autoload :ModelRouter, 'rubyn_code/llm/model_router'

    # Adapters (provider-specific implementations)
    module Adapters
      autoload :Base, 'rubyn_code/llm/adapters/base'
      autoload :JsonParsing, 'rubyn_code/llm/adapters/json_parsing'
      autoload :PromptCaching, 'rubyn_code/llm/adapters/prompt_caching'
      autoload :Anthropic, 'rubyn_code/llm/adapters/anthropic'
      autoload :AnthropicCompatible, 'rubyn_code/llm/adapters/anthropic_compatible'
      autoload :AnthropicStreaming, 'rubyn_code/llm/adapters/anthropic_streaming'
      autoload :OpenAI, 'rubyn_code/llm/adapters/openai'
      autoload :OpenAIStreaming, 'rubyn_code/llm/adapters/openai_streaming'
      autoload :OpenAICompatible, 'rubyn_code/llm/adapters/openai_compatible'
      autoload :OpenAIMessageTranslator, 'rubyn_code/llm/adapters/openai_message_translator'
    end

    # Backward-compat: LLM::Streaming → Adapters::AnthropicStreaming
    autoload :Streaming, 'rubyn_code/llm/streaming'
  end

  # Layer 1: Agent Loop
  module Agent
    autoload :Loop, 'rubyn_code/agent/loop'
    autoload :LoopDetector, 'rubyn_code/agent/loop_detector'
    autoload :Conversation, 'rubyn_code/agent/conversation'
    autoload :ResponseModes, 'rubyn_code/agent/response_modes'
    autoload :DynamicToolSchema, 'rubyn_code/agent/dynamic_tool_schema'
  end

  # Layer 2: Tool System
  module Tools
    autoload :Base, 'rubyn_code/tools/base'
    autoload :Registry, 'rubyn_code/tools/registry'
    autoload :Schema, 'rubyn_code/tools/schema'
    autoload :Executor, 'rubyn_code/tools/executor'
    autoload :ReadFile, 'rubyn_code/tools/read_file'
    autoload :WriteFile, 'rubyn_code/tools/write_file'
    autoload :EditFile, 'rubyn_code/tools/edit_file'
    autoload :Glob, 'rubyn_code/tools/glob'
    autoload :Grep, 'rubyn_code/tools/grep'
    autoload :Bash, 'rubyn_code/tools/bash'
    autoload :RailsGenerate, 'rubyn_code/tools/rails_generate'
    autoload :DbMigrate, 'rubyn_code/tools/db_migrate'
    autoload :RunSpecs, 'rubyn_code/tools/run_specs'
    autoload :BundleInstall, 'rubyn_code/tools/bundle_install'
    autoload :BundleAdd, 'rubyn_code/tools/bundle_add'
    autoload :Compact, 'rubyn_code/tools/compact'
    autoload :LoadSkill, 'rubyn_code/tools/load_skill'
    autoload :Task, 'rubyn_code/tools/task'
    autoload :MemorySearch, 'rubyn_code/tools/memory_search'
    autoload :MemoryWrite, 'rubyn_code/tools/memory_write'
    autoload :SendMessage, 'rubyn_code/tools/send_message'
    autoload :ReadInbox, 'rubyn_code/tools/read_inbox'
    autoload :ReviewPr, 'rubyn_code/tools/review_pr'
    autoload :SpawnAgent, 'rubyn_code/tools/spawn_agent'
    autoload :BackgroundRun, 'rubyn_code/tools/background_run'
    autoload :WebSearch, 'rubyn_code/tools/web_search'
    autoload :WebFetch, 'rubyn_code/tools/web_fetch'
    autoload :AskUser, 'rubyn_code/tools/ask_user'
    autoload :GitCommit, 'rubyn_code/tools/git_commit'
    autoload :GitDiff, 'rubyn_code/tools/git_diff'
    autoload :GitLog, 'rubyn_code/tools/git_log'
    autoload :GitStatus, 'rubyn_code/tools/git_status'
    autoload :SpawnTeammate, 'rubyn_code/tools/spawn_teammate'
    autoload :OutputCompressor, 'rubyn_code/tools/output_compressor'
    autoload :FileCache, 'rubyn_code/tools/file_cache'
    autoload :SpecOutputParser, 'rubyn_code/tools/spec_output_parser'
  end

  # Layer 3: Permissions
  module Permissions
    autoload :Tier, 'rubyn_code/permissions/tier'
    autoload :Policy, 'rubyn_code/permissions/policy'
    autoload :DenyList, 'rubyn_code/permissions/deny_list'
    autoload :Prompter, 'rubyn_code/permissions/prompter'
  end

  # Layer 4: Context Management
  module Context
    autoload :Manager, 'rubyn_code/context/manager'
    autoload :Compactor, 'rubyn_code/context/compactor'
    autoload :MicroCompact, 'rubyn_code/context/micro_compact'
    autoload :AutoCompact, 'rubyn_code/context/auto_compact'
    autoload :ManualCompact, 'rubyn_code/context/manual_compact'
    autoload :ContextCollapse, 'rubyn_code/context/context_collapse'
    autoload :ContextBudget, 'rubyn_code/context/context_budget'
    autoload :SchemaFilter, 'rubyn_code/context/schema_filter'
    autoload :DecisionCompactor, 'rubyn_code/context/decision_compactor'
  end

  # Layer 5: Skills
  module Skills
    autoload :Loader, 'rubyn_code/skills/loader'
    autoload :Catalog, 'rubyn_code/skills/catalog'
    autoload :Document, 'rubyn_code/skills/document'
    autoload :TtlManager, 'rubyn_code/skills/ttl_manager'
    autoload :RegistryClient, 'rubyn_code/skills/registry_client'
    autoload :PackManager, 'rubyn_code/skills/pack_manager'
    autoload :RegistryError, 'rubyn_code/skills/registry_client'
  end

  # Layer 6: Sub-Agents
  module SubAgents
    autoload :Runner, 'rubyn_code/sub_agents/runner'
    autoload :Summarizer, 'rubyn_code/sub_agents/summarizer'
  end

  # Layer 7: Tasks
  module Tasks
    autoload :Manager, 'rubyn_code/tasks/manager'
    autoload :DAG, 'rubyn_code/tasks/dag'
    autoload :Models, 'rubyn_code/tasks/models'
  end

  # Layer 8: Background
  module Background
    autoload :Worker, 'rubyn_code/background/worker'
    autoload :Job, 'rubyn_code/background/job'
    autoload :Notifier, 'rubyn_code/background/notifier'
  end

  # Layer 9: Teams
  module Teams
    autoload :Manager, 'rubyn_code/teams/manager'
    autoload :Mailbox, 'rubyn_code/teams/mailbox'
    autoload :Teammate, 'rubyn_code/teams/teammate'
  end

  # Layer 10: Protocols
  module Protocols
    autoload :ShutdownHandshake, 'rubyn_code/protocols/shutdown_handshake'
    autoload :PlanApproval, 'rubyn_code/protocols/plan_approval'
    autoload :InterruptHandler, 'rubyn_code/protocols/interrupt_handler'
  end

  # Layer 11: Autonomous
  module Autonomous
    autoload :Daemon, 'rubyn_code/autonomous/daemon'
    autoload :IdlePoller, 'rubyn_code/autonomous/idle_poller'
    autoload :TaskClaimer, 'rubyn_code/autonomous/task_claimer'
  end

  # Layer 12: Memory
  module Memory
    autoload :Store, 'rubyn_code/memory/store'
    autoload :Search, 'rubyn_code/memory/search'
    autoload :SessionPersistence, 'rubyn_code/memory/session_persistence'
    autoload :Models, 'rubyn_code/memory/models'
  end

  # Layer 13: Observability
  module Observability
    autoload :TokenCounter, 'rubyn_code/observability/token_counter'
    autoload :CostCalculator, 'rubyn_code/observability/cost_calculator'
    autoload :BudgetEnforcer, 'rubyn_code/observability/budget_enforcer'
    autoload :UsageReporter, 'rubyn_code/observability/usage_reporter'
    autoload :Models, 'rubyn_code/observability/models'
    autoload :TokenAnalytics, 'rubyn_code/observability/token_analytics'
    autoload :SkillAnalytics, 'rubyn_code/observability/skill_analytics'
  end

  # Layer 14: Hooks
  module Hooks
    autoload :Registry, 'rubyn_code/hooks/registry'
    autoload :Runner, 'rubyn_code/hooks/runner'
    autoload :BuiltIn, 'rubyn_code/hooks/built_in'
    autoload :UserHooks, 'rubyn_code/hooks/user_hooks'
  end

  # Layer 15: MCP
  module MCP
    autoload :Client, 'rubyn_code/mcp/client'
    autoload :StdioTransport, 'rubyn_code/mcp/stdio_transport'
    autoload :SSETransport, 'rubyn_code/mcp/sse_transport'
    autoload :ToolBridge, 'rubyn_code/mcp/tool_bridge'
    autoload :Config, 'rubyn_code/mcp/config'
  end

  # Layer 16: Learning
  module Learning
    autoload :Extractor, 'rubyn_code/learning/extractor'
    autoload :Instinct, 'rubyn_code/learning/instinct'
    autoload :InstinctMethods, 'rubyn_code/learning/instinct'
    autoload :Injector, 'rubyn_code/learning/injector'
    autoload :Shortcut, 'rubyn_code/learning/shortcut'
  end

  # IDE (VS Code extension server)
  module IDE
    autoload :Protocol, 'rubyn_code/ide/protocol'
    autoload :Server, 'rubyn_code/ide/server'

    module Adapters
      autoload :ToolOutput, 'rubyn_code/ide/adapters/tool_output'
    end
  end

  # Self-Test
  autoload :SelfTest, 'rubyn_code/self_test'

  # Codebase Index
  module Index
    autoload :CodebaseIndex, 'rubyn_code/index/codebase_index'
  end

  # CLI
  module CLI
    autoload :App, 'rubyn_code/cli/app'
    autoload :REPL, 'rubyn_code/cli/repl'
    autoload :InputHandler, 'rubyn_code/cli/input_handler'
    autoload :Renderer, 'rubyn_code/cli/renderer'
    autoload :Spinner, 'rubyn_code/cli/spinner'
    autoload :StreamFormatter, 'rubyn_code/cli/stream_formatter'
    autoload :Setup, 'rubyn_code/cli/setup'
    autoload :FirstRun, 'rubyn_code/cli/first_run'
    autoload :DaemonRunner, 'rubyn_code/cli/daemon_runner'
    autoload :VersionCheck, 'rubyn_code/cli/version_check'

    # Slash Command System
    module Commands
      autoload :Base, 'rubyn_code/cli/commands/base'
      autoload :Context, 'rubyn_code/cli/commands/context'
      autoload :Registry, 'rubyn_code/cli/commands/registry'
      autoload :Help, 'rubyn_code/cli/commands/help'
      autoload :Quit, 'rubyn_code/cli/commands/quit'
      autoload :Compact, 'rubyn_code/cli/commands/compact'
      autoload :Cost, 'rubyn_code/cli/commands/cost'
      autoload :Clear, 'rubyn_code/cli/commands/clear'
      autoload :Undo, 'rubyn_code/cli/commands/undo'
      autoload :Tasks, 'rubyn_code/cli/commands/tasks'
      autoload :Budget, 'rubyn_code/cli/commands/budget'
      autoload :Skill, 'rubyn_code/cli/commands/skill'
      autoload :Version, 'rubyn_code/cli/commands/version'
      autoload :Review, 'rubyn_code/cli/commands/review'
      autoload :Resume, 'rubyn_code/cli/commands/resume'
      autoload :Spawn, 'rubyn_code/cli/commands/spawn'
      autoload :Doctor, 'rubyn_code/cli/commands/doctor'
      autoload :Tokens, 'rubyn_code/cli/commands/tokens'
      autoload :Plan, 'rubyn_code/cli/commands/plan'
      autoload :ContextInfo, 'rubyn_code/cli/commands/context_info'
      autoload :Diff, 'rubyn_code/cli/commands/diff'
      autoload :Mcp, 'rubyn_code/cli/commands/mcp'
      autoload :Model, 'rubyn_code/cli/commands/model'
      autoload :NewSession, 'rubyn_code/cli/commands/new_session'
      autoload :Provider, 'rubyn_code/cli/commands/provider'
      autoload :InstallSkills, 'rubyn_code/cli/commands/install_skills'
      autoload :RemoveSkills, 'rubyn_code/cli/commands/remove_skills'
      autoload :Skills, 'rubyn_code/cli/commands/skills'
    end
  end

  # Output
  module Output
    autoload :Formatter, 'rubyn_code/output/formatter'
    autoload :DiffRenderer, 'rubyn_code/output/diff_renderer'
  end
end
