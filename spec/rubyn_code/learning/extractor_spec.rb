# frozen_string_literal: true

require "spec_helper"

RSpec.describe RubynCode::Learning::Extractor do
  let(:llm_client) { instance_double("RubynCode::LLM::Client") }
  let(:messages) { [{ role: "user", content: "Fix the migration" }] }

  describe ".call" do
    it "returns extracted patterns from LLM response" do
      json_array = JSON.generate([{
        "type" => "error_resolution",
        "pattern" => "Check index before migration",
        "context_tags" => ["rails"],
        "confidence" => 0.6
      }])

      response = RubynCode::LLM::Response.new(
        id: "msg_1",
        content: [RubynCode::LLM::TextBlock.new(text: json_array)],
        stop_reason: "end_turn",
        usage: RubynCode::LLM::Usage.new(input_tokens: 50, output_tokens: 50)
      )
      allow(llm_client).to receive(:chat).and_return(response)

      results = described_class.call(messages, llm_client: llm_client, project_path: "/proj")

      expect(results.size).to eq(1)
      expect(results.first[:pattern]).to include("error_resolution")
      expect(results.first[:confidence]).to be_between(0.3, 0.8)
    end

    it "returns empty array when LLM fails" do
      allow(llm_client).to receive(:chat).and_raise(StandardError, "timeout")

      results = described_class.call(messages, llm_client: llm_client, project_path: "/proj")
      expect(results).to eq([])
    end

    it "returns empty array for empty messages" do
      results = described_class.call([], llm_client: llm_client, project_path: "/proj")
      expect(results).to eq([])
    end
  end
end
