# frozen_string_literal: true

require "spec_helper"

RSpec.describe RubynCode::Agent::Loop, "background job integration" do
  let(:llm_client)      { instance_double(RubynCode::LLM::Client) }
  let(:tool_executor)   { instance_double(RubynCode::Tools::Executor, tool_definitions: []) }
  let(:context_manager) { instance_double(RubynCode::Context::Manager, check_compaction!: nil, track_usage: nil, estimated_tokens: 0, needs_compaction?: false, advance_turn!: nil) }
  let(:hook_runner)     { instance_double(RubynCode::Hooks::Runner, fire: nil) }
  let(:conversation)    { RubynCode::Agent::Conversation.new }
  let(:stall_detector)  { RubynCode::Agent::LoopDetector.new }
  let(:notifier)        { RubynCode::Background::Notifier.new }
  let(:background_worker) { RubynCode::Background::Worker.new(project_root: Dir.tmpdir, notifier: notifier) }

  subject(:agent_loop) do
    described_class.new(
      llm_client: llm_client,
      tool_executor: tool_executor,
      context_manager: context_manager,
      hook_runner: hook_runner,
      conversation: conversation,
      permission_tier: RubynCode::Permissions::Tier::UNRESTRICTED,
      stall_detector: stall_detector,
      background_manager: background_worker
    )
  end

  def text_response(text, stop_reason: "end_turn")
    {
      content: [{ type: "text", text: text }],
      stop_reason: stop_reason,
      usage: { input_tokens: 10, output_tokens: 5 }
    }
  end

  def tool_response(name, input, id: "toolu_1")
    {
      content: [{ type: "tool_use", id: id, name: name, input: input }],
      stop_reason: "tool_use",
      usage: { input_tokens: 10, output_tokens: 5 }
    }
  end

  describe "draining background notifications" do
    it "drains completed jobs before adding the user message" do
      # Simulate a job that completed between turns
      notifier.push({
        type: :job_completed,
        job_id: "abc12345-dead-beef",
        status: :completed,
        result: "9 tests, 0 failures",
        duration: 4.2
      })

      allow(llm_client).to receive(:chat).and_return(text_response("Tests passed!"))

      agent_loop.send_message("did the tests finish?")

      # The background notification should appear BEFORE the user message
      bg_index = conversation.messages.index { |m|
        m[:role] == "user" && m[:content].is_a?(String) && m[:content].include?("Background job results")
      }
      user_index = conversation.messages.index { |m|
        m[:role] == "user" && m[:content] == "did the tests finish?"
      }

      expect(bg_index).not_to be_nil
      expect(user_index).not_to be_nil
      expect(bg_index).to be < user_index
    end

    it "formats notifications with job ID, status, duration, and result" do
      notifier.push({
        type: :job_completed,
        job_id: "abc12345-dead-beef",
        status: :completed,
        result: "All tests passed",
        duration: 12.7
      })

      allow(llm_client).to receive(:chat).and_return(text_response("Great!"))

      agent_loop.send_message("check it")

      bg_msg = conversation.messages.find { |m|
        m[:role] == "user" && m[:content].is_a?(String) && m[:content].include?("Background job results")
      }

      expect(bg_msg[:content]).to include("abc12345")
      expect(bg_msg[:content]).to include("completed")
      expect(bg_msg[:content]).to include("12.7s")
      expect(bg_msg[:content]).to include("All tests passed")
    end

    it "drains notifications after tool execution within the loop" do
      # First call: LLM uses a tool
      tool_resp = tool_response("bash", { command: "echo hi" })
      # Second call: LLM responds with text
      final_resp = text_response("Done.")

      allow(llm_client).to receive(:chat).and_return(tool_resp, final_resp)
      allow(tool_executor).to receive(:execute) do
        # Simulate a background job completing while a tool runs
        notifier.push({
          type: :job_completed,
          job_id: "during-tool-exec",
          status: :completed,
          result: "finished during tool",
          duration: 1.0
        })
        "tool output"
      end

      agent_loop.send_message("do something")

      bg_msg = conversation.messages.find { |m|
        m[:role] == "user" && m[:content].is_a?(String) && m[:content].include?("finished during tool")
      }
      expect(bg_msg).not_to be_nil
    end
  end

  describe "pending background jobs" do
    it "keeps the loop running when jobs are still active" do
      # Stub pending checks: active for first two calls, then done
      pending_calls = 0
      allow(agent_loop).to receive(:pending_background_jobs?) do
        pending_calls += 1
        pending_calls <= 2
      end
      allow(agent_loop).to receive(:sleep) # stub wait_for_background_jobs polling

      call_count = 0
      allow(llm_client).to receive(:chat) do
        call_count += 1
        if call_count <= 2
          # First two calls: LLM responds with text while jobs are pending
          text_response("Waiting for results...")
        else
          # By third call, jobs are done
          text_response("All done!")
        end
      end

      result = agent_loop.send_message("run tests")

      # The loop should have continued past the first text response
      expect(call_count).to be >= 2
    end

    it "returns immediately when no background jobs are pending" do
      allow(llm_client).to receive(:chat).and_return(text_response("Hello!"))

      result = agent_loop.send_message("hi")

      expect(result).to eq("Hello!")
      expect(llm_client).to have_received(:chat).once
    end
  end

  describe "handles empty notification queue" do
    it "does not inject messages when queue is empty" do
      allow(llm_client).to receive(:chat).and_return(text_response("No jobs."))

      agent_loop.send_message("anything running?")

      bg_msgs = conversation.messages.select { |m|
        m[:role] == "user" && m[:content].is_a?(String) && m[:content].include?("Background job results")
      }
      expect(bg_msgs).to be_empty
    end
  end
end
