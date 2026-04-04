# frozen_string_literal: true

require 'spec_helper'

RSpec.describe RubynCode::Hooks::BuiltIn do
  describe RubynCode::Hooks::BuiltIn::CostTrackingHook do
    let(:budget_enforcer) do
      instance_double('RubynCode::Observability::BudgetEnforcer', record!: nil)
    end

    subject(:hook) { described_class.new(budget_enforcer: budget_enforcer) }

    describe '#call' do
      it 'records usage with symbol keys' do
        response = {
          model: 'claude-sonnet-4-20250514',
          usage: {
            input_tokens: 100,
            output_tokens: 50,
            cache_read_input_tokens: 10,
            cache_creation_input_tokens: 5
          }
        }

        hook.call(response: response)

        expect(budget_enforcer).to have_received(:record!).with(
          model: 'claude-sonnet-4-20250514',
          input_tokens: 100,
          output_tokens: 50,
          cache_read_tokens: 10,
          cache_write_tokens: 5
        )
      end

      it 'records usage with string keys' do
        response = {
          'model' => 'claude-haiku',
          'usage' => {
            'input_tokens' => 200,
            'output_tokens' => 80,
            'cache_read_input_tokens' => 20,
            'cache_creation_input_tokens' => 15
          }
        }

        hook.call(response: response)

        expect(budget_enforcer).to have_received(:record!).with(
          model: 'claude-haiku',
          input_tokens: 200,
          output_tokens: 80,
          cache_read_tokens: 20,
          cache_write_tokens: 15
        )
      end

      it 'returns early when budget_enforcer is nil' do
        hook = described_class.new(budget_enforcer: nil)
        response = { usage: { input_tokens: 100, output_tokens: 50 } }

        expect(hook.call(response: response)).to be_nil
      end

      it 'returns early when response has no usage' do
        response = { model: 'claude-sonnet-4-20250514' }

        hook.call(response: response)

        expect(budget_enforcer).not_to have_received(:record!)
      end

      it 'defaults model to "unknown" when not present' do
        response = {
          usage: { input_tokens: 10, output_tokens: 5 }
        }

        hook.call(response: response)

        expect(budget_enforcer).to have_received(:record!).with(
          hash_including(model: 'unknown')
        )
      end

      it 'defaults token counts to 0 when not present' do
        response = {
          model: 'claude-sonnet-4-20250514',
          usage: {}
        }

        hook.call(response: response)

        expect(budget_enforcer).to have_received(:record!).with(
          model: 'claude-sonnet-4-20250514',
          input_tokens: 0,
          output_tokens: 0,
          cache_read_tokens: 0,
          cache_write_tokens: 0
        )
      end
    end
  end

  describe RubynCode::Hooks::BuiltIn::LoggingHook do
    let(:formatter) do
      instance_double('RubynCode::Output::Formatter', tool_call: nil, tool_result: nil)
    end

    subject(:hook) { described_class.new(formatter: formatter) }

    describe '#call' do
      it 'calls formatter.tool_call when result is nil (pre_tool_use)' do
        tool_input = { command: 'ls -la' }

        hook.call(tool_name: 'bash', tool_input: tool_input)

        expect(formatter).to have_received(:tool_call).with('bash', tool_input)
        expect(formatter).not_to have_received(:tool_result)
      end

      it 'calls formatter.tool_result when result is present (post_tool_use)' do
        hook.call(tool_name: 'bash', result: 'file.txt')

        expect(formatter).to have_received(:tool_result).with('bash', 'file.txt', success: true)
        expect(formatter).not_to have_received(:tool_call)
      end

      it 'returns nil' do
        result = hook.call(tool_name: 'bash', tool_input: {})

        expect(result).to be_nil
      end
    end
  end

  describe RubynCode::Hooks::BuiltIn::AutoCompactHook do
    # auto_compact is not yet defined on Context::Manager, so we use a plain
    # double to avoid instance_double verification failures.
    let(:context_manager) { double('ContextManager', auto_compact: nil) } # rubocop:disable RSpec/VerifiedDoubles
    let(:conversation) { double('Conversation') } # rubocop:disable RSpec/VerifiedDoubles

    subject(:hook) { described_class.new(context_manager: context_manager) }

    describe '#call' do
      it 'calls auto_compact on context_manager with conversation' do
        hook.call(conversation: conversation)

        expect(context_manager).to have_received(:auto_compact).with(conversation)
      end

      it 'returns early when context_manager is nil' do
        hook = described_class.new(context_manager: nil)

        expect(hook.call(conversation: conversation)).to be_nil
      end

      it 'returns early when conversation is nil' do
        hook.call(conversation: nil)

        expect(context_manager).not_to have_received(:auto_compact)
      end

      it 'rescues NoMethodError when auto_compact is not available' do
        allow(context_manager).to receive(:auto_compact).and_raise(NoMethodError)

        expect { hook.call(conversation: conversation) }.not_to raise_error
      end
    end
  end

  describe '.register_all!' do
    let(:registry) { instance_double('RubynCode::Hooks::Registry', on: nil) }
    let(:budget_enforcer) { instance_double('RubynCode::Observability::BudgetEnforcer') }
    let(:formatter) { instance_double('RubynCode::Output::Formatter') }
    let(:context_manager) { instance_double('RubynCode::Context::Manager') }

    it 'registers CostTrackingHook on :post_llm_call when budget_enforcer given' do
      described_class.register_all!(registry, budget_enforcer: budget_enforcer)

      expect(registry).to have_received(:on).with(
        :post_llm_call,
        an_instance_of(RubynCode::Hooks::BuiltIn::CostTrackingHook),
        priority: 10
      )
    end

    it 'registers LoggingHook on :pre_tool_use and :post_tool_use when formatter given' do
      described_class.register_all!(registry, formatter: formatter)

      expect(registry).to have_received(:on).with(
        :pre_tool_use,
        an_instance_of(RubynCode::Hooks::BuiltIn::LoggingHook),
        priority: 50
      )
      expect(registry).to have_received(:on).with(
        :post_tool_use,
        an_instance_of(RubynCode::Hooks::BuiltIn::LoggingHook),
        priority: 50
      )
    end

    it 'registers AutoCompactHook on :post_llm_call when context_manager given' do
      described_class.register_all!(registry, context_manager: context_manager)

      expect(registry).to have_received(:on).with(
        :post_llm_call,
        an_instance_of(RubynCode::Hooks::BuiltIn::AutoCompactHook),
        priority: 90
      )
    end

    it 'skips registration when dependencies are nil' do
      described_class.register_all!(registry, budget_enforcer: budget_enforcer)

      expect(registry).to have_received(:on).once
      expect(registry).to have_received(:on).with(:post_llm_call, anything, priority: 10)
    end

    it 'registers nothing when all deps are nil' do
      described_class.register_all!(registry)

      expect(registry).not_to have_received(:on)
    end
  end
end
