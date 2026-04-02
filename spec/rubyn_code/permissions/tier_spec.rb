# frozen_string_literal: true

RSpec.describe RubynCode::Permissions::Tier do
  describe ".all" do
    it "returns all four tiers" do
      expect(described_class.all).to contain_exactly(
        :ask_always, :allow_read, :autonomous, :unrestricted
      )
    end
  end

  describe "constants" do
    it "defines ASK_ALWAYS" do
      expect(described_class::ASK_ALWAYS).to eq(:ask_always)
    end

    it "defines ALLOW_READ" do
      expect(described_class::ALLOW_READ).to eq(:allow_read)
    end

    it "defines AUTONOMOUS" do
      expect(described_class::AUTONOMOUS).to eq(:autonomous)
    end

    it "defines UNRESTRICTED" do
      expect(described_class::UNRESTRICTED).to eq(:unrestricted)
    end
  end

  describe ".valid?" do
    it "returns true for a known tier" do
      expect(described_class.valid?(:autonomous)).to be true
    end

    it "returns false for an unknown tier" do
      expect(described_class.valid?(:bogus)).to be false
    end
  end
end
