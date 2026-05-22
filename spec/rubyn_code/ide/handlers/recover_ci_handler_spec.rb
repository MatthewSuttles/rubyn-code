  # frozen_string_literal: true

require "spec_helper"
require "rubyn_code/ide/server"

RSpec.describe RubynCode::IDE::Handlers::RecoverCiHandler do
  let(:server)   { RubynCode::IDE::Server.new }
  let(:recovery) { instance_double("RubynCode::Megaplan::CiRecovery") }
  let(:handler)  { described_class.new(server, recovery: recovery) }

  let(:camel_params) do
    {
      "planId" => "plan-1",
      "phaseNumber" => 1,
      "branch" => "rubyn/feature-phase-01-add",
      "prNumber" => 42,
      "failingCheckName" => "test",
      "trimmedLog" => "AssertionError: x",
      "commitSha" => "abc123",
      "attemptNumber" => 1,
      "maxAttempts" => 3,
      "phase" => { "number" => 1, "name" => "Add", "summary" => "s" },
      "sessionId" => "session-1"
    }
  end

  before do
    @threads_before = Thread.list.dup
  end

  after do
    leaked = Thread.list - @threads_before
    leaked.each { |t| t.join(5) if t.alive? }
  end

  it "returns { accepted: true, sessionId } immediately" do
    allow(recovery).to receive(:recover).and_return({ "kind" => "fixed" })
    result = handler.call(camel_params)
    expect(result["accepted"]).to eq(true)
    expect(result["sessionId"]).to eq("session-1")
  end

  it "fires recovery/outcome with the agent's kind + summary" do
    allow(recovery).to receive(:recover).and_return({
                                                      "kind" => "fixed",
                                                      "commit_sha" => "deadbeef",
                                                      "summary" => "all good"
                                                    })

    notifications = []
    allow(server).to receive(:notify) do |method, params|
      notifications << { method: method, params: params }
    end

    handler.call(camel_params)
    sleep 0.3

    outcome = notifications.find { |n| n[:method] == "recovery/outcome" }
    expect(outcome).not_to be_nil
    expect(outcome[:params]["kind"]).to eq("fixed")
    expect(outcome[:params]["planId"]).to eq("plan-1")
    expect(outcome[:params]["phaseNumber"]).to eq(1)
    expect(outcome[:params]["commitSha"]).to eq("deadbeef")
  end

  it "fires agent/status done after a successful recovery" do
    allow(recovery).to receive(:recover).and_return({ "kind" => "fixed", "summary" => "ok" })
    notifications = []
    allow(server).to receive(:notify) do |method, params|
      notifications << { method: method, params: params }
    end

    handler.call(camel_params)
    sleep 0.3

    done = notifications.find { |n| n[:method] == "agent/status" && n[:params]["status"] == "done" }
    expect(done).not_to be_nil
  end

  it "normalizes camelCase keys to snake_case before passing to CiRecovery" do
    captured = nil
    allow(recovery).to receive(:recover) do |ctx|
      captured = ctx
      { "kind" => "fixed" }
    end
    handler.call(camel_params)
    sleep 0.3
    expect(captured["plan_id"]).to eq("plan-1")
    expect(captured["trimmed_log"]).to eq("AssertionError: x")
    expect(captured["attempt_number"]).to eq(1)
    expect(captured["max_attempts"]).to eq(3)
  end

  it "fires an errored recovery/outcome when the service raises" do
    allow(recovery).to receive(:recover).and_raise(StandardError, "boom")
    notifications = []
    allow(server).to receive(:notify) do |method, params|
      notifications << { method: method, params: params }
    end

    handler.call(camel_params)
    sleep 0.3

    outcome = notifications.find { |n| n[:method] == "recovery/outcome" }
    expect(outcome[:params]["kind"]).to eq("errored")
    expect(outcome[:params]["summary"]).to include("boom")
  end

  it "rejects nil params with a -32602 error" do
    result = handler.call(nil)
    expect(result["error"]["code"]).to eq(-32_602)
  end

  it "generates a sessionId when none is provided" do
    allow(recovery).to receive(:recover).and_return({ "kind" => "fixed" })
    allow(SecureRandom).to receive(:uuid).and_return("generated-id")
    result = handler.call(camel_params.merge("sessionId" => nil))
    expect(result["sessionId"]).to eq("generated-id")
  end
end
