# frozen_string_literal: true

require 'yaml'
require 'fileutils'
require_relative 'defaults'

module RubynCode
  module Config
    class Settings
      class LoadError < StandardError; end

      CONFIGURABLE_KEYS = %i[
        provider model max_iterations max_sub_agent_iterations max_output_chars
        context_threshold_tokens micro_compact_keep_recent
        poll_interval idle_timeout
        session_budget_usd daily_budget_usd
        oauth_client_id oauth_redirect_uri oauth_authorize_url
        oauth_token_url oauth_scopes
      ].freeze

      DEFAULT_MAP = {
        provider: Defaults::DEFAULT_PROVIDER,
        model: Defaults::DEFAULT_MODEL,
        max_iterations: Defaults::MAX_ITERATIONS,
        max_sub_agent_iterations: Defaults::MAX_SUB_AGENT_ITERATIONS,
        max_output_chars: Defaults::MAX_OUTPUT_CHARS,
        context_threshold_tokens: Defaults::CONTEXT_THRESHOLD_TOKENS,
        micro_compact_keep_recent: Defaults::MICRO_COMPACT_KEEP_RECENT,
        poll_interval: Defaults::POLL_INTERVAL,
        idle_timeout: Defaults::IDLE_TIMEOUT,
        session_budget_usd: Defaults::SESSION_BUDGET_USD,
        daily_budget_usd: Defaults::DAILY_BUDGET_USD,
        oauth_client_id: Defaults::OAUTH_CLIENT_ID,
        oauth_redirect_uri: Defaults::OAUTH_REDIRECT_URI,
        oauth_authorize_url: Defaults::OAUTH_AUTHORIZE_URL,
        oauth_token_url: Defaults::OAUTH_TOKEN_URL,
        oauth_scopes: Defaults::OAUTH_SCOPES
      }.freeze

      attr_reader :config_path, :data

      def initialize(config_path: Defaults::CONFIG_FILE)
        @config_path = config_path
        @data = {}
        ensure_home_directory!
        load!
      end

      # Define accessor methods for each configurable key
      CONFIGURABLE_KEYS.each do |key|
        define_method(key) do
          @data.fetch(key.to_s, DEFAULT_MAP[key])
        end

        define_method(:"#{key}=") do |value|
          @data[key.to_s] = value
        end
      end

      def get(key, default = nil)
        sym = key.to_sym
        @data.fetch(key.to_s) { DEFAULT_MAP.fetch(sym, default) }
      end

      def set(key, value)
        @data[key.to_s] = value
      end

      def save!
        ensure_home_directory!
        File.write(@config_path, YAML.dump(@data))
        File.chmod(0o600, @config_path)
      rescue Errno::EACCES => e
        raise LoadError, "Permission denied writing config to #{@config_path}: #{e.message}"
      rescue SystemCallError => e
        raise LoadError, "Failed to save config to #{@config_path}: #{e.message}"
      end

      def reload!
        load!
      end

      def to_h
        DEFAULT_MAP.transform_keys(&:to_s).merge(@data)
      end

      def home_dir = Defaults::HOME_DIR
      def db_file = Defaults::DB_FILE
      def tokens_file = Defaults::TOKENS_FILE
      def sessions_dir = Defaults::SESSIONS_DIR
      def memories_dir = Defaults::MEMORIES_DIR

      def dangerous_patterns = Defaults::DANGEROUS_PATTERNS
      def scrub_env_vars = Defaults::SCRUB_ENV_VARS

      # Returns config hash for a custom provider, or nil if not configured.
      # Reads from `providers.<name>` in config.yml.
      #
      # Expected keys: base_url, env_key, models, pricing
      # pricing is a hash of model_name => [input_rate, output_rate]
      def provider_config(name)
        providers = @data.dig('providers', name.to_s)
        return nil unless providers.is_a?(Hash)

        providers.transform_keys(&:to_s)
      end

      # Returns all user-configured pricing as { model => [input, output] }
      def custom_pricing
        providers = @data['providers']
        return {} unless providers.is_a?(Hash)

        providers.each_with_object({}) do |(_, cfg), acc|
          merge_provider_pricing(cfg, acc)
        end
      end

      private

      def merge_provider_pricing(cfg, acc)
        return unless cfg.is_a?(Hash) && cfg['pricing'].is_a?(Hash)

        cfg['pricing'].each do |model, rates|
          pair = Array(rates)
          acc[model.to_s] = pair.map(&:to_f) if pair.size == 2
        end
      end

      def ensure_home_directory!
        dir = File.dirname(@config_path)
        return if File.directory?(dir)

        FileUtils.mkdir_p(dir, mode: 0o700)
      rescue SystemCallError => e
        raise LoadError, "Cannot create config directory #{dir}: #{e.message}"
      end

      def load!
        return unless File.exist?(@config_path)

        content = File.read(@config_path)
        return if content.strip.empty?

        parsed = YAML.safe_load(content, permitted_classes: [Symbol])

        case parsed
        in Hash => h
          @data = h.transform_keys(&:to_s)
        else
          raise LoadError, "Expected a YAML mapping in #{@config_path}, got #{parsed.class}"
        end
      rescue Psych::SyntaxError => e
        raise LoadError, "Malformed YAML in #{@config_path}: #{e.message}"
      rescue Errno::EACCES => e
        raise LoadError, "Permission denied reading #{@config_path}: #{e.message}"
      end
    end
  end
end
