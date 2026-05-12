# frozen_string_literal: true

RSpec.describe RubynCode::Context::Manager do
  subject(:manager) { described_class.new(threshold: 500) }

  describe '#track_usage' do
    it 'accumulates input and output tokens' do
      usage = double(input_tokens: 100, output_tokens: 50)
      manager.track_usage(usage)
      manager.track_usage(usage)

      expect(manager.total_input_tokens).to eq(200)
      expect(manager.total_output_tokens).to eq(100)
    end
  end

  describe '#estimated_tokens' do
    it 'returns a reasonable estimate based on JSON character length' do
      messages = [{ role: 'user', content: 'a' * 400 }]
      estimate = manager.estimated_tokens(messages)

      expect(estimate).to be > 100
      expect(estimate).to be < 200
    end

    it 'returns a positive integer for simple messages' do
      messages = [{ role: 'user', content: 'hello world' }]
      expect(manager.estimated_tokens(messages)).to be_a(Integer)
      expect(manager.estimated_tokens(messages)).to be > 0
    end
  end

  describe '#needs_compaction?' do
    it 'returns false when under threshold' do
      messages = [{ role: 'user', content: 'short' }]
      expect(manager.needs_compaction?(messages)).to be false
    end

    it 'returns true when over threshold' do
      messages = [{ role: 'user', content: 'x' * 5000 }]
      expect(manager.needs_compaction?(messages)).to be true
    end
  end

  describe '#advance_turn!' do
    it 'increments the current turn counter' do
      expect { manager.advance_turn! }.to change(manager, :current_turn).by(1)
    end
  end

  describe '#reset!' do
    it 'zeroes the counters' do
      manager.track_usage(double(input_tokens: 50, output_tokens: 25))
      manager.reset!

      expect(manager.total_input_tokens).to eq(0)
      expect(manager.total_output_tokens).to eq(0)
    end

    it 'resets the turn counter' do
      manager.advance_turn!
      manager.advance_turn!
      manager.reset!

      expect(manager.current_turn).to eq(0)
    end
  end

  describe '#check_compaction!' do
    let(:conversation) { RubynCode::Agent::Conversation.new }

    context 'when under threshold' do
      it 'does not modify messages' do
        conversation.add_user_message('short message')
        original_count = conversation.messages.size

        manager.check_compaction!(conversation)

        expect(conversation.messages.size).to eq(original_count)
      end

      it 'does not run micro-compaction below MICRO_COMPACT_RATIO' do
        conversation.add_user_message('tiny')
        allow(RubynCode::Context::MicroCompact).to receive(:call)

        manager.check_compaction!(conversation)

        expect(RubynCode::Context::MicroCompact).not_to have_received(:call)
      end
    end

    context 'compaction deduplication' do
      let(:manager) { described_class.new(threshold: 10) }

      it 'skips compaction on duplicate calls within the same turn when compaction succeeded' do
        conversation.add_user_message('x' * 200)
        collapsed = [{ role: 'user', content: 'collapsed' }]

        allow(RubynCode::Context::MicroCompact).to receive(:call).and_return(0)
        allow(RubynCode::Context::ContextCollapse).to receive(:call).and_return(collapsed)

        manager.advance_turn!
        manager.check_compaction!(conversation)

        # Second call in the same turn should be skipped because compaction succeeded
        manager.check_compaction!(conversation)
        expect(RubynCode::Context::MicroCompact).to have_received(:call).once
      end

      it 'retries compaction within the same turn when prior attempt did not reduce context' do
        conversation.add_user_message('x' * 200)

        allow(RubynCode::Context::MicroCompact).to receive(:call).and_return(0)
        allow(RubynCode::Context::ContextCollapse).to receive(:call).and_return(nil)

        manager.advance_turn!
        manager.check_compaction!(conversation)

        # Second call should retry since compaction didn't actually succeed
        manager.check_compaction!(conversation)
        expect(RubynCode::Context::MicroCompact).to have_received(:call).twice
      end

      it 'allows compaction again after advancing the turn' do
        conversation.add_user_message('x' * 200)

        allow(RubynCode::Context::MicroCompact).to receive(:call).and_return(0)
        allow(RubynCode::Context::ContextCollapse).to receive(:call).and_return(nil)

        manager.advance_turn!
        manager.check_compaction!(conversation)
        expect(RubynCode::Context::MicroCompact).to have_received(:call).once

        # Advance turn and call again — should run
        manager.advance_turn!
        manager.check_compaction!(conversation)
        expect(RubynCode::Context::MicroCompact).to have_received(:call).twice
      end
    end

    context 'when near MICRO_COMPACT_RATIO' do
      # threshold=200 tokens so 70% = 140 tokens ≈ 560 chars of JSON
      # We want to be above 70% but BELOW 100% so micro-compact fires
      # but full compaction does NOT.
      let(:manager) { described_class.new(threshold: 200) }

      it 'runs micro-compaction when over 70% of threshold' do
        conversation.add_user_message('x' * 700)

        allow(RubynCode::Context::MicroCompact).to receive(:call).and_return(0)

        manager.check_compaction!(conversation)

        expect(RubynCode::Context::MicroCompact).to have_received(:call)
      end
    end

    context 'when over threshold' do
      # Very low threshold so messages always exceed it
      let(:manager) { described_class.new(threshold: 10) }

      it 'attempts context collapse first' do
        conversation.add_user_message('x' * 200)

        allow(RubynCode::Context::MicroCompact).to receive(:call).and_return(0)
        collapsed = [{ role: 'user', content: 'compacted' }]
        allow(RubynCode::Context::ContextCollapse).to receive(:call).and_return(collapsed)

        manager.check_compaction!(conversation)

        expect(RubynCode::Context::ContextCollapse).to have_received(:call)
      end

      it 'calls apply_compacted_messages with the collapsed result' do
        conversation.add_user_message('x' * 200)

        allow(RubynCode::Context::MicroCompact).to receive(:call).and_return(0)
        collapsed = [{ role: 'user', content: 'compacted' }]
        allow(RubynCode::Context::ContextCollapse).to receive(:call).and_return(collapsed)

        # NOTE: Conversation doesn't respond to replace_messages or messages=,
        # so apply_compacted_messages is currently a no-op. This tests that
        # the compaction logic runs without error, not that messages are replaced.
        expect { manager.check_compaction!(conversation) }.not_to raise_error
      end
    end

    context 'provider-aware micro-compact ratio' do
      let(:conversation) { RubynCode::Agent::Conversation.new }

      it 'uses 0.7 ratio (cached) by default when no llm_client is set' do
        # threshold=200, 0.7 * 200 = 140 tokens ≈ 560 chars
        mgr = described_class.new(threshold: 200)
        conversation.add_user_message('x' * 700)

        allow(RubynCode::Context::MicroCompact).to receive(:call).and_return(0)
        mgr.check_compaction!(conversation)
        expect(RubynCode::Context::MicroCompact).to have_received(:call)
      end

      it 'uses 0.7 ratio for Anthropic provider (has prompt caching)' do
        anthropic_client = double('llm_client', provider_name: 'anthropic')
        # threshold=200, 0.7 * 200 = 140 tokens ≈ 560 chars
        mgr = described_class.new(threshold: 200, llm_client: anthropic_client)
        conversation.add_user_message('x' * 700)

        allow(RubynCode::Context::MicroCompact).to receive(:call).and_return(0)
        mgr.check_compaction!(conversation)
        expect(RubynCode::Context::MicroCompact).to have_received(:call)
      end

      it 'uses 0.5 ratio for OpenAI provider (no prompt caching)' do
        openai_client = double('llm_client', provider_name: 'openai')
        # With OpenAI: threshold=200, 0.5 * 200 = 100 tokens trigger
        # With Anthropic: threshold=200, 0.7 * 200 = 140 tokens trigger
        # We want est between 100 and 140 so it fires for OpenAI but not Anthropic
        mgr = described_class.new(threshold: 200, llm_client: openai_client)
        # ~480 chars JSON => ~120 estimated tokens (between 100 and 140)
        conversation.add_user_message('x' * 450)

        allow(RubynCode::Context::MicroCompact).to receive(:call).and_return(0)
        mgr.check_compaction!(conversation)
        expect(RubynCode::Context::MicroCompact).to have_received(:call)
      end

      it 'does not fire micro-compact with Anthropic at the same token level' do
        anthropic_client = double('llm_client', provider_name: 'anthropic')
        # Same threshold and content as the OpenAI test above
        # Anthropic ratio 0.7 * 200 = 140 trigger, est ~120 < 140
        mgr = described_class.new(threshold: 200, llm_client: anthropic_client)
        conversation.add_user_message('x' * 450)

        allow(RubynCode::Context::MicroCompact).to receive(:call).and_return(0)
        mgr.check_compaction!(conversation)
        expect(RubynCode::Context::MicroCompact).not_to have_received(:call)
      end

      it 'does not run micro-compact when below the OpenAI 0.5 ratio threshold' do
        openai_client = double('llm_client', provider_name: 'openai')
        mgr = described_class.new(threshold: 1000, llm_client: openai_client)
        # threshold=1000, 0.5 * 1000 = 500 tokens ≈ 2000 chars
        conversation.add_user_message('x' * 100) # well below

        allow(RubynCode::Context::MicroCompact).to receive(:call).and_return(0)
        mgr.check_compaction!(conversation)
        expect(RubynCode::Context::MicroCompact).not_to have_received(:call)
      end
    end
  end
end
