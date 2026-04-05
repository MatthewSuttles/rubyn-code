# frozen_string_literal: true

require 'tty-prompt'
require 'tty-reader'
require 'pastel'

module RubynCode
  module Protocols
    # Presents a plan to the user for approval before executing significant changes.
    #
    # This protocol ensures that destructive or wide-reaching operations are
    # reviewed by a human before proceeding.
    module PlanApproval
      APPROVED = :approved
      REJECTED = :rejected

      class << self
        # Displays a plan and asks the user to approve or reject it.
        #
        # @param plan_text [String] the plan description to display
        # @param prompt [String, nil] optional custom prompt message
        # @return [Symbol] :approved or :rejected
        def request(plan_text, prompt: nil)
          pastel = Pastel.new
          display_plan(pastel, plan_text, prompt)

          approved = build_prompt.yes?(
            pastel.yellow.bold('Do you approve this plan?'),
            default: false
          )

          approved ? approve(pastel) : reject(pastel)
        rescue TTY::Reader::InputInterrupt
          $stdout.puts pastel.red("\nPlan rejected (interrupted).")
          REJECTED
        end

        private

        def display_plan(pastel, plan_text, prompt)
          $stdout.puts
          $stdout.puts pastel.cyan.bold('Proposed Plan')
          $stdout.puts pastel.cyan('=' * 60)
          $stdout.puts plan_text
          $stdout.puts pastel.cyan('=' * 60)
          $stdout.puts
          return unless prompt

          $stdout.puts pastel.yellow(prompt)
          $stdout.puts
        end

        def approve(pastel)
          $stdout.puts pastel.green('Plan approved.')
          APPROVED
        end

        def reject(pastel)
          $stdout.puts pastel.red('Plan rejected.')
          REJECTED
        end

        # Builds a TTY::Prompt instance configured for non-destructive interrupt handling.
        #
        # @return [TTY::Prompt]
        def build_prompt
          TTY::Prompt.new(interrupt: :noop)
        end
      end
    end
  end
end
