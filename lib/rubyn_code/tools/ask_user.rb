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

      attr_writer :prompt_callback

      def execute(question:)
        if @prompt_callback
          @prompt_callback.call(question)
        else
          # Fallback: use stdin directly
          $stdout.puts
          $stdout.puts "  #{question}"
          $stdout.print '  > '
          $stdout.flush
          $stdin.gets&.strip || '[no response]'
        end
      end
    end

    Registry.register(AskUser)
  end
end
