# frozen_string_literal: true

require "spec_helper"

RSpec.describe RubynCode::Learning::Instinct do
  let(:now) { Time.now }

  subject(:instinct) do
    described_class.new(
      id: "inst-1", project_path: "/proj", pattern: "Use RSpec matchers",
      context_tags: %w[rspec testing], confidence: 0.7, decay_rate: 0.05,
      times_applied: 3, times_helpful: 2, created_at: now, updated_at: now
    )
  end

  it "stores fields and clamps confidence" do
    expect(instinct.pattern).to eq("Use RSpec matchers")
    expect(instinct.confidence).to eq(0.7)
    high = described_class.new(id: "h", project_path: "/p", pattern: "x", confidence: 1.5)
    expect(high.confidence).to eq(1.0)
  end
end

RSpec.describe RubynCode::Learning::InstinctMethods do
  let(:now) { Time.now }
  let(:instinct) do
    RubynCode::Learning::Instinct.new(
      id: "i1", project_path: "/p", pattern: "test",
      confidence: 0.8, decay_rate: 0.05, updated_at: now
    )
  end

  describe ".apply_decay" do
    it "reduces confidence over time" do
      future = now + (7 * 86_400) # 7 days
      decayed = described_class.apply_decay(instinct, future)
      expect(decayed.confidence).to be < 0.8
      expect(decayed.confidence).to be > 0
    end

    it "does not decay when no time has passed" do
      same = described_class.apply_decay(instinct, now)
      expect(same.confidence).to eq(instinct.confidence)
    end
  end

  describe ".reinforce" do
    it "increases confidence when helpful" do
      reinforced = described_class.reinforce(instinct, helpful: true)
      expect(reinforced.confidence).to be > 0.8
      expect(reinforced.times_applied).to eq(1)
      expect(reinforced.times_helpful).to eq(1)
    end

    it "decreases confidence when not helpful" do
      weakened = described_class.reinforce(instinct, helpful: false)
      expect(weakened.confidence).to be < 0.8
      expect(weakened.times_applied).to eq(1)
      expect(weakened.times_helpful).to eq(0)
    end
  end
end
