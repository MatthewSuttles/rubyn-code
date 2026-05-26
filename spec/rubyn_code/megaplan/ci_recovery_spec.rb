  # frozen_string_literal: true

require "spec_helper"
require "rubyn_code/megaplan/ci_recovery"

RSpec.describe RubynCode::Megaplan::CiRecovery do
  let(:context) do
    {
      "plan_id" => "plan-1",
      "phase_number" => 1,
      "branch" => "rubyn/feature-phase-01-add-thing",
      "pr_number" => 42,
      "failing_check_name" => "test",
      "full_log" => "lots of log lines",
      "trimmed_log" => "AssertionError: expected x got y",
      "commit_sha" => "abc123",
      "attempt_number" => 1,
      "max_attempts" => 3,
      "phase" => {
        "number" => 1,
        "name" => "Add thing",
        "summary" => "Migration + scope"
      }
    }
  end

  it "returns kind: 'fixed' when the agent finishes without a NO_FIX marker" do
    invoker = ->(_prompt, _ctx) { { "text" => "Pushed a fix to the branch." } }
    outcome = described_class.new(agent_invoker: invoker).recover(context)
    expect(outcome["kind"]).to eq("fixed")
    expect(outcome["commit_sha"]).to eq("abc123")
  end

  it "returns kind: 'no_fix' when the agent emits NO_FIX_IDENTIFIED" do
    invoker = ->(_prompt, _ctx) { { "text" => "NO_FIX_IDENTIFIED: log shows an unrelated infra failure." } }
    outcome = described_class.new(agent_invoker: invoker).recover(context)
    expect(outcome["kind"]).to eq("no_fix")
    expect(outcome["summary"]).to include("infra failure")
  end

  it "returns kind: 'errored' when the agent invoker raises" do
    invoker = ->(_prompt, _ctx) { raise StandardError, "llm crashed" }
    outcome = described_class.new(agent_invoker: invoker).recover(context)
    expect(outcome["kind"]).to eq("errored")
    expect(outcome["summary"]).to include("llm crashed")
  end

  it "passes a prompt that includes attempt counts + trimmed log" do
    captured = nil
    invoker = ->(prompt, _ctx) { captured = prompt; { "text" => "fixed" } }
    described_class.new(agent_invoker: invoker).recover(context)
    expect(captured).to include("attempt 1 of 3")
    expect(captured).to include("AssertionError")
    expect(captured).to include("#42")
  end

  it "rejects missing required context fields" do
    incomplete = context.dup
    incomplete.delete("trimmed_log")
    outcome = described_class.new(agent_invoker: ->(_, _) {}).recover(incomplete)
    expect(outcome["kind"]).to eq("errored")
  end

  it "handles a plain string response (not a hash)" do
    invoker = ->(_prompt, _ctx) { "Just text." }
    outcome = described_class.new(agent_invoker: invoker).recover(context)
    expect(outcome["kind"]).to eq("fixed")
  end
end
