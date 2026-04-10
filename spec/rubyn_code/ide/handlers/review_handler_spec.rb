# frozen_string_literal: true

require "spec_helper"
require "rubyn_code/ide/server"

RSpec.describe RubynCode::IDE::Handlers::ReviewHandler do
  let(:server)  { RubynCode::IDE::Server.new }
  let(:handler) { described_class.new(server) }

  let(:review_tool) do
    instance_double("RubynCode::Tools::ReviewPr")
  end

  before do
    allow(RubynCode::Tools::ReviewPr).to receive(:new).and_return(review_tool)
    server.workspace_path = "/test/project"
  end

  describe "accepts review" do
    it "returns { accepted: true } immediately" do
      allow(review_tool).to receive(:execute).and_return("")

      result = handler.call({ "baseBranch" => "main", "sessionId" => "r1" })
      expect(result["accepted"]).to eq(true)
      expect(result["sessionId"]).to eq("r1")
    end

    it "generates a sessionId if none provided" do
      allow(SecureRandom).to receive(:uuid).and_return("gen-review-id")
      allow(review_tool).to receive(:execute).and_return("")

      result = handler.call({})
      expect(result["sessionId"]).to eq("gen-review-id")
    end
  end

  describe "emits findings" do
    it "sends review/finding notifications for each finding" do
      review_output = <<~TEXT
        [warning] app/models/user.rb line 42: Missing validation
        Additional context for this finding
        [critical] lib/auth.rb line 10: SQL injection risk
      TEXT

      allow(review_tool).to receive(:execute).and_return(review_output)

      notifications = []
      allow(server).to receive(:notify) do |method, params|
        notifications << { "method" => method, "params" => params }
      end

      handler.call({ "baseBranch" => "main", "sessionId" => "r2" })
      sleep 0.5

      findings = notifications.select { |n| n["method"] == "review/finding" }
      expect(findings.size).to eq(2)

      first = findings.first["params"]
      expect(first["severity"]).to eq("warning")
      expect(first["index"]).to eq(0)

      second = findings.last["params"]
      expect(second["severity"]).to eq("critical")
      expect(second["index"]).to eq(1)
    end

    it "extracts file references from findings" do
      review_output = "[suggestion] config/routes.rb line 5: Unused route"
      allow(review_tool).to receive(:execute).and_return(review_output)

      notifications = []
      allow(server).to receive(:notify) do |method, params|
        notifications << { "method" => method, "params" => params }
      end

      handler.call({ "sessionId" => "r3" })
      sleep 0.5

      finding = notifications.find { |n| n["method"] == "review/finding" }
      expect(finding["params"]["file"]).to eq("config/routes.rb")
      expect(finding["params"]["line"]).to eq(5)
    end

    it "emits done status when review completes" do
      allow(review_tool).to receive(:execute).and_return("")

      notifications = []
      allow(server).to receive(:notify) do |method, params|
        notifications << { "method" => method, "params" => params }
      end

      handler.call({ "sessionId" => "r4" })
      sleep 0.5

      done = notifications.find do |n|
        n["method"] == "agent/status" && n["params"]["status"] == "done"
      end
      expect(done).not_to be_nil
    end

    it "emits reviewing status at start" do
      allow(review_tool).to receive(:execute).and_return("")

      notifications = []
      allow(server).to receive(:notify) do |method, params|
        notifications << { "method" => method, "params" => params }
      end

      handler.call({ "sessionId" => "r5" })
      sleep 0.5

      reviewing = notifications.find do |n|
        n["method"] == "agent/status" && n["params"]["status"] == "reviewing"
      end
      expect(reviewing).not_to be_nil
    end
  end

  describe "error handling" do
    it "emits error status when review tool raises" do
      allow(review_tool).to receive(:execute).and_raise(StandardError, "git error")

      notifications = []
      allow(server).to receive(:notify) do |method, params|
        notifications << { "method" => method, "params" => params }
      end

      handler.call({ "sessionId" => "r6" })
      sleep 0.5

      error_notif = notifications.find do |n|
        n["method"] == "agent/status" && n["params"]["status"] == "error"
      end
      expect(error_notif).not_to be_nil
      expect(error_notif["params"]["error"]).to include("git error")
    end
  end

  describe "extract_findings" do
    it "handles non-string input" do
      findings = handler.send(:extract_findings, nil)
      expect(findings).to eq([])
    end

    it "handles empty string" do
      findings = handler.send(:extract_findings, "")
      expect(findings).to eq([])
    end

    it "handles [nitpick] severity" do
      findings = handler.send(:extract_findings, "[nitpick] style issue")
      expect(findings.first[:severity]).to eq("nitpick")
    end

    it "appends continuation lines to the current finding" do
      text = "[warning] main issue\nmore detail\neven more"
      findings = handler.send(:extract_findings, text)
      expect(findings.size).to eq(1)
      expect(findings.first[:message]).to include("more detail")
      expect(findings.first[:message]).to include("even more")
    end
  end
end
