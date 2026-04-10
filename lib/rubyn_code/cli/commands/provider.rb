# frozen_string_literal: true

module RubynCode
  module CLI
    module Commands
      class Provider < Base
        def self.command_name = '/provider'
        def self.description = 'Manage providers (/provider add|list|set-key)'

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

          unless name && base_url
            ctx.renderer.warning('Usage: /provider add <name> <base_url> [options]')
            return
          end

          opts = parse_flags(args)
          settings = Config::Settings.new
          settings.add_provider(
            name,
            base_url: base_url,
            env_key: opts[:env_key],
            models: opts[:models],
            api_format: opts[:api_format]
          )

          Auth::TokenStore.save_provider_key(name, opts[:key]) if opts[:key]

          ctx.renderer.success("Provider '#{name}' added (#{opts[:api_format] || 'openai'} format)")
          ctx.renderer.info("  base_url: #{base_url}")
          ctx.renderer.info("  api_key: stored") if opts[:key]
          ctx.renderer.info("  models: #{opts[:models].join(', ')}") unless opts[:models].empty?
          ctx.renderer.info("Switch with: /model #{name}:#{opts[:models].first || '<model>'}") # rubocop:disable Style/TernaryParentheses
        end

        def set_key(args, ctx)
          name = args[0]
          key = args[1]

          unless name && key
            ctx.renderer.warning('Usage: /provider set-key <name> <key>')
            return
          end

          Auth::TokenStore.save_provider_key(name, key)
          ctx.renderer.success("API key stored for '#{name}'")
        end

        def list_providers(ctx)
          settings = Config::Settings.new
          providers = settings.data['providers']

          unless providers.is_a?(Hash) && providers.any?
            ctx.renderer.info('No providers configured.')
            return
          end

          providers.each do |name, cfg|
            format_label = cfg.is_a?(Hash) && cfg['api_format'] ? " (#{cfg['api_format']})" : ''
            models = extract_models(cfg)
            model_label = models.empty? ? '' : " — #{models.join(', ')}"
            ctx.renderer.info("  #{name}#{format_label}#{model_label}")
          end
        end

        def parse_flags(args)
          opts = { models: [], env_key: nil, api_format: nil, key: nil }
          idx = 0
          while idx < args.length
            case args[idx]
            when '--format'
              opts[:api_format] = args[idx + 1]
              idx += 2
            when '--env-key'
              opts[:env_key] = args[idx + 1]
              idx += 2
            when '--models'
              opts[:models] = args[idx + 1]&.split(',')&.map(&:strip) || []
              idx += 2
            when '--key'
              opts[:key] = args[idx + 1]
              idx += 2
            else
              idx += 1
            end
          end
          opts
        end

        def extract_models(cfg)
          raw = cfg.is_a?(Hash) ? cfg['models'] : nil
          return [] unless raw

          raw.is_a?(Hash) ? raw.values : Array(raw)
        end

        def show_usage(ctx)
          ctx.renderer.info('Usage:')
          ctx.renderer.info('  /provider list                            List configured providers')
          ctx.renderer.info('  /provider add <name> <base_url> [opts]    Add a provider')
          ctx.renderer.info('  /provider set-key <name> <key>            Store an API key')
          ctx.renderer.info('')
          ctx.renderer.info('Options for add:')
          ctx.renderer.info('  --key <api_key>              API key (stored securely in tokens.yml)')
          ctx.renderer.info('  --format <openai|anthropic>  API format (default: openai)')
          ctx.renderer.info('  --models <m1,m2,...>          Comma-separated model names')
          ctx.renderer.info('')
          ctx.renderer.info('Example:')
          ctx.renderer.info('  /provider add groq https://api.groq.com/openai/v1 --key gsk-xxx --models llama-3.3-70b')
        end
      end
    end
  end
end
