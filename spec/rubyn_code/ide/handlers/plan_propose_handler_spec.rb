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

  it "raises a JsonRpcError with INVALID_PARAMS when feature is empty" do
    expect { handler.call({ "feature" => "  " }) }
      .to raise_error(RubynCode::IDE::Protocol::JsonRpcError) do |err|
        expect(err.code).to eq(RubynCode::IDE::Protocol::INVALID_PARAMS)
        expect(err.message).to include("feature is required")
      end
  end

  it "raises a JsonRpcError with INVALID_PARAMS when feature is missing" do
    expect { handler.call({}) }
      .to raise_error(RubynCode::IDE::Protocol::JsonRpcError) do |err|
        expect(err.code).to eq(RubynCode::IDE::Protocol::INVALID_PARAMS)
      end
  end

  it "surfaces InvalidProposalError as a JsonRpcError with -32001" do
    allow(proposer).to receive(:propose)
      .and_raise(RubynCode::Megaplan::PlanProposer::InvalidProposalError, "phases is empty")
    expect { handler.call({ "feature" => "x" }) }
      .to raise_error(RubynCode::IDE::Protocol::JsonRpcError) do |err|
        expect(err.code).to eq(described_class::INVALID_PROPOSAL_CODE)
        expect(err.message).to include("phases is empty")
      end
  end

  it "lets other errors propagate (the server rescue converts them to INTERNAL_ERROR)" do
    allow(proposer).to receive(:propose).and_raise(StandardError, "llm down")
    expect { handler.call({ "feature" => "x" }) }.to raise_error(StandardError, "llm down")
  end
end
