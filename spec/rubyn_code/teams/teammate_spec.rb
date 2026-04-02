# frozen_string_literal: true

require "spec_helper"

RSpec.describe RubynCode::Teams::Teammate do
  def build(status:)
    described_class.new(
      id: "t1", name: "coder", role: "dev", persona: nil,
      model: nil, status: status, metadata: {}, created_at: Time.now.iso8601
    )
  end

  describe "status predicates" do
    it "idle? is true for idle status" do
      expect(build(status: "idle").idle?).to be true
    end

    it "active? is true for active status" do
      expect(build(status: "active").active?).to be true
    end

    it "offline? is true for offline status" do
      expect(build(status: "offline").offline?).to be true
    end

    it "returns false for mismatched predicates" do
      mate = build(status: "idle")
      expect(mate.active?).to be false
      expect(mate.offline?).to be false
    end
  end

  describe "#to_h" do
    it "returns a hash with all fields" do
      mate = build(status: "idle")
      h = mate.to_h
      expect(h).to include(name: "coder", role: "dev", status: "idle")
    end
  end

  describe "VALID_STATUSES" do
    it "contains idle, active, offline" do
      expect(RubynCode::Teams::VALID_STATUSES).to eq(%w[idle active offline])
    end
  end
end
