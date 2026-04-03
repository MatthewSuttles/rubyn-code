# frozen_string_literal: true

require "spec_helper"

RSpec.describe RubynCode::Agent::Loop, "413 recovery" do
  let(:llm_client)      { instance_double(RubynCode::LLM::Client) }
  let(:tool_executor)   { instance_double(RubynCode::Tools::Executor, tool_definitions: []) }
  let(:context_manager) { RubynCode::Context::Manager.new(threshold: 999_999) }
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

  def text_response(text)
    {
      content: [{ type: "text", text: text }],
      stop_reason: "end_turn",
      usage: { input_tokens: 10, output_tokens: 5 }
    }
  end

  describe "prompt too long recovery" do
    it "compacts and retries on 413 error" do
      call_count = 0
      allow(llm_client).to receive(:chat) do
        call_count += 1
        if call_count == 1
          raise RubynCode::LLM::Client::PromptTooLongError, "prompt too long"
        else
          text_response("Recovered after compaction.")
        end
      end

      result = agent_loop.send_message("big question")

      expect(result).to eq("Recovered after compaction.")
      expect(call_count).to eq(2)
    end

    it "propagates error if retry also fails" do
      allow(llm_client).to receive(:chat)
        .and_raise(RubynCode::LLM::Client::PromptTooLongError, "still too long")

      expect {
        agent_loop.send_message("huge question")
      }.to raise_error(RubynCode::LLM::Client::PromptTooLongError)
    end
  end
end
