# frozen_string_literal: true

require 'tty-prompt'
require 'yaml'
require 'fileutils'

module RubynCode
  module CLI
    # Guided first-run setup wizard.
    #
    # Runs when no ~/.rubyn-code/config.yml exists (first launch).
    # Walks the user through provider selection, API key configuration,
    # and default budget setup.
    #
    # Skippable via --skip-setup flag or RUBYN_SKIP_SETUP=1 env var.
    class FirstRun
      PROVIDERS = {
        'Anthropic (recommended)' => 'anthropic',
        'OpenAI' => 'openai',
        'Other (configure later)' => 'other'
      }.freeze

      DEFAULT_BUDGET = 5.0

      def initialize(config_path: Config::Defaults::CONFIG_FILE, prompt: nil)
        @config_path = config_path
        @tty_prompt = prompt
      end

      # Returns true if first-run setup should be triggered.
      def self.needed?(config_path: Config::Defaults::CONFIG_FILE)
        !File.exist?(config_path)
      end

      # Returns true if the user opted to skip setup.
      def self.skipped?(skip_flag: false)
        skip_flag || ENV['RUBYN_SKIP_SETUP'] == '1'
      end

      def run
        display_welcome
        provider = ask_provider
        configure_api_key(provider)
        budget = ask_budget
        write_config(provider, budget)
        display_summary
      end

      private

      def tty_prompt
        @tty_prompt ||= TTY::Prompt.new
      end

      def display_welcome
        puts
        puts "\e[1;36m#{'=' * 50}\e[0m"
        puts "\e[1;36m  Welcome to Rubyn Code!\e[0m"
        puts "\e[1;36m  Ruby & Rails Agentic Coding Assistant\e[0m"
        puts "\e[1;36m#{'=' * 50}\e[0m"
        puts
        puts "  Let's get you set up. This will only take a moment."
        puts
      end

      def ask_provider
        tty_prompt.select('Which AI provider would you like to use?', PROVIDERS)
      end

      def configure_api_key(provider)
        case provider
        when 'anthropic'
          configure_anthropic
        when 'openai'
          configure_openai
        when 'other'
          puts
          puts '  You can configure a custom provider later in ~/.rubyn-code/config.yml'
          puts
        end
      end

      def configure_anthropic
        puts
        puts '  Anthropic authentication options:'
        puts '    1. Set ANTHROPIC_API_KEY environment variable'
        puts '    2. Run `rubyn-code --auth` for OAuth (if you have a Claude account)'
        puts

        has_key = ENV.key?('ANTHROPIC_API_KEY')
        if has_key
          puts "  \e[32m✓\e[0m ANTHROPIC_API_KEY is already set."
        else
          puts "  \e[33m!\e[0m ANTHROPIC_API_KEY is not set."
          puts '    Add it to your shell profile or set it before running rubyn-code.'
        end
        puts
      end

      def configure_openai
        puts
        has_key = ENV.key?('OPENAI_API_KEY')
        if has_key
          puts "  \e[32m✓\e[0m OPENAI_API_KEY is already set."
        else
          puts "  \e[33m!\e[0m OPENAI_API_KEY is not set."
          puts '    Add it to your shell profile or set it before running rubyn-code.'
        end
        puts
      end

      def ask_budget
        tty_prompt.ask(
          'Session budget in USD?',
          default: DEFAULT_BUDGET.to_s,
          convert: :float
        )
      end

      def write_config(provider, budget)
        dir = File.dirname(@config_path)
        FileUtils.mkdir_p(dir, mode: 0o700) unless File.directory?(dir)

        model = default_model(provider)
        data = {
          'provider' => provider == 'other' ? 'anthropic' : provider,
          'model' => model,
          'session_budget_usd' => budget,
          'providers' => Config::Settings::DEFAULT_PROVIDER_MODELS.transform_values(&:dup)
        }

        File.write(@config_path, YAML.dump(data))
        File.chmod(0o600, @config_path)
      end

      def default_model(provider)
        return 'gpt-5.4' if provider == 'openai'

        'claude-opus-4-6'
      end

      def display_summary
        puts
        puts "\e[1;32m  Setup complete!\e[0m"
        puts
        puts '  Quick-start commands:'
        puts '    /help          — Show all available commands'
        puts '    /skill         — List coding skills'
        puts '    /doctor        — Check environment health'
        puts '    /cost          — View session costs'
        puts '    /compact       — Compress conversation context'
        puts '    /quit          — Exit'
        puts
        puts "  Config saved to: #{@config_path}"
        puts
      end
    end
  end
end
