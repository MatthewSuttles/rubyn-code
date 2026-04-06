# frozen_string_literal: true

module RubynCode
  module CLI
    module Commands
      class Model < Base
        def self.command_name = '/model'
        def self.description = 'Show or switch model (/model [provider:model])'

        def execute(args, ctx)
          name = args.first
          return show_current(ctx) unless name

          provider, model = parse_model_arg(name)
          switch_model(provider, model, ctx)
        end

        private

        # Parse "provider:model" or just "model".
        # Examples:
        #   "openai:gpt-4o"            → ["openai", "gpt-4o"]
        #   "claude-sonnet-4-20250514" → [nil, "claude-sonnet-4-20250514"]
        #   "anthropic:"               → ["anthropic", nil]
        def parse_model_arg(arg)
          return [arg.chomp(':'), nil] if arg.end_with?(':')
          return [Regexp.last_match(1), Regexp.last_match(2)] if arg.match(/\A([^:]+):(.+)\z/)

          [nil, arg]
        end

        def switch_model(provider, model, ctx)
          if provider
            switch_provider_and_model(provider, model, ctx)
          else
            switch_model_only(model, ctx)
          end
        end

        def switch_provider_and_model(provider, model, ctx)
          validate_model_for_provider!(provider, model, ctx) if model
          ctx.renderer.info("Switched to provider: #{provider}#{", model: #{model}" if model}")
          { action: :set_provider, provider: provider, model: model }
        end

        def switch_model_only(model, ctx)
          unless known_model?(model, ctx)
            ctx.renderer.warning("Unknown model: #{model}")
            show_available(ctx)
            return
          end

          ctx.renderer.info("Model switched to #{model}")
          { action: :set_model, model: model }
        end

        def validate_model_for_provider!(provider, model, ctx)
          adapter_models = models_for_provider(provider)
          return if adapter_models.empty? # Unknown provider — can't validate
          return if adapter_models.include?(model)

          ctx.renderer.warning("Unknown model '#{model}' for #{provider}. Known: #{adapter_models.join(', ')}")
        end

        def show_current(ctx)
          client = ctx.llm_client
          provider = client.provider_name
          current = client.model
          ctx.renderer.info("Provider: #{provider}")
          ctx.renderer.info("Current model: #{current}")
          show_available(ctx)
        end

        def show_available(ctx)
          client = ctx.llm_client
          ctx.renderer.info("Available: #{client.models.join(', ')}")
          ctx.renderer.info('Tip: /model provider:model to switch providers (e.g., /model openai:gpt-4o)')
        end

        def known_model?(model, ctx)
          ctx.llm_client.models.include?(model)
        end

        def models_for_provider(provider)
          case provider
          when 'anthropic' then LLM::Adapters::Anthropic::AVAILABLE_MODELS
          when 'openai' then LLM::Adapters::OpenAI::AVAILABLE_MODELS
          else []
          end
        end
      end
    end
  end
end
