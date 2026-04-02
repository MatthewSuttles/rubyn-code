# frozen_string_literal: true

RSpec.describe RubynCode::Context::Compactor do
  let(:llm_client) { double("llm_client") }
  subject(:compactor) { described_class.new(llm_client: llm_client, threshold: 100) }

  describe "#micro_compact!" do
    it "delegates to MicroCompact" do
      messages = []
      allow(RubynCode::Context::MicroCompact).to receive(:call).with(messages).and_return(0)

      expect(compactor.micro_compact!(messages)).to eq(0)
    end
  end

  describe "#auto_compact!" do
    it "delegates to AutoCompact" do
      messages = [{ role: "user", content: "hi" }]
      result = [{ role: "user", content: "[Context compacted]\n\nSummary" }]

      allow(RubynCode::Context::AutoCompact).to receive(:call).and_return(result)

      expect(compactor.auto_compact!(messages)).to eq(result)
    end

    it "raises when no LLM client is configured" do
      no_llm = described_class.new(llm_client: nil, threshold: 100)

      expect { no_llm.auto_compact!([]) }.to raise_error(RubynCode::Error)
    end
  end

  describe "#should_auto_compact?" do
    it "returns false when under threshold" do
      expect(compactor.should_auto_compact?([{ role: "user", content: "hi" }])).to be false
    end

    it "returns true when over threshold" do
      big = [{ role: "user", content: "x" * 1000 }]
      expect(compactor.should_auto_compact?(big)).to be true
    end
  end
end
