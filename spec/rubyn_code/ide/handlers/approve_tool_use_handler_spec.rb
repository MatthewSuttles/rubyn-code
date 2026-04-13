# frozen_string_literal: true

require "spec_helper"
require "rubyn_code/ide/server"

RSpec.describe RubynCode::IDE::Handlers::ApproveToolUseHandler do
  let(:server)  { RubynCode::IDE::Server.new }
  let(:handler) { described_class.new(server) }

  describe "resolves approval" do
    it "signals the condition variable and resolves pending approval" do
      notifications = []
      allow(server).to receive(:notify) do |method, params|
        notifications << { "method" => method, "params" => params }
      end

      approval_result = nil
      waiter = Thread.new do
        approval_result = handler.wait_for_approval("req-1", "bash", { "command" => "ls" })
      end
      sleep 0.1

      result = handler.call({ "requestId" => "req-1", "approved" => true })
      waiter.join(2)

      expect(result["resolved"]).to eq(true)
      expect(result["requestId"]).to eq("req-1")
      expect(approval_result).to eq(true)
    end
  end

  describe "approve true" do
    it "sets approved flag to true" do
      allow(server).to receive(:notify)

      approved = nil
      waiter = Thread.new do
        approved = handler.wait_for_approval("req-2", "write_file", {})
      end
      sleep 0.1

      handler.call({ "requestId" => "req-2", "approved" => true })
      waiter.join(2)

      expect(approved).to eq(true)
    end
  end

  describe "approve false" do
    it "sets approved flag to false (denied)" do
      allow(server).to receive(:notify)

      approved = nil
      waiter = Thread.new do
        approved = handler.wait_for_approval("req-3", "bash", {})
      end
      sleep 0.1

      handler.call({ "requestId" => "req-3", "approved" => false })
      waiter.join(2)

      expect(approved).to eq(false)
    end
  end

  describe "unknown requestId" do
    it "returns resolved: false with error message" do
      result = handler.call({ "requestId" => "nonexistent", "approved" => true })
      expect(result["resolved"]).to eq(false)
      expect(result["error"]).to include("No pending request")
    end
  end

  describe "missing requestId" do
    it "returns resolved: false with error message" do
      result = handler.call({ "approved" => true })
      expect(result["resolved"]).to eq(false)
      expect(result["error"]).to include("Missing requestId")
    end
  end

  describe "#wait_for_approval" do
    it "emits tool/approval_required notification" do
      notifications = []
      allow(server).to receive(:notify) do |method, params|
        notifications << { "method" => method, "params" => params }
      end

      waiter = Thread.new do
        handler.wait_for_approval("req-4", "bash", { "command" => "rm -rf /" })
      end
      sleep 0.1

      # Approve to unblock the waiter
      handler.call({ "requestId" => "req-4", "approved" => true })
      waiter.join(2)

      approval_notif = notifications.find { |n| n["method"] == "tool/approval_required" }
      expect(approval_notif).not_to be_nil
      expect(approval_notif["params"]["requestId"]).to eq("req-4")
      expect(approval_notif["params"]["tool"]).to eq("bash")
      expect(approval_notif["params"]["params"]["command"]).to eq("rm -rf /")
    end
  end

  describe "#pending?" do
    it "returns false when no approvals are pending" do
      expect(handler.pending?).to be false
    end

    it "returns true when an approval is pending" do
      allow(server).to receive(:notify)

      Thread.new do
        handler.wait_for_approval("req-5", "bash", {})
      end
      sleep 0.1

      expect(handler.pending?).to be true

      # Clean up
      handler.call({ "requestId" => "req-5", "approved" => true })
      sleep 0.1
    end
  end
end
