# frozen_string_literal: true

require "spec_helper"

RSpec.describe RubynCode::Agent::Loop, "output token recovery" do
  let(:llm_client)      { instance_double(RubynCode::LLM::Client) }
  let(:tool_executor)   { instance_double(RubynCode::Tools::Executor, tool_definitions: []) }
  let(:context_manager) { instance_double(RubynCode::Context::Manager, check_compaction!: nil, track_usage: nil, estimated_tokens: 0, needs_compaction?: false) }
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

  def text_response(text, stop_reason: "end_turn")
    {
      content: [{ type: "text", text: text }],
      stop_reason: stop_reason,
      usage: { input_tokens: 10, output_tokens: 5 }
    }
  end

  def tool_response(name, input, id: "toolu_1", stop_reason: "tool_use")
    {
      content: [{ type: "tool_use", id: id, name: name, input: input }],
      stop_reason: stop_reason,
      usage: { input_tokens: 10, output_tokens: 5 }
    }
  end

  def truncated_text_response(text)
    text_response(text, stop_reason: "max_tokens")
  end

  def truncated_tool_response(name, input, id: "toolu_1")
    tool_response(name, input, id: id, stop_reason: "max_tokens")
  end

  describe "Tier 1: silent escalation on truncated tool-use response" do
    it "retries with escalated max_tokens without injecting a message" do
      # First call: tool response truncated at 8K
      truncated = truncated_tool_response("bash", { command: "echo hi" })
      # Second call: same request succeeds at 32K
      full_tool = tool_response("bash", { command: "echo hi" }, id: "toolu_2")
      # Third call: final text
      final = text_response("Done.")

      allow(llm_client).to receive(:chat).and_return(truncated, full_tool, final)
      allow(tool_executor).to receive(:execute).and_return("ok")

      result = agent_loop.send_message("run something")

      expect(result).to eq("Done.")

      # Verify escalated max_tokens was passed on retry
      expect(llm_client).to have_received(:chat).with(
        hash_including(max_tokens: RubynCode::Config::Defaults::ESCALATED_MAX_OUTPUT_TOKENS)
      ).at_least(:once)

      # No recovery messages should have been injected
      recovery_msgs = conversation.messages.select { |m|
        m[:role] == "user" && m[:content].is_a?(String) && m[:content].include?("Resume directly")
      }
      expect(recovery_msgs).to be_empty
    end
  end

  describe "Tier 2: multi-turn recovery on truncated text response" do
    it "injects continuation message and retries" do
      truncated = truncated_text_response("Here is the beginning of my anal")
      continued = text_response("ysis. Everything looks good.")

      allow(llm_client).to receive(:chat).and_return(truncated, continued)

      result = agent_loop.send_message("analyze this")

      expect(result).to eq("ysis. Everything looks good.")

      # Should have injected a recovery message
      recovery_msg = conversation.messages.find { |m|
        m[:role] == "user" && m[:content].is_a?(String) && m[:content].include?("Resume directly")
      }
      expect(recovery_msg).not_to be_nil
    end

    it "retries up to MAX_OUTPUT_TOKENS_RECOVERY_LIMIT times" do
      limit = RubynCode::Config::Defaults::MAX_OUTPUT_TOKENS_RECOVERY_LIMIT

      # Every response is truncated
      truncated = truncated_text_response("partial...")
      responses = Array.new(limit + 1) { truncated }

      allow(llm_client).to receive(:chat).and_return(*responses)

      result = agent_loop.send_message("write a novel")

      # Should have injected exactly `limit` recovery messages
      recovery_msgs = conversation.messages.select { |m|
        m[:role] == "user" && m[:content].is_a?(String) && m[:content].include?("Resume directly")
      }
      expect(recovery_msgs.size).to eq(limit)
    end
  end

  describe "Tier 3: returns partial response when recovery exhausted" do
    it "returns whatever text was collected" do
      limit = RubynCode::Config::Defaults::MAX_OUTPUT_TOKENS_RECOVERY_LIMIT

      responses = Array.new(limit + 1) { truncated_text_response("partial...") }
      allow(llm_client).to receive(:chat).and_return(*responses)

      result = agent_loop.send_message("big question")

      # Should still return something rather than crashing
      expect(result).to eq("partial...")
    end
  end

  describe "no recovery needed" do
    it "does not inject recovery messages for normal responses" do
      allow(llm_client).to receive(:chat).and_return(text_response("All good."))

      result = agent_loop.send_message("hi")

      expect(result).to eq("All good.")

      recovery_msgs = conversation.messages.select { |m|
        m[:role] == "user" && m[:content].is_a?(String) && m[:content].include?("Resume directly")
      }
      expect(recovery_msgs).to be_empty
    end
  end
end
