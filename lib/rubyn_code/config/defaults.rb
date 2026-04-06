# frozen_string_literal: true

module RubynCode
  module Config
    module Defaults
      HOME_DIR = File.expand_path('~/.rubyn-code')
      CONFIG_FILE = File.join(HOME_DIR, 'config.yml')
      DB_FILE = File.join(HOME_DIR, 'rubyn_code.db')
      TOKENS_FILE = File.join(HOME_DIR, 'tokens.yml')
      SESSIONS_DIR = File.join(HOME_DIR, 'sessions')
      MEMORIES_DIR = File.join(HOME_DIR, 'memories')

      DEFAULT_PROVIDER = 'anthropic'
      DEFAULT_MODEL = 'claude-opus-5-4'
      MAX_ITERATIONS = 200
      MAX_SUB_AGENT_ITERATIONS = 200
      MAX_EXPLORE_AGENT_ITERATIONS = 200

      # Output token management (3-tier recovery, matches Claude Code)
      CAPPED_MAX_OUTPUT_TOKENS = 8_000 # Default cap — keeps prompt cache efficient
      ESCALATED_MAX_OUTPUT_TOKENS = 32_000   # Silent escalation on first max_tokens hit
      MAX_OUTPUT_TOKENS_RECOVERY_LIMIT = 3   # Multi-turn recovery attempts after escalation

      MAX_OUTPUT_CHARS = 10_000
      MAX_TOOL_RESULT_CHARS = 10_000          # Per-tool result cap
      MAX_MESSAGE_TOOL_RESULTS_CHARS = 50_000 # Aggregate cap for all tool results in one message
      CONTEXT_THRESHOLD_TOKENS = 80_000
      MICRO_COMPACT_KEEP_RECENT = 2

      POLL_INTERVAL = 5
      IDLE_TIMEOUT = 60

      SESSION_BUDGET_USD = 5.00
      DAILY_BUDGET_USD = 10.00

      OAUTH_CLIENT_ID = 'rubyn-code'
      OAUTH_REDIRECT_URI = 'http://localhost:19275/callback'
      OAUTH_AUTHORIZE_URL = 'https://claude.ai/oauth/authorize'
      OAUTH_TOKEN_URL = 'https://claude.ai/oauth/token'
      OAUTH_SCOPES = 'user:read model:read model:write'

      # Known provider configurations: provider name → { env_key:, base_url: (if not default) }
      PROVIDER_ENV_KEYS = {
        'anthropic' => 'ANTHROPIC_API_KEY',
        'openai' => 'OPENAI_API_KEY',
        'groq' => 'GROQ_API_KEY',
        'together' => 'TOGETHER_API_KEY',
        'ollama' => 'OLLAMA_API_KEY'
      }.freeze

      DANGEROUS_PATTERNS = [
        'rm -rf /', 'sudo rm', 'shutdown', 'reboot',
        '> /dev/', 'mkfs', 'dd if=', ':(){:|:&};:'
      ].freeze

      SCRUB_ENV_VARS = %w[
        API_KEY SECRET TOKEN PASSWORD CREDENTIAL
        PRIVATE_KEY ACCESS_KEY SESSION_KEY
      ].freeze
    end
  end
end
