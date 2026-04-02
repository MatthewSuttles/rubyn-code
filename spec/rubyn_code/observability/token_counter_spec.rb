# frozen_string_literal: true

require "spec_helper"

RSpec.describe RubynCode::Observability::TokenCounter do
  describe ".estimate" do
    it "returns 0 for nil" do
      expect(described_class.estimate(nil)).to eq(0)
    end

    it "returns 0 for empty string" do
      expect(described_class.estimate("")).to eq(0)
    end

    it "returns a reasonable estimate for English text" do
      text = "Hello, this is a test message with several words."
      result = described_class.estimate(text)
      expect(result).to be > 5
      expect(result).to be < 100
    end

    it "scales with text length" do
      short = described_class.estimate("hello")
      long = described_class.estimate("hello " * 100)
      expect(long).to be > short
    end
  end

  describe ".estimate_messages" do
    it "returns 0 for nil" do
      expect(described_class.estimate_messages(nil)).to eq(0)
    end

    it "returns 0 for empty array" do
      expect(described_class.estimate_messages([])).to eq(0)
    end

    it "returns a positive count for valid messages" do
      messages = [
        { role: "user", content: "What is Ruby?" },
        { role: "assistant", content: "Ruby is a programming language." }
      ]
      result = described_class.estimate_messages(messages)
      expect(result).to be > 10
    end
  end
end
