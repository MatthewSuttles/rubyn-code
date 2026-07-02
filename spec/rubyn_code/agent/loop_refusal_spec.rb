# frozen_string_literal: true

require "spec_helper"

RSpec.describe RubynCode::Agent::Loop, "refusal handling" do
  let(:llm_client)      { instance_double(RubynCode::LLM::Client) }
  let(:tool_executor) do
    instance_double(RubynCode::Tools::Executor, tool_definitions: []).tap do |te|
      allow(te).to receive(:todo_store=)
    end
  end
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

  it "surfaces a clear message instead of an empty turn" do
    response = stub_claude_refusal_response(category: "cyber")
    allow(agent_loop).to receive(:call_llm).and_return(response)

    result = agent_loop.send_message("do something dangerous")

    expect(result).to eq("Claude's safety system declined this request (category: cyber).")
  end

  it "falls back to 'unknown' when stop_details has no category" do
    response = RubynCode::LLM::Response.new(
      id: "msg_test",
      content: [],
      stop_reason: "refusal",
      usage: RubynCode::LLM::Usage.new(input_tokens: 10, output_tokens: 0)
    )
    allow(agent_loop).to receive(:call_llm).and_return(response)

    result = agent_loop.send_message("hi")

    expect(result).to eq("Claude's safety system declined this request (category: unknown).")
  end
end
