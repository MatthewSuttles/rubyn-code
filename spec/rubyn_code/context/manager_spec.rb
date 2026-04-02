# frozen_string_literal: true

RSpec.describe RubynCode::Context::Manager do
  subject(:manager) { described_class.new(threshold: 500) }

  describe "#track_usage" do
    it "accumulates input and output tokens" do
      usage = double(input_tokens: 100, output_tokens: 50)
      manager.track_usage(usage)
      manager.track_usage(usage)

      expect(manager.total_input_tokens).to eq(200)
      expect(manager.total_output_tokens).to eq(100)
    end
  end

  describe "#estimated_tokens" do
    it "returns a reasonable estimate based on JSON character length" do
      messages = [{ role: "user", content: "a" * 400 }]
      estimate = manager.estimated_tokens(messages)

      expect(estimate).to be > 100
      expect(estimate).to be < 200
    end

    it "returns a positive integer for simple messages" do
      messages = [{ role: "user", content: "hello world" }]
      expect(manager.estimated_tokens(messages)).to be_a(Integer)
      expect(manager.estimated_tokens(messages)).to be > 0
    end
  end

  describe "#needs_compaction?" do
    it "returns false when under threshold" do
      messages = [{ role: "user", content: "short" }]
      expect(manager.needs_compaction?(messages)).to be false
    end

    it "returns true when over threshold" do
      messages = [{ role: "user", content: "x" * 5000 }]
      expect(manager.needs_compaction?(messages)).to be true
    end
  end

  describe "#reset!" do
    it "zeroes the counters" do
      manager.track_usage(double(input_tokens: 50, output_tokens: 25))
      manager.reset!

      expect(manager.total_input_tokens).to eq(0)
      expect(manager.total_output_tokens).to eq(0)
    end
  end
end
