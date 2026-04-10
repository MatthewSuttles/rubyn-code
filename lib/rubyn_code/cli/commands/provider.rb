# frozen_string_literal: true

module RubynCode
  module CLI
    module Commands
      class Provider < Base
        def self.command_name = '/provider'
        def self.description = 'Add a provider (/provider add <name> <base_url> [--format anthropic] [--env-key KEY] [--models m1,m2])'

        def execute(args, ctx)
          return show_usage(ctx) if args.empty?

          case args.first
          when 'add' then add_provider(args[1..], ctx)
          when 'list' then list_providers(ctx)
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

          ctx.renderer.success("Provider '#{name}' added (#{opts[:api_format] || 'openai'} format)")
          ctx.renderer.info("  base_url: #{base_url}")
          ctx.renderer.info("  env_key: #{opts[:env_key]}") if opts[:env_key]
          ctx.renderer.info("  models: #{opts[:models].join(', ')}") unless opts[:models].empty?
          ctx.renderer.info("Switch with: /model #{name}:#{opts[:models].first || '<model>'}") # rubocop:disable Style/TernaryParentheses
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
          opts = { models: [], env_key: nil, api_format: nil }
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
          ctx.renderer.info('  /provider list                          List configured providers')
          ctx.renderer.info('  /provider add <name> <base_url> [opts]  Add a provider')
          ctx.renderer.info('')
          ctx.renderer.info('Options:')
          ctx.renderer.info('  --format <openai|anthropic>  API format (default: openai)')
          ctx.renderer.info('  --env-key <VAR_NAME>         Environment variable for API key')
          ctx.renderer.info('  --models <m1,m2,...>          Comma-separated model names')
          ctx.renderer.info('')
          ctx.renderer.info('Example:')
          ctx.renderer.info('  /provider add groq https://api.groq.com/openai/v1 --env-key GROQ_API_KEY --models llama-3.3-70b')
        end
      end
    end
  end
end
