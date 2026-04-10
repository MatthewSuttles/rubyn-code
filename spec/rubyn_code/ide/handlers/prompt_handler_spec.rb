# frozen_string_literal: true

require "spec_helper"
require "rubyn_code/ide/server"
require "stringio"
require_relative "../support/server_helper"

RSpec.describe RubynCode::IDE::Handlers::PromptHandler do
  include IDEServerHelper

  let(:stdout_io) { StringIO.new }
  let(:stdin_io)  { StringIO.new }
  let(:server)    { build_test_server(stdin_io, stdout_io) }
  let(:handler)   { described_class.new(server) }

  # Stub the agent loop build to avoid real LLM calls
  let(:mock_agent) { IDEServerHelper::MockAgentLoop.new }

  before do
    allow(handler).to receive(:build_agent_loop).and_return(mock_agent)
  end

  describe "accepts prompt" do
    it "returns { accepted: true } immediately" do
      result = handler.call({ "text" => "Hello", "sessionId" => "s1" })
      expect(result["accepted"]).to eq(true)
      expect(result["sessionId"]).to eq("s1")
    end

    it "generates a sessionId if none provided" do
      allow(SecureRandom).to receive(:uuid).and_return("generated-uuid")
      result = handler.call({ "text" => "Hello" })
      expect(result["sessionId"]).to eq("generated-uuid")
    end
  end

  describe "emits stream/text notifications" do
    it "sends stream/text notifications via server.notify" do
      notifications = []
      allow(server).to receive(:notify) do |method, params|
        notifications << { "method" => method, "params" => params }
      end

      result = handler.call({ "text" => "test", "sessionId" => "s2" })

      # Wait for the background thread to complete
      sleep 0.3

      stream_texts = notifications.select { |n| n["method"] == "stream/text" }
      expect(stream_texts).not_to be_empty
      final_text = stream_texts.find { |n| n["params"]["final"] == true }
      expect(final_text).not_to be_nil
      expect(final_text["params"]["text"]).to include("Mock response")
    end
  end

  describe "emits agent/status notifications" do
    it "sends thinking, streaming, and done status notifications" do
      notifications = []
      allow(server).to receive(:notify) do |method, params|
        notifications << { "method" => method, "params" => params }
      end

      handler.call({ "text" => "test", "sessionId" => "s3" })
      sleep 0.3

      statuses = notifications
        .select { |n| n["method"] == "agent/status" }
        .map { |n| n["params"]["status"] }

      expect(statuses).to include("thinking")
      expect(statuses).to include("streaming")
      expect(statuses).to include("done")
    end
  end

  describe "context included" do
    it "passes activeFile in the enriched input" do
      allow(server).to receive(:notify)

      handler.call({
        "text" => "fix the bug",
        "sessionId" => "s4",
        "context" => {
          "activeFile" => "/src/main.rb"
        }
      })
      sleep 0.3

      expect(mock_agent.messages_sent.first).to include("[Active file: /src/main.rb]")
    end

    it "passes selection in the enriched input" do
      allow(server).to receive(:notify)

      handler.call({
        "text" => "refactor this",
        "sessionId" => "s5",
        "context" => {
          "selection" => {
            "startLine" => 10,
            "endLine" => 20,
            "text" => "selected code here"
          }
        }
      })
      sleep 0.3

      input = mock_agent.messages_sent.first
      expect(input).to include("Selection")
      expect(input).to include("lines 10-20")
      expect(input).to include("selected code here")
    end

    it "passes openFiles in the enriched input" do
      allow(server).to receive(:notify)

      handler.call({
        "text" => "check these",
        "sessionId" => "s6",
        "context" => {
          "openFiles" => ["a.rb", "b.rb"]
        }
      })
      sleep 0.3

      expect(mock_agent.messages_sent.first).to include("Open files: a.rb, b.rb")
    end
  end

  describe "cancel" do
    it "cancels a running session thread" do
      slow_agent = instance_double("SlowAgent")
      allow(slow_agent).to receive(:send_message) { sleep 10; "done" }
      allow(handler).to receive(:build_agent_loop).and_return(slow_agent)

      notifications = []
      allow(server).to receive(:notify) do |method, params|
        notifications << { "method" => method, "params" => params }
      end

      handler.call({ "text" => "slow task", "sessionId" => "cancel-me" })
      sleep 0.1 # let thread start

      handler.cancel_session("cancel-me")
      sleep 0.5

      statuses = notifications
        .select { |n| n["method"] == "agent/status" }
        .map { |n| n["params"]["status"] }

      expect(statuses).to include("cancelled")
    end
  end

  describe "concurrent prompts" do
    it "cancels the previous session when a new prompt uses the same sessionId" do
      slow_agent = instance_double("SlowAgent")
      call_count = 0
      allow(slow_agent).to receive(:send_message) do
        call_count += 1
        if call_count == 1
          sleep 10 # first call blocks
          "first"
        else
          "second"
        end
      end
      allow(handler).to receive(:build_agent_loop).and_return(slow_agent)

      notifications = []
      allow(server).to receive(:notify) do |method, params|
        notifications << { "method" => method, "params" => params }
      end

      handler.call({ "text" => "first", "sessionId" => "shared" })
      sleep 0.1

      handler.call({ "text" => "second", "sessionId" => "shared" })
      sleep 0.5

      statuses = notifications
        .select { |n| n["method"] == "agent/status" }
        .map { |n| n["params"]["status"] }

      # The first session should have been cancelled
      expect(statuses).to include("cancelled")
    end
  end

  describe "error handling" do
    it "emits error status when agent raises" do
      error_agent = instance_double("ErrorAgent")
      allow(error_agent).to receive(:send_message).and_raise(StandardError, "LLM failure")
      allow(handler).to receive(:build_agent_loop).and_return(error_agent)

      notifications = []
      allow(server).to receive(:notify) do |method, params|
        notifications << { "method" => method, "params" => params }
      end

      handler.call({ "text" => "fail", "sessionId" => "err1" })
      sleep 0.3

      error_notif = notifications.find do |n|
        n["method"] == "agent/status" && n["params"]["status"] == "error"
      end
      expect(error_notif).not_to be_nil
      expect(error_notif["params"]["error"]).to include("LLM failure")
    end
  end
end
