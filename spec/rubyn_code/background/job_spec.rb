# frozen_string_literal: true

require "spec_helper"

RSpec.describe RubynCode::Background::Job do
  let(:now) { Time.now }

  subject(:job) do
    described_class.new(
      id: "job-1", command: "echo hi", status: :running,
      result: nil, started_at: now, completed_at: nil
    )
  end

  it "creates with Data.define fields" do
    expect(job.id).to eq("job-1")
    expect(job.command).to eq("echo hi")
  end

  describe "status predicates" do
    it { expect(job.running?).to be true }
    it { expect(job.completed?).to be false }
    it { expect(job.error?).to be false }
    it { expect(job.timeout?).to be false }
  end

  describe "#duration" do
    it "returns nil for a running job" do
      expect(job.duration).to be_nil
    end

    it "calculates duration for a completed job" do
      completed = described_class.new(
        id: "j2", command: "ls", status: :completed,
        result: "ok", started_at: now - 5, completed_at: now
      )
      expect(completed.duration).to be_within(0.1).of(5.0)
    end
  end
end
