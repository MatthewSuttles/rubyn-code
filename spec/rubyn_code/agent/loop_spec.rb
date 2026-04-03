# frozen_string_literal: true

require "spec_helper"

RSpec.describe RubynCode::Agent::Loop do
  let(:llm_client)      { instance_double(RubynCode::LLM::Client) }
  let(:tool_executor)   { instance_double(RubynCode::Tools::Executor, tool_definitions: []) }
  let(:context_manager) { instance_double(RubynCode::Context::Manager, check_compaction!: nil, track_usage: nil) }
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
    { content: [{ type: "text", text: text }], usage: { input_tokens: 10, output_tokens: 5 } }
  end

  def tool_response(name, input, id: "toolu_1")
    {
      content: [
        { type: "tool_use", id: id, name: name, input: input }
      ],
      usage: { input_tokens: 10, output_tokens: 5 }
    }
  end

  describe "#send_message" do
    it "returns text when the LLM responds with no tool calls" do
      allow(llm_client).to receive(:chat).and_return(text_response("Hello!"))
      result = agent_loop.send_message("hi")
      expect(result).to eq("Hello!")
    end

    it "executes tools and continues when LLM returns tool_use" do
      tool_resp = tool_response("read_file", { path: "x.rb" })
      final_resp = text_response("Done reading.")
      allow(llm_client).to receive(:chat).and_return(tool_resp, final_resp)
      allow(tool_executor).to receive(:execute).and_return("file contents")

      result = agent_loop.send_message("read x.rb")
      expect(result).to eq("Done reading.")
      expect(tool_executor).to have_received(:execute)
    end

    it "stops after max iterations" do
      loop_resp = tool_response("bash", { command: "echo hi" })
      allow(llm_client).to receive(:chat).and_return(loop_resp)
      allow(tool_executor).to receive(:execute).and_return("ok")

      result = agent_loop.send_message("loop forever")
      expect(result).to include("maximum iteration limit")
    end

    it "handles permission denials" do
      tool_resp = tool_response("bash", { command: "rm -rf /" })
      final_resp = text_response("Understood.")
      allow(llm_client).to receive(:chat).and_return(tool_resp, final_resp)

      deny_list = RubynCode::Permissions::DenyList.new(names: ["bash"])
      loop_with_deny = described_class.new(
        llm_client: llm_client,
        tool_executor: tool_executor,
        context_manager: context_manager,
        hook_runner: hook_runner,
        conversation: conversation,
        permission_tier: RubynCode::Permissions::Tier::UNRESTRICTED,
        deny_list: deny_list,
        stall_detector: stall_detector
      )

      result = loop_with_deny.send_message("run something")
      expect(result).to eq("Understood.")
      expect(conversation.messages.any? { |m|
        m[:content].is_a?(Array) && m[:content].any? { |b| b[:content]&.include?("blocked") }
      }).to be true
    end

    it "detects stalls and injects a nudge" do
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

      same_tool = tool_response("read_file", { path: "x.rb" })
      final = text_response("OK, trying something else.")
      allow(llm_client).to receive(:chat).and_return(same_tool, same_tool, final)
      allow(tool_executor).to receive(:execute).and_return("content")

      result = stalling_loop.send_message("help")
      expect(result).to eq("OK, trying something else.")
      nudge_present = conversation.messages.any? { |m|
        m[:role] == "user" && m[:content].is_a?(String) && m[:content].include?("repeating")
      }
      expect(nudge_present).to be true
    end
  end
end
