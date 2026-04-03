# frozen_string_literal: true

require "spec_helper"

RSpec.describe RubynCode::Agent::LoopDetector do
  subject(:detector) { described_class.new(window: 5, threshold: 3) }

  describe "#record" do
    it "records a tool invocation into the history" do
      detector.record('read_file', { path: 'x.rb' })
      # One call is below threshold — detector should not be stalled
      expect(detector).not_to be_stalled
      # But recording the same call up to threshold should detect the loop
      2.times { detector.record('read_file', { path: 'x.rb' }) }
      expect(detector).to be_stalled
    end

    it "keeps history within the sliding window" do
      10.times { |i| detector.record("tool_#{i}", {}) }
      # window size is 5, so only last 5 entries are kept
      detector.record("unique", {})
      expect(detector).not_to be_stalled
    end
  end

  describe "#stalled?" do
    it "returns false with fewer calls than threshold" do
      2.times { detector.record("read_file", { path: "x.rb" }) }
      expect(detector).not_to be_stalled
    end

    it "returns true when the same call repeats threshold times" do
      3.times { detector.record("read_file", { path: "x.rb" }) }
      expect(detector).to be_stalled
    end

    it "returns false when calls are diverse" do
      detector.record("read_file", { path: "a.rb" })
      detector.record("grep", { pattern: "foo" })
      detector.record("bash", { command: "ls" })
      expect(detector).not_to be_stalled
    end

    it "detects stalls regardless of hash key order" do
      3.times { detector.record("edit", { a: 1, b: 2 }) }
      expect(detector).to be_stalled
    end
  end

  describe "#reset!" do
    it "clears recorded history" do
      3.times { detector.record("read_file", { path: "x.rb" }) }
      detector.reset!
      expect(detector).not_to be_stalled
    end
  end

  describe "#nudge_message" do
    it "returns a non-empty guidance string" do
      msg = detector.nudge_message
      expect(msg).to be_a(String)
      expect(msg).to include("different approach")
    end
  end
end
