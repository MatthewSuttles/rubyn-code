# frozen_string_literal: true

require_relative 'base'
require_relative 'registry'

module RubynCode
  module Tools
    # Ask a different model for a second opinion. The "friend" is chosen to
    # maximize perspective diversity: prefer the top-tier model of another
    # configured provider (a genuinely different model family), and fall back
    # to the active provider's top-tier model when no other provider has an
    # API key available. One-shot, no tools, returns plain text.
    class PhoneAFriend < Base
      TOOL_NAME = 'phone_a_friend'
      DESCRIPTION = 'Ask a different model for a second opinion when you are stuck, ' \
                    'weighing two approaches, or want your reasoning sanity-checked. ' \
                    'Sends one question (plus optional context) to another model — ' \
                    'a different provider when one is configured, otherwise the ' \
                    'top-tier model of the current provider — and returns its answer. ' \
                    'The friend has no tools and sees nothing except what you send.'
      PARAMETERS = {
        question: {
          type: :string,
          required: true,
          description: 'The question to ask. Be specific about what kind of answer you ' \
                       'need (a decision, a review of reasoning, an alternative approach).'
        },
        context: {
          type: :string,
          required: false,
          description: 'Relevant code, error output, or background. The friend sees ' \
                       'only this — include everything needed to answer well.'
        }
      }.freeze
      RISK_LEVEL = :external

      SYSTEM_PROMPT = <<~PROMPT
        You are giving a second opinion to another AI coding agent that is working
        inside a project and has hit a question it wants an outside perspective on.
        You cannot see the project — only what the agent sent you. Answer directly
        and concretely: commit to a recommendation, explain the key reason, and
        flag anything important the agent may have missed. If the provided context
        is insufficient to answer well, say exactly what is missing.
      PROMPT

      # Injected by the Executor (active client) and overridable in tests.
      attr_writer :llm_client, :client_factory

      def execute(question:, context: nil)
        return 'phone_a_friend: no LLM client available.' unless @llm_client

        provider, model = pick_friend
        response = call_friend(provider, model, build_message(question, context))
        answer = extract_text(response)
        return "phone_a_friend: #{provider}/#{model} returned no text." if answer.empty?

        "## Second Opinion — #{provider}/#{model}\n\n#{answer}"
      rescue StandardError => e
        friend = provider ? "#{provider}/#{model}" : 'friend'
        "phone_a_friend: call to #{friend} failed: #{e.message}"
      end

      def self.summarize(_output, _args)
        'asked another model for a second opinion'
      end

      private

      # Returns [provider, model]. Prefers another provider whose API key is
      # present; otherwise escalates to the active provider's top tier.
      def pick_friend
        active = @llm_client.provider_name
        other = (known_providers - [active]).find { |p| key_present?(p) }
        provider = other || active
        [provider, top_model_for(provider)]
      end

      def call_friend(provider, model, message)
        client = provider == @llm_client.provider_name ? @llm_client : friend_client(provider, model)
        client.chat(
          messages: [{ role: 'user', content: message }],
          tools: nil,
          system: SYSTEM_PROMPT,
          model: model
        )
      end

      def friend_client(provider, model)
        factory = @client_factory || ->(prov, mod) { LLM::Client.new(provider: prov, model: mod) }
        factory.call(provider, model)
      end

      def build_message(question, context)
        return question if context.to_s.empty?

        "#{question}\n\n## Context\n\n#{context}"
      end

      def known_providers
        configured = settings.to_h['providers']
        names = configured.is_a?(Hash) ? configured.keys : []
        (names + Config::Settings::DEFAULT_PROVIDER_MODELS.keys).uniq
      end

      def key_present?(provider)
        env_key = provider_setting(provider, 'env_key')
        env_key ? !ENV[env_key].to_s.empty? : false
      end

      def top_model_for(provider)
        config_models = provider_setting(provider, 'models')
        model = config_models['top'] || config_models.values.last if config_models.is_a?(Hash)
        model || @llm_client.model
      end

      # Reads a provider key from config.yml, falling back to the built-in
      # provider defaults for anthropic/openai.
      def provider_setting(provider, key)
        value = settings.provider_config(provider)&.fetch(key, nil)
        value || Config::Settings::DEFAULT_PROVIDER_MODELS.dig(provider, key)
      end

      def settings
        @settings ||= Config::Settings.new
      end

      def extract_text(response)
        content = response.respond_to?(:content) ? Array(response.content) : []
        content.select { |b| b.respond_to?(:type) && b.type == 'text' }.map(&:text).join("\n")
      end
    end

    Registry.register(PhoneAFriend)
  end
end
