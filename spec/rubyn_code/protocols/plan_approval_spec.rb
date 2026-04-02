# frozen_string_literal: true

require "spec_helper"

RSpec.describe RubynCode::Protocols::PlanApproval do
  let(:tty_prompt) { instance_double("TTY::Prompt") }

  before do
    allow(TTY::Prompt).to receive(:new).and_return(tty_prompt)
    allow($stdout).to receive(:puts)
  end

  describe ".request" do
    it "returns :approved when user confirms" do
      allow(tty_prompt).to receive(:yes?).and_return(true)

      result = described_class.request("Delete all files")
      expect(result).to eq(:approved)
    end

    it "returns :rejected when user declines" do
      allow(tty_prompt).to receive(:yes?).and_return(false)

      result = described_class.request("Drop database")
      expect(result).to eq(:rejected)
    end

    it "returns :rejected on input interrupt" do
      allow(tty_prompt).to receive(:yes?)
        .and_raise(TTY::Reader::InputInterrupt)

      result = described_class.request("Dangerous plan")
      expect(result).to eq(:rejected)
    end

    it "displays the plan text to stdout" do
      allow(tty_prompt).to receive(:yes?).and_return(true)

      expect($stdout).to receive(:puts).with(anything).at_least(:once)
      described_class.request("My plan details")
    end
  end
end
