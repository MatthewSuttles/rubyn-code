# frozen_string_literal: true

module RubynCode
  module Config
    module Defaults
      HOME_DIR = File.expand_path("~/.rubyn-code")
      CONFIG_FILE = File.join(HOME_DIR, "config.yml")
      DB_FILE = File.join(HOME_DIR, "rubyn_code.db")
      TOKENS_FILE = File.join(HOME_DIR, "tokens.yml")
      SESSIONS_DIR = File.join(HOME_DIR, "sessions")
      MEMORIES_DIR = File.join(HOME_DIR, "memories")

      DEFAULT_MODEL = "claude-opus-4-6"
      MAX_ITERATIONS = 200
      MAX_SUB_AGENT_ITERATIONS = 30
      MAX_OUTPUT_CHARS = 50_000
      CONTEXT_THRESHOLD_TOKENS = 50_000
      MICRO_COMPACT_KEEP_RECENT = 3

      POLL_INTERVAL = 5
      IDLE_TIMEOUT = 60

      SESSION_BUDGET_USD = 5.00
      DAILY_BUDGET_USD = 10.00

      OAUTH_CLIENT_ID = "rubyn-code"
      OAUTH_REDIRECT_URI = "http://localhost:19275/callback"
      OAUTH_AUTHORIZE_URL = "https://claude.ai/oauth/authorize"
      OAUTH_TOKEN_URL = "https://claude.ai/oauth/token"
      OAUTH_SCOPES = "user:read model:read model:write"

      DANGEROUS_PATTERNS = [
        "rm -rf /", "sudo rm", "shutdown", "reboot",
        "> /dev/", "mkfs", "dd if=", ":(){:|:&};:"
      ].freeze

      SCRUB_ENV_VARS = %w[
        API_KEY SECRET TOKEN PASSWORD CREDENTIAL
        PRIVATE_KEY ACCESS_KEY SESSION_KEY
      ].freeze
    end
  end
end
