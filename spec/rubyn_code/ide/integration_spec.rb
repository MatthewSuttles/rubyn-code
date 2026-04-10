# frozen_string_literal: true

require "spec_helper"
require "rubyn_code/ide/server"
require "stringio"
require "json"
require_relative "support/server_helper"

RSpec.describe "IDE Server Integration", :integration do
  include IDEServerHelper

  let(:stdin_io)  { StringIO.new }
  let(:stdout_io) { StringIO.new }
  let(:server)    { build_test_server(stdin_io, stdout_io) }

  def dispatch(line)
    server.public_handle_line(line)
  end

  def json_request(method, params = {}, id: 1)
    JSON.generate({ "jsonrpc" => "2.0", "id" => id, "method" => method, "params" => params })
  end

  def json_notification(method, params = {})
    JSON.generate({ "jsonrpc" => "2.0", "method" => method, "params" => params })
  end

  def collect_responses
    stdout_io.rewind
    read_all_messages(stdout_io)
  end

  describe "full prompt lifecycle" do
    before do
      allow(Dir).to receive(:exist?).and_return(false)
      allow(Dir).to receive(:chdir)
      allow(RubynCode::Tools::Registry).to receive(:load_all!)
      allow(RubynCode::Tools::Registry).to receive(:tool_names).and_return([])
      catalog_double = instance_double("RubynCode::Skills::Catalog", available: [])
      allow(RubynCode::Skills::Catalog).to receive(:new).and_return(catalog_double)
    end

    it "initialize -> prompt -> collect notifications -> verify stream/text" do
      # Step 1: Initialize
      dispatch(json_request("initialize", { "extensionVersion" => "1.0" }, id: 1))

      init_responses = collect_responses
      expect(init_responses.first["result"]["capabilities"]).to be_a(Hash)

      # Reset stdout for prompt phase
      stdout_io.truncate(0)
      stdout_io.rewind

      # Step 2: Stub the prompt handler's agent
      prompt_handler = server.handler_instance(:prompt)
      mock_agent = IDEServerHelper::MockAgentLoop.new
      allow(prompt_handler).to receive(:build_agent_loop).and_return(mock_agent)

      # Step 3: Send prompt
      dispatch(json_request("prompt", { "text" => "Hello world", "sessionId" => "int-1" }, id: 2))

      # Wait for background thread
      sleep 0.5

      messages = collect_responses

      # Should have the immediate response
      prompt_response = messages.find { |m| m["id"] == 2 }
      expect(prompt_response["result"]["accepted"]).to eq(true)

      # Should have stream/text notifications
      stream_texts = messages.select { |m| m["method"] == "stream/text" }
      expect(stream_texts).not_to be_empty

      final = stream_texts.find { |m| m["params"]["final"] == true }
      expect(final).not_to be_nil
      expect(final["params"]["text"]).to include("Mock response")

      # Should have agent/status notifications
      statuses = messages.select { |m| m["method"] == "agent/status" }.map { |m| m["params"]["status"] }
      expect(statuses).to include("thinking")
      expect(statuses).to include("done")
    end
  end

  describe "tool approval lifecycle" do
    it "prompt triggers tool -> tool/use notification -> approveToolUse -> tool/result" do
      # Register a custom handler that uses the approve flow
      approve_handler = server.handler_instance("approveToolUse") ||
                        server.handler_instances["approveToolUse"]

      notifications = []
      original_write = server.method(:public_handle_line)

      # Track all output
      allow(server).to receive(:write) do |hash|
        serialized = RubynCode::IDE::Protocol.serialize(hash)
        stdout_io.write(serialized)
      end

      # Simulate a tool requiring approval using ApproveToolUseHandler directly
      approval_result = nil
      waiter = Thread.new do
        approval_result = approve_handler.wait_for_approval("tool-req-1", "bash", { "command" => "ls" })
      end
      sleep 0.2

      # The handler should have emitted a tool/approval_required notification
      messages = collect_responses
      approval_notif = messages.find { |m| m["method"] == "tool/approval_required" }
      expect(approval_notif).not_to be_nil
      expect(approval_notif["params"]["requestId"]).to eq("tool-req-1")

      # Send approval
      dispatch(json_request("approveToolUse", {
        "requestId" => "tool-req-1",
        "approved"  => true
      }, id: 10))

      waiter.join(2)

      expect(approval_result).to eq(true)
    end
  end

  describe "review lifecycle" do
    it "sends review request -> receives findings -> completion" do
      review_tool = instance_double("RubynCode::Tools::ReviewPr")
      allow(RubynCode::Tools::ReviewPr).to receive(:new).and_return(review_tool)

      review_output = <<~TEXT
        [warning] app/models/user.rb line 15: N+1 query detected
        [critical] lib/auth.rb line 42: Hardcoded secret
      TEXT
      allow(review_tool).to receive(:execute).and_return(review_output)

      server.workspace_path = "/test"

      dispatch(json_request("review", { "baseBranch" => "main", "sessionId" => "rev-1" }, id: 5))

      # Wait for background thread
      sleep 0.5

      messages = collect_responses

      # Immediate response
      review_response = messages.find { |m| m["id"] == 5 }
      expect(review_response["result"]["accepted"]).to eq(true)

      # Findings
      findings = messages.select { |m| m["method"] == "review/finding" }
      expect(findings.size).to eq(2)

      severities = findings.map { |f| f["params"]["severity"] }
      expect(severities).to include("warning", "critical")

      # Done status
      done = messages.find { |m| m["method"] == "agent/status" && m["params"]["status"] == "done" }
      expect(done).not_to be_nil
      expect(done["params"]["summary"]).to include("2 finding(s)")
    end
  end

  describe "shutdown lifecycle" do
    it "handles multiple requests then shuts down cleanly" do
      server.on("ping") { |_params, _id| { "pong" => true } }

      dispatch(json_request("ping", {}, id: 1))
      dispatch(json_request("ping", {}, id: 2))
      dispatch(json_request("shutdown", {}, id: 3))

      messages = collect_responses
      expect(messages.size).to eq(3)

      pong1 = messages.find { |m| m["id"] == 1 }
      pong2 = messages.find { |m| m["id"] == 2 }
      shutdown = messages.find { |m| m["id"] == 3 }

      expect(pong1["result"]["pong"]).to eq(true)
      expect(pong2["result"]["pong"]).to eq(true)
      expect(shutdown["result"]["shutdown"]).to eq(true)
    end
  end

  describe "error handling" do
    it "handles malformed requests then recovers for valid ones" do
      server.on("echo") { |params, _id| { "echo" => params["msg"] } }

      # Malformed request
      dispatch("not json")
      # Valid request
      dispatch(json_request("echo", { "msg" => "works" }, id: 2))

      messages = collect_responses

      error_msg = messages.find { |m| m.key?("error") && m["error"]["code"] == -32_700 }
      expect(error_msg).not_to be_nil

      success_msg = messages.find { |m| m["id"] == 2 }
      expect(success_msg["result"]["echo"]).to eq("works")
    end

    it "handles missing method in otherwise valid JSON-RPC" do
      dispatch(json_request("doesNotExist", {}, id: 99))

      messages = collect_responses
      error = messages.find { |m| m["id"] == 99 }
      expect(error["error"]["code"]).to eq(-32_601)
    end

    it "handles handler exceptions without crashing" do
      server.on("explode") { |_p, _id| raise StandardError, "internal error" }

      dispatch(json_request("explode", {}, id: 50))
      dispatch(json_request("shutdown", {}, id: 51))

      messages = collect_responses

      error_msg = messages.find { |m| m["id"] == 50 }
      expect(error_msg["error"]["code"]).to eq(-32_603)

      shutdown_msg = messages.find { |m| m["id"] == 51 }
      expect(shutdown_msg["result"]["shutdown"]).to eq(true)
    end
  end

  describe "multiple sessions" do
    it "handles prompts with different sessionIds independently" do
      prompt_handler = server.handler_instance(:prompt)

      agents = {}
      allow(prompt_handler).to receive(:build_agent_loop) do |session_id, _workspace|
        agent = IDEServerHelper::MockAgentLoop.new
        agents[session_id] = agent
        agent
      end

      dispatch(json_request("prompt", { "text" => "task A", "sessionId" => "session-A" }, id: 1))
      dispatch(json_request("prompt", { "text" => "task B", "sessionId" => "session-B" }, id: 2))

      sleep 0.5

      messages = collect_responses

      # Both should have responses
      resp_a = messages.find { |m| m["id"] == 1 }
      resp_b = messages.find { |m| m["id"] == 2 }
      expect(resp_a["result"]["sessionId"]).to eq("session-A")
      expect(resp_b["result"]["sessionId"]).to eq("session-B")

      # Both should have stream/text for their respective sessions
      stream_a = messages.select { |m| m["method"] == "stream/text" && m["params"]["sessionId"] == "session-A" }
      stream_b = messages.select { |m| m["method"] == "stream/text" && m["params"]["sessionId"] == "session-B" }
      expect(stream_a).not_to be_empty
      expect(stream_b).not_to be_empty
    end
  end

  describe "full read_loop integration" do
    it "processes multiple messages from a StringIO input stream" do
      server.on("greet") { |params, _id| { "greeting" => "hello #{params['name']}" } }

      input_lines = [
        json_request("greet", { "name" => "Alice" }, id: 1),
        json_request("greet", { "name" => "Bob" }, id: 2),
        "",
        json_request("shutdown", {}, id: 3)
      ].join("\n")

      input_io = StringIO.new(input_lines)
      output_io = StringIO.new

      test_server = build_test_server(input_io, output_io)
      test_server.on("greet") { |params, _id| { "greeting" => "hello #{params['name']}" } }
      test_server.instance_variable_set(:@running, true)
      test_server.send(:read_loop)

      output_io.rewind
      messages = read_all_messages(output_io)

      expect(messages.size).to eq(3)

      greet1 = messages.find { |m| m["id"] == 1 }
      expect(greet1["result"]["greeting"]).to eq("hello Alice")

      greet2 = messages.find { |m| m["id"] == 2 }
      expect(greet2["result"]["greeting"]).to eq("hello Bob")

      shutdown = messages.find { |m| m["id"] == 3 }
      expect(shutdown["result"]["shutdown"]).to eq(true)
    end
  end
end
