# frozen_string_literal: true

require "spec_helper"

RSpec.describe RubynCode::SubAgents::Summarizer do
  describe ".call" do
    it "returns empty string for nil input" do
      expect(described_class.call(nil)).to eq("")
    end

    it "returns empty string for empty input" do
      expect(described_class.call("")).to eq("")
    end

    it "passes through short text unchanged" do
      short = "This is a brief result."
      expect(described_class.call(short)).to eq(short)
    end

    it "strips leading and trailing whitespace" do
      expect(described_class.call("  hello  ")).to eq("hello")
    end

    it "truncates text exceeding max_length" do
      long_text = "a" * 3000
      result = described_class.call(long_text, max_length: 200)

      expect(result.length).to be <= 300 # head + suffix + tail
      expect(result).to include("[... output truncated ...]")
    end

    it "preserves beginning and end of long text" do
      lines = (1..100).map { |i| "Line #{i}: some content here" }.join("\n")
      result = described_class.call(lines, max_length: 500)

      expect(result).to include("Line 1:")
      expect(result).to include("Line 100:")
    end

    it "uses DEFAULT_MAX_LENGTH when no max_length given" do
      expect(described_class::DEFAULT_MAX_LENGTH).to eq(2000)
    end
  end
end
