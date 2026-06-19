# frozen_string_literal: true

require 'spec_helper'

RSpec.describe RubynCode::Hooks::GoalHook do
  let(:condition) { 'all tests pass' }

  describe '#call' do
    it 'blocks stopping when no evaluator is provided' do
      hook = described_class.new(condition: condition)
      result = hook.call(conversation: nil)

      expect(result).to include(block: true)
      expect(result[:reason]).to include(condition)
    end

    it 'allows stopping and auto-clears once the evaluator says the goal is met' do
      evaluator = ->(**_) { true }
      hook = described_class.new(condition: condition, evaluator: evaluator)

      expect(hook.call).to be_nil
      expect(hook).not_to be_active
    end

    it 'keeps blocking while the evaluator says the goal is not met' do
      evaluator = ->(**_) { false }
      hook = described_class.new(condition: condition, evaluator: evaluator)

      expect(hook.call).to include(block: true)
      expect(hook).to be_active
    end

    it 'returns nil immediately once cleared' do
      hook = described_class.new(condition: condition)
      hook.clear!

      expect(hook.call).to be_nil
      expect(hook).not_to be_active
    end

    it 'gives up after max_attempts to avoid an unsatisfiable loop' do
      hook = described_class.new(condition: condition, evaluator: ->(**_) { false }, max_attempts: 3)

      2.times { expect(hook.call).to include(block: true) }
      expect(hook.call).to be_nil # third attempt exhausts the budget
      expect(hook).not_to be_active
    end

    it 'treats evaluator errors as not-met (keeps working)' do
      hook = described_class.new(condition: condition, evaluator: ->(**_) { raise 'boom' })

      expect(hook.call).to include(block: true)
    end
  end
end
