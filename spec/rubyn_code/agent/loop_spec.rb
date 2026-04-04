# frozen_string_literal: true

require 'spec_helper'

RSpec.describe RubynCode::Agent::Loop do
  let(:llm_client)      { instance_double(RubynCode::LLM::Client) }
  let(:tool_executor)   { instance_double(RubynCode::Tools::Executor, tool_definitions: []) }
  let(:context_manager) do
    instance_double(
      RubynCode::Context::Manager,
      check_compaction!: nil,
      track_usage: nil,
      estimated_tokens: 0
    )
  end
  let(:hook_runner)     { instance_double(RubynCode::Hooks::Runner, fire: nil) }
  let(:conversation)    { RubynCode::Agent::Conversation.new }
  let(:stall_detector)  { RubynCode::Agent::LoopDetector.new }

  subject(:agent_loop) do
    described_class.new(
      llm_client: llm_client,
      tool_executor: tool_executor,
      context_manager: context_manager,
      hook_runner: hook_runner,
      conversation: conversation,
      permission_tier: RubynCode::Permissions::Tier::UNRESTRICTED,
      stall_detector: stall_detector
    )
  end

  # Response helpers — match the Hash branch in the loop's get_content/truncated?
  def text_response(text)
    {
      content: [{ type: 'text', text: text }],
      usage: { input_tokens: 10, output_tokens: 5 },
      stop_reason: 'end_turn'
    }
  end

  def tool_response(name, input, id: 'toolu_1')
    {
      content: [
        { type: 'tool_use', id: id, name: name, input: input }
      ],
      usage: { input_tokens: 10, output_tokens: 5 },
      stop_reason: 'tool_use'
    }
  end

  describe '#send_message' do
    context 'simple text response' do
      it 'returns the LLM text when no tools are called' do
        allow(llm_client).to receive(:chat).and_return(text_response('Hello!'))

        result = agent_loop.send_message('hi')

        expect(result).to eq('Hello!')
      end

      it 'adds the user message to the conversation' do
        allow(llm_client).to receive(:chat).and_return(text_response('Hi'))

        agent_loop.send_message('hello')

        user_msg = conversation.messages.find { |m| m[:role] == 'user' }
        expect(user_msg[:content]).to eq('hello')
      end

      it 'adds the assistant response to the conversation' do
        allow(llm_client).to receive(:chat).and_return(text_response('Hello!'))

        agent_loop.send_message('hi')

        assistant_msg = conversation.messages.find { |m| m[:role] == 'assistant' }
        expect(assistant_msg).not_to be_nil
      end

      it 'tracks usage after each LLM call' do
        allow(llm_client).to receive(:chat).and_return(text_response('Hello!'))

        agent_loop.send_message('hi')

        expect(context_manager).to have_received(:track_usage)
      end
    end

    context 'tool execution' do
      it 'executes tools and continues to the final text response' do
        tool_resp = tool_response('read_file', { path: 'x.rb' })
        final_resp = text_response('Done reading.')
        allow(llm_client).to receive(:chat).and_return(tool_resp, final_resp)
        allow(tool_executor).to receive(:execute).and_return('file contents')

        result = agent_loop.send_message('read x.rb')

        expect(result).to eq('Done reading.')
        expect(tool_executor).to have_received(:execute)
      end

      it 'appends tool results to the conversation' do
        tool_resp = tool_response('read_file', { path: 'x.rb' }, id: 'toolu_abc')
        final_resp = text_response('Done.')
        allow(llm_client).to receive(:chat).and_return(tool_resp, final_resp)
        allow(tool_executor).to receive(:execute).and_return('contents of x.rb')

        agent_loop.send_message('read x.rb')

        tool_result_msg = conversation.messages.find do |m|
          m[:role] == 'user' && m[:content].is_a?(Array) &&
            m[:content].any? { |b| b[:type] == 'tool_result' }
        end
        expect(tool_result_msg).not_to be_nil
      end

      it 'fires hooks during tool calls' do
        tool_resp = tool_response('bash', { command: 'ls' })
        final_resp = text_response('Done.')
        allow(llm_client).to receive(:chat).and_return(tool_resp, final_resp)
        allow(tool_executor).to receive(:execute).and_return('file list')

        agent_loop.send_message('list files')

        expect(hook_runner).to have_received(:fire).at_least(:once)
      end

      it 'runs compaction check after tool execution' do
        tool_resp = tool_response('bash', { command: 'ls' })
        final_resp = text_response('Done.')
        allow(llm_client).to receive(:chat).and_return(tool_resp, final_resp)
        allow(tool_executor).to receive(:execute).and_return('file list')

        agent_loop.send_message('list files')

        # check_compaction! runs in run_maintenance, which runs AFTER tool execution
        expect(context_manager).to have_received(:check_compaction!).with(conversation)
      end

      it 'tracks multiple tool call results in conversation' do
        # Two tool calls in one response
        multi_tool = {
          content: [
            { type: 'tool_use', id: 'toolu_1', name: 'read_file', input: { path: 'a.rb' } },
            { type: 'tool_use', id: 'toolu_2', name: 'read_file', input: { path: 'b.rb' } }
          ],
          usage: { input_tokens: 10, output_tokens: 5 },
          stop_reason: 'tool_use'
        }
        final_resp = text_response('Read both files.')
        allow(llm_client).to receive(:chat).and_return(multi_tool, final_resp)
        allow(tool_executor).to receive(:execute).and_return('contents')

        agent_loop.send_message('read both')

        expect(tool_executor).to have_received(:execute).twice
      end
    end

    context 'iteration limit' do
      it 'stops after max iterations and returns a warning' do
        loop_resp = tool_response('bash', { command: 'echo hi' })
        allow(llm_client).to receive(:chat).and_return(loop_resp)
        allow(tool_executor).to receive(:execute).and_return('ok')

        result = agent_loop.send_message('loop forever')

        expect(result).to include('maximum iteration limit')
      end
    end

    context 'permission denial' do
      let(:deny_list) { RubynCode::Permissions::DenyList.new(names: ['bash']) }
      let(:loop_with_deny) do
        described_class.new(
          llm_client: llm_client,
          tool_executor: tool_executor,
          context_manager: context_manager,
          hook_runner: hook_runner,
          conversation: conversation,
          permission_tier: RubynCode::Permissions::Tier::UNRESTRICTED,
          deny_list: deny_list,
          stall_detector: stall_detector
        )
      end

      it 'does not execute blocked tools' do
        tool_resp = tool_response('bash', { command: 'rm -rf /' })
        final_resp = text_response('Understood.')
        allow(llm_client).to receive(:chat).and_return(tool_resp, final_resp)
        # Stub execute so we can verify it was NOT called
        allow(tool_executor).to receive(:execute)

        loop_with_deny.send_message('run something')

        expect(tool_executor).not_to have_received(:execute)
      end

      it 'adds a blocked message to the conversation for denied tools' do
        tool_resp = tool_response('bash', { command: 'rm -rf /' })
        final_resp = text_response('Understood.')
        allow(llm_client).to receive(:chat).and_return(tool_resp, final_resp)
        allow(tool_executor).to receive(:execute)

        loop_with_deny.send_message('run something')

        blocked_msg = conversation.messages.any? do |m|
          m[:role] == 'user' && m[:content].is_a?(Array) &&
            m[:content].any? do |b|
              b[:content].to_s.downcase.include?('blocked') || b[:content].to_s.downcase.include?('denied')
            end
        end
        expect(blocked_msg).to be true
      end
    end

    context 'stall detection' do
      it 'injects a nudge when the same tool is called repeatedly' do
        stall = RubynCode::Agent::LoopDetector.new(window: 5, threshold: 2)
        stalling_loop = described_class.new(
          llm_client: llm_client,
          tool_executor: tool_executor,
          context_manager: context_manager,
          hook_runner: hook_runner,
          conversation: conversation,
          permission_tier: RubynCode::Permissions::Tier::UNRESTRICTED,
          stall_detector: stall
        )

        same_tool = tool_response('read_file', { path: 'x.rb' })
        final = text_response('OK, trying something else.')
        allow(llm_client).to receive(:chat).and_return(same_tool, same_tool, final)
        allow(tool_executor).to receive(:execute).and_return('content')

        result = stalling_loop.send_message('help')

        expect(result).to eq('OK, trying something else.')
        nudge_present = conversation.messages.any? do |m|
          m[:role] == 'user' && m[:content].is_a?(String) && m[:content].downcase.include?('repeating')
        end
        expect(nudge_present).to be true
      end
    end

    context 'budget enforcement' do
      it 'raises BudgetExceededError when budget is blown during tool loop' do
        budget = instance_double(RubynCode::Observability::BudgetEnforcer)
        allow(budget).to receive(:check!).and_raise(RubynCode::BudgetExceededError, 'Budget exceeded')

        loop_with_budget = described_class.new(
          llm_client: llm_client,
          tool_executor: tool_executor,
          context_manager: context_manager,
          hook_runner: hook_runner,
          conversation: conversation,
          permission_tier: RubynCode::Permissions::Tier::UNRESTRICTED,
          budget_enforcer: budget,
          stall_detector: stall_detector
        )

        # Budget check runs in run_maintenance, which only fires during tool loops
        tool_resp = tool_response('bash', { command: 'ls' })
        allow(llm_client).to receive(:chat).and_return(tool_resp)
        allow(tool_executor).to receive(:execute).and_return('ok')

        expect { loop_with_budget.send_message('do stuff') }
          .to raise_error(RubynCode::BudgetExceededError)
      end

      it 'does not raise when there is no budget enforcer' do
        allow(llm_client).to receive(:chat).and_return(text_response('Hello!'))

        expect { agent_loop.send_message('hi') }.not_to raise_error
      end
    end
  end
end
