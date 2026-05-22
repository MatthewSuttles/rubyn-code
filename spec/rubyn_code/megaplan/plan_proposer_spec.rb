  # frozen_string_literal: true

require "spec_helper"
require "rubyn_code/megaplan/plan_proposer"

RSpec.describe RubynCode::Megaplan::PlanProposer do
  let(:llm_client) { instance_double("RubynCode::LLM::Client") }
  let(:proposer)   { described_class.new(llm_client: llm_client) }

  let(:valid_payload) do
    {
      "slug" => "soft-delete-posts",
      "feature" => "Soft-delete posts",
      "phases" => [
        {
          "number" => 1,
          "slug" => "add-column",
          "name" => "Add deleted_at column",
          "summary" => "Migration plus scope",
          "requirements_md" => "# Requirements\n",
          "design_md" => "# Design\n",
          "tasks_md" => "# Tasks\n- [ ] 1.1 add migration\n"
        }
      ]
    }
  end

  it "returns a normalized plan when the LLM returns clean JSON" do
    allow(llm_client).to receive(:chat).and_return(valid_payload.to_json)
    result = proposer.propose("Soft-delete posts")
    expect(result["slug"]).to eq("soft-delete-posts")
    expect(result["phases"].size).to eq(1)
    expect(result["phases"].first["name"]).to eq("Add deleted_at column")
  end

  it "strips a leading/trailing ``` fence the LLM sometimes emits" do
    fenced = "```json\n#{valid_payload.to_json}\n```"
    allow(llm_client).to receive(:chat).and_return(fenced)
    result = proposer.propose("Soft-delete posts")
    expect(result["phases"].size).to eq(1)
  end

  it "raises InvalidProposalError on unparseable JSON" do
    allow(llm_client).to receive(:chat).and_return("this is not json")
    expect { proposer.propose("anything") }
      .to raise_error(described_class::InvalidProposalError, /not valid JSON/)
  end

  it "raises when phases is empty" do
    allow(llm_client).to receive(:chat).and_return({ "phases" => [] }.to_json)
    expect { proposer.propose("anything") }
      .to raise_error(described_class::InvalidProposalError, /empty/)
  end

  it "raises when there are too many phases" do
    too_many = { "phases" => Array.new(13) { |i| valid_payload["phases"].first.merge("number" => i + 1) } }
    allow(llm_client).to receive(:chat).and_return(too_many.to_json)
    expect { proposer.propose("anything") }
      .to raise_error(described_class::InvalidProposalError, /too many phases/)
  end

  it "raises when a phase is missing a required field" do
    payload = JSON.parse(valid_payload.to_json)
    payload["phases"].first.delete("tasks_md")
    allow(llm_client).to receive(:chat).and_return(payload.to_json)
    expect { proposer.propose("anything") }
      .to raise_error(described_class::InvalidProposalError, /missing tasks_md/)
  end

  it "fills in a slug when the payload omits it" do
    payload = valid_payload.merge("slug" => "")
    allow(llm_client).to receive(:chat).and_return(payload.to_json)
    result = proposer.propose("Soft-Delete Posts!")
    expect(result["slug"]).to eq("soft-delete-posts")
  end

  it "rejects empty feature input" do
    expect { proposer.propose("   ") }.to raise_error(ArgumentError, /feature is required/)
  end

  it "passes the system prompt to the LLM" do
    allow(llm_client).to receive(:chat) do |kwargs|
      expect(kwargs[:system]).to include("megaplan")
      valid_payload.to_json
    end
    proposer.propose("Whatever")
  end
end

