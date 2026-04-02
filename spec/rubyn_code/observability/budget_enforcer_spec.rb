# frozen_string_literal: true

require "spec_helper"

RSpec.describe RubynCode::Observability::BudgetEnforcer do
  let(:db) { setup_test_db }

  subject(:enforcer) do
    described_class.new(db, session_id: "test-session",
                        session_limit: 1.00, daily_limit: 2.00)
  end

  describe "#record!" do
    it "persists a cost record and returns it" do
      record = enforcer.record!(
        model: "claude-sonnet-4-20250514",
        input_tokens: 100_000, output_tokens: 10_000
      )
      expect(record).to be_a(RubynCode::Observability::CostRecord)
      expect(record.cost_usd).to be > 0
    end
  end

  describe "#check!" do
    it "does not raise when under budget" do
      expect { enforcer.check! }.not_to raise_error
    end

    it "raises BudgetExceededError when session budget exceeded" do
      # Record enough cost to exceed $1.00 session limit
      enforcer.record!(
        model: "claude-opus-4-20250514",
        input_tokens: 500_000, output_tokens: 500_000
      )
      expect { enforcer.check! }.to raise_error(RubynCode::BudgetExceededError, /Session budget/)
    end
  end

  describe "#remaining_budget" do
    it "returns full budget when no costs recorded" do
      expect(enforcer.remaining_budget).to be_within(0.01).of(1.00)
    end

    it "decreases after recording costs" do
      enforcer.record!(
        model: "claude-haiku-4-5",
        input_tokens: 100_000, output_tokens: 10_000
      )
      expect(enforcer.remaining_budget).to be < 1.00
    end
  end
end
