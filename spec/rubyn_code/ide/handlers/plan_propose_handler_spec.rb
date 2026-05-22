  # frozen_string_literal: true

require "spec_helper"
require "rubyn_code/ide/server"

RSpec.describe RubynCode::IDE::Handlers::PlanProposeHandler do
  let(:server)   { RubynCode::IDE::Server.new }
  let(:proposer) { instance_double("RubynCode::Megaplan::PlanProposer") }
  let(:handler)  { described_class.new(server, proposer: proposer) }

  let(:valid_plan) do
    {
      "slug" => "feature",
      "feature" => "Feature",
      "phases" => [
        {
          "number" => 1,
          "slug" => "phase-1",
          "name" => "Phase 1",
          "summary" => "s",
          "requirements_md" => "# req",
          "design_md" => "# design",
          "tasks_md" => "# tasks"
        }
      ]
    }
  end

  it "returns the proposer's plan when invocation succeeds" do
    allow(proposer).to receive(:propose).with("Add a thing").and_return(valid_plan)
    result = handler.call({ "feature" => "Add a thing" })
    expect(result["slug"]).to eq("feature")
    expect(result["phases"].size).to eq(1)
  end

  it "rejects an empty feature with a -32602 error" do
    result = handler.call({ "feature" => "  " })
    expect(result["error"]["code"]).to eq(-32_602)
    expect(result["error"]["message"]).to include("feature is required")
  end

  it "rejects a missing feature with a -32602 error" do
    result = handler.call({})
    expect(result["error"]["code"]).to eq(-32_602)
  end

  it "surfaces InvalidProposalError as a -32001 error" do
    allow(proposer).to receive(:propose)
      .and_raise(RubynCode::Megaplan::PlanProposer::InvalidProposalError, "phases is empty")
    result = handler.call({ "feature" => "x" })
    expect(result["error"]["code"]).to eq(described_class::INVALID_PROPOSAL_CODE)
    expect(result["error"]["message"]).to include("phases is empty")
  end

  it "surfaces any other error as -32000 (generic server error)" do
    allow(proposer).to receive(:propose).and_raise(StandardError, "llm down")
    result = handler.call({ "feature" => "x" })
    expect(result["error"]["code"]).to eq(-32_000)
    expect(result["error"]["message"]).to include("llm down")
  end
end
