# frozen_string_literal: true

require "spec_helper"

RSpec.describe RubynCode::Rules::Registry do
  # Define a named dummy rule so the registry can resolve constants.
  before(:all) do
    RubynCode::Rules.const_set(:DummyRule, Class.new(RubynCode::Rules::Base) {
      self.const_set(:ID, "DUMMY001")
      self.const_set(:CATEGORY, :testing)
      self.const_set(:SEVERITY, :low)
      self.const_set(:RAILS_VERSIONS, [">= 6.0"].freeze)
      self.const_set(:CONFIDENCE_FLOOR, 0.5)

      def self.name
        "RubynCode::Rules::DummyRule"
      end

      def self.applies_to?(_diff_data)
        true
      end

      def self.prompt_module
        "Dummy prompt"
      end

      def self.validate(_finding, _diff_data)
        true
      end
    })
  end

  after(:all) do
    RubynCode::Rules.send(:remove_const, :DummyRule) if RubynCode::Rules.const_defined?(:DummyRule)
  end

  let(:dummy_rule) { RubynCode::Rules::DummyRule }

  before { described_class.reset! }
  after { described_class.reset! }

  describe ".register and .get" do
    it "registers and retrieves a rule class by ID" do
      described_class.register(dummy_rule)
      expect(described_class.get("DUMMY001")).to eq(dummy_rule)
    end

    it "raises KeyError for an unknown rule" do
      expect { described_class.get("NONEXISTENT") }
        .to raise_error(KeyError, /Unknown rule/)
    end
  end

  describe ".all" do
    it "returns all registered rule classes" do
      described_class.register(dummy_rule)
      expect(described_class.all).to include(dummy_rule)
    end

    it "is accessible via the convenience RubynCode::Rules.all" do
      described_class.register(dummy_rule)
      expect(RubynCode::Rules.all).to include(dummy_rule)
    end
  end

  describe ".rule_ids" do
    it "returns sorted rule IDs" do
      described_class.register(dummy_rule)
      expect(described_class.rule_ids).to eq(["DUMMY001"])
    end
  end

  describe ".reset!" do
    it "clears all registered rules" do
      described_class.register(dummy_rule)
      described_class.reset!
      expect(described_class.all).to be_empty
    end
  end

  describe "registry picks up rules via .all.map(&:name)" do
    it "lists registered rule names" do
      described_class.register(dummy_rule)
      names = described_class.all.map(&:name)
      expect(names).to include("RubynCode::Rules::DummyRule")
    end
  end
end
