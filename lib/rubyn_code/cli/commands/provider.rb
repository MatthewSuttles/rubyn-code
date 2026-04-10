# frozen_string_literal: true

module RubynCode
  module CLI
    module Commands
      class Provider < Base
        def self.command_name = '/provider'
        def self.description = 'Manage providers (/provider add|list|set-key)'

        USAGE_LINES = [
          'Usage:',
          '  /provider list                            List configured providers',
          '  /provider add <name> <base_url> [opts]    Add a provider',
          '  /provider set-key <name> <key>            Store an API key',
          '',
          'Options for add:',
          '  --key <api_key>              API key (stored securely in tokens.yml)',
          '  --format <openai|anthropic>  API format (default: openai)',
          '  --models <m1,m2,...>          Comma-separated model names',
          '',
          'Example:',
          '  /provider add groq https://api.groq.com/openai/v1 --key gsk-xxx --models llama-3.3-70b'
        ].freeze

        FLAG_KEYS = { '--format' => :api_format, '--env-key' => :env_key, '--key' => :key }.freeze

        def execute(args, ctx)
          return show_usage(ctx) if args.empty?

          case args.first
          when 'add' then add_provider(args[1..], ctx)
          when 'list' then list_providers(ctx)
          when 'set-key' then set_key(args[1..], ctx)
          else show_usage(ctx)
          end
        end

        private

        def add_provider(args, ctx)
          name = args.shift
          base_url = args.shift
          return ctx.renderer.warning('Usage: /provider add <name> <base_url> [options]') unless name && base_url

          opts = parse_flags(args)
          persist_provider(name, base_url, opts)
          confirm_added(name, base_url, opts, ctx)
        end

        def persist_provider(name, base_url, opts)
          Config::Settings.new.add_provider(
            name, base_url: base_url, env_key: opts[:env_key],
                  models: opts[:models], api_format: opts[:api_format]
          )
          Auth::TokenStore.save_provider_key(name, opts[:key]) if opts[:key]
        end

        def confirm_added(name, base_url, opts, ctx) # rubocop:disable Metrics/AbcSize -- sequential output lines
          ctx.renderer.success("Provider '#{name}' added (#{opts[:api_format] || 'openai'} format)")
          ctx.renderer.info("  base_url: #{base_url}")
          ctx.renderer.info('  api_key: stored') if opts[:key]
          ctx.renderer.info("  models: #{opts[:models].join(', ')}") unless opts[:models].empty?
          ctx.renderer.info("Switch with: /model #{name}:#{opts[:models].first || '<model>'}")
        end

        def set_key(args, ctx)
          name = args[0]
          key = args[1]
          return ctx.renderer.warning('Usage: /provider set-key <name> <key>') unless name && key

          Auth::TokenStore.save_provider_key(name, key)
          ctx.renderer.success("API key stored for '#{name}'")
        end

        def list_providers(ctx)
          providers = Config::Settings.new.data['providers']
          return ctx.renderer.info('No providers configured.') unless providers.is_a?(Hash) && providers.any?

          providers.each { |name, cfg| ctx.renderer.info("  #{format_provider(name, cfg)}") }
        end

        def format_provider(name, cfg)
          format_label = cfg.is_a?(Hash) && cfg['api_format'] ? " (#{cfg['api_format']})" : ''
          models = extract_models(cfg)
          model_label = models.empty? ? '' : " — #{models.join(', ')}"
          "#{name}#{format_label}#{model_label}"
        end

        def parse_flags(args)
          opts = { models: [], env_key: nil, api_format: nil, key: nil }
          idx = 0
          idx = parse_single_flag(args, idx, opts) while idx < args.length
          opts
        end

        def parse_single_flag(args, idx, opts)
          flag = args[idx]
          return idx + 1 unless FLAG_KEYS.key?(flag) || flag == '--models'
          return parse_models_flag(args, idx, opts) if flag == '--models'

          opts[FLAG_KEYS[flag]] = args[idx + 1]
          idx + 2
        end

        def parse_models_flag(args, idx, opts)
          opts[:models] = args[idx + 1]&.split(',')&.map(&:strip) || []
          idx + 2
        end

        def extract_models(cfg)
          raw = cfg.is_a?(Hash) ? cfg['models'] : nil
          return [] unless raw

          raw.is_a?(Hash) ? raw.values : Array(raw)
        end

        def show_usage(ctx)
          USAGE_LINES.each { |line| ctx.renderer.info(line) }
        end
      end
    end
  end
end
