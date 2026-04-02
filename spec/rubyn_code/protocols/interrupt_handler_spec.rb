# frozen_string_literal: true

require "spec_helper"

RSpec.describe RubynCode::Protocols::InterruptHandler do
  after do
    described_class.reset!
    described_class.clear_callbacks!
  end

  describe ".setup!" do
    it "installs a SIGINT trap without raising" do
      expect { described_class.setup! }.not_to raise_error
    end

    it "resets the interrupted flag" do
      # Manually set interrupted state via internals
      described_class.instance_variable_set(:@interrupted, true)
      described_class.setup!
      expect(described_class.interrupted?).to be false
    end
  end

  describe ".interrupted?" do
    it "returns false by default" do
      described_class.reset!
      expect(described_class.interrupted?).to be false
    end
  end

  describe ".reset!" do
    it "clears the interrupted flag" do
      described_class.instance_variable_set(:@interrupted, true)
      described_class.reset!
      expect(described_class.interrupted?).to be false
    end
  end
end
