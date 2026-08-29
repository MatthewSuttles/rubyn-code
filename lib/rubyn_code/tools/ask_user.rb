# frozen_string_literal: true

require 'json'

require_relative 'base'
require_relative 'registry'

module RubynCode
  module Tools
    class AskUser < Base
      TOOL_NAME = 'ask_user'
      DESCRIPTION = 'Ask the user one question or a round of at most three independent questions and wait for their response. ' \
                    'For Wayfinder Grill rounds, provide options with recommendation, pros, and cons; freeform input remains available. ' \
                    'The Harness returns the submitted answer as the tool result.'
      PARAMETERS = {
        question: {
          type: :string,
          description: 'The question to ask the user',
          required: false
        },
        questions: {
          type: :array,
          description: 'Optional structured round of up to three questions. Each item may include prompt, cardinality, and options with label, description, recommended, pros, and cons.',
          required: false
        }
      }.freeze
      RISK_LEVEL = :read # Never needs approval — it IS the approval mechanism

      # The user may take a while to answer, so allow far longer than the
      # default RPC timeout before giving up on the IDE round-trip.
      IDE_ASK_TIMEOUT = 300 # seconds

      attr_writer :prompt_callback

      def initialize(project_root:, ide_client: nil)
        super(project_root: project_root)
        @ide_client = ide_client
      end

      def execute(question: nil, questions: nil)
        structured = Array(questions).first(3)
        prompt = question.to_s.strip
        raise ArgumentError, 'question or questions is required' if prompt.empty? && structured.empty?

        if @ide_client
          # IDE mode: round-trip the question through the extension's UI.
          payload = { question: prompt }
          payload[:questions] = structured unless structured.empty?
          response = @ide_client.request('ide/askUser', payload, timeout: IDE_ASK_TIMEOUT)
          answer = response && response['answer']
          return '[no response]' if answer.nil? || (answer.respond_to?(:empty?) && answer.empty?)

          answer.is_a?(String) ? answer : JSON.generate(answer)
        elsif @prompt_callback
          @prompt_callback.call(prompt)
        elsif $stdin.respond_to?(:tty?) && $stdin.tty?
          # Interactive fallback: prompt on stdin
          $stdout.puts
          $stdout.puts "  #{prompt}"
          $stdout.print '  > '
          $stdout.flush
          $stdin.gets&.strip || '[no response]'
        else
          # Non-interactive (piped input, -p mode, daemon) — can't ask
          '[non-interactive session — cannot ask user. Make your best judgment and proceed.]'
        end
      end
    end

    Registry.register(AskUser)
  end
end
