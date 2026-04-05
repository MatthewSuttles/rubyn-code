# frozen_string_literal: true

require 'spec_helper'

RSpec.describe RubynCode::Agent::Loop, 'compaction on end_turn' do
  let(:conversation) { RubynCode::Agent::Conversation.new }
  let(:llm_client) { instance_double(RubynCode::LLM::Client) }
  let(:tool_executor) do
    instance_double(RubynCode::Tools::Executor, tool_definitions: [])
  end
  let(:context_manager) { RubynCode::Context::Manager.new(threshold: 100) }
  let(:hook_runner) do
    instance_double(RubynCode::Hooks::Runner, fire: nil)
  end

  let(:agent_loop) do
    described_class.new(
      llm_client: llm_client,
      tool_executor: tool_executor,
      context_manager: context_manager,
      hook_runner: hook_runner,
      conversation: conversation
    )
  end

  def text_response(text)
    RubynCode::LLM::Response.new(
      id: "msg_#{SecureRandom.hex(4)}",
      content: [RubynCode::LLM::TextBlock.new(text: text)],
      stop_reason: 'end_turn',
      usage: RubynCode::LLM::Usage.new(input_tokens: 10, output_tokens: 5)
    )
  end

  describe 'compaction triggers on text response when over threshold' do
    it 'runs compaction before returning when context exceeds threshold' do
      # Stuff the conversation with enough messages to exceed 100 token threshold
      50.times do |idx|
        conversation.add_user_message("Message #{idx} with some filler content to increase size")
        conversation.add_assistant_message(
          [{ type: 'text', text: "Response #{idx} with additional content" }]
        )
      end

      # Verify we're over threshold
      est = context_manager.estimated_tokens(conversation.messages)
      expect(est).to be > 100

      allow(llm_client).to receive(:chat).and_return(text_response('Final answer'))

      # check_compaction! should be called
      expect(context_manager).to receive(:check_compaction!).with(conversation).at_least(:once)

      agent_loop.send_message('one more question')
    end

    it 'runs compaction before calling the LLM when already over threshold' do
      # Pre-fill conversation past threshold
      50.times do |idx|
        conversation.add_user_message("Padding message #{idx}")
        conversation.add_assistant_message(
          [{ type: 'text', text: "Padding response #{idx}" }]
        )
      end

      allow(llm_client).to receive(:chat).and_return(text_response('Done'))

      # Should compact BEFORE the LLM call
      call_order = []
      allow(context_manager).to receive(:check_compaction!) do
        call_order << :compact
      end
      allow(llm_client).to receive(:chat) do
        call_order << :llm_call
        text_response('Done')
      end

      agent_loop.send_message('test')

      # Compaction should happen before the LLM call
      compact_idx = call_order.index(:compact)
      llm_idx = call_order.index(:llm_call)
      expect(compact_idx).not_to be_nil
      expect(compact_idx).to be < llm_idx
    end

    it 'does not compact when context is under threshold' do
      conversation.add_user_message('short')
      conversation.add_assistant_message([{ type: 'text', text: 'ok' }])

      allow(llm_client).to receive(:chat).and_return(text_response('hi'))

      # check_compaction! should NOT be called from compact_if_needed
      # (it may still be called from run_maintenance for tool responses)
      expect(context_manager).not_to receive(:check_compaction!)

      agent_loop.send_message('hello')
    end
  end
end
