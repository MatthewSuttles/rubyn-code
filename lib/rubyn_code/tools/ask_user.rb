# frozen_string_literal: true

require_relative 'base'
require_relative 'registry'

module RubynCode
  module Tools
    class AskUser < Base
      TOOL_NAME = 'ask_user'
      DESCRIPTION = 'Ask the user a question and wait for their response. ' \
                    'Use this when you need clarification, want to confirm a plan before executing, ' \
                    'or are stuck and need guidance. The question is displayed and the user\'s answer ' \
                    'is returned as the tool result.'
      PARAMETERS = {
        question: {
          type: :string,
          description: 'The question to ask the user',
          required: true
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

      def execute(question:)
        if @ide_client
          # IDE mode: round-trip the question through the extension's UI.
          response = @ide_client.request('ide/askUser', { question: question }, timeout: IDE_ASK_TIMEOUT)
          answer = response && response['answer']
          answer.nil? || answer.empty? ? '[no response]' : answer
        elsif @prompt_callback
          @prompt_callback.call(question)
        elsif $stdin.respond_to?(:tty?) && $stdin.tty?
          # Interactive fallback: prompt on stdin
          $stdout.puts
          $stdout.puts "  #{question}"
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
