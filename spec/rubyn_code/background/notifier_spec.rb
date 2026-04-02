# frozen_string_literal: true

require "spec_helper"

RSpec.describe RubynCode::Background::Notifier do
  subject(:notifier) { described_class.new }

  describe "#push and #pending?" do
    it "starts with no pending notifications" do
      expect(notifier.pending?).to be false
    end

    it "marks pending after a push" do
      notifier.push({ type: :test })
      expect(notifier.pending?).to be true
    end
  end

  describe "#drain" do
    it "returns empty array when nothing is pending" do
      expect(notifier.drain).to eq([])
    end

    it "returns all pushed notifications and clears the queue" do
      notifier.push("first")
      notifier.push("second")

      drained = notifier.drain
      expect(drained).to eq(%w[first second])
      expect(notifier.pending?).to be false
    end

    it "is safe to call drain multiple times" do
      notifier.push("x")
      notifier.drain
      expect(notifier.drain).to eq([])
    end
  end
end
