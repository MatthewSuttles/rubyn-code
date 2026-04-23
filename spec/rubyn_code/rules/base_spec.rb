# frozen_string_literal: true

require "spec_helper"

RSpec.describe RubynCode::Rules::Base do
  describe "default constants" do
    it "defines ID as nil" do
      expect(described_class.id).to be_nil
    end

    it "defines CATEGORY as nil" do
      expect(described_class.category).to be_nil
    end

    it "defines SEVERITY as nil" do
      expect(described_class.severity).to be_nil
    end

    it "defines RAILS_VERSIONS as an empty frozen array" do
      expect(described_class.rails_versions).to eq([])
      expect(described_class.rails_versions).to be_frozen
    end

    it "defines CONFIDENCE_FLOOR as 0.0" do
      expect(described_class.confidence_floor).to eq(0.0)
    end
  end

  describe ".applies_to?" do
    it "raises NotImplementedError" do
      expect { described_class.applies_to?({}) }
        .to raise_error(NotImplementedError, /applies_to\? must be implemented/)
    end
  end

  describe ".prompt_module" do
    it "raises NotImplementedError" do
      expect { described_class.prompt_module }
        .to raise_error(NotImplementedError, /prompt_module must be implemented/)
    end
  end

  describe ".validate" do
    it "raises NotImplementedError" do
      expect { described_class.validate({}, {}) }
        .to raise_error(NotImplementedError, /validate must be implemented/)
    end
  end

  context "with a concrete subclass" do
    let(:rule_class) do
      Class.new(described_class) do
        self.const_set(:ID, "TEST001")
        self.const_set(:CATEGORY, :testing)
        self.const_set(:SEVERITY, :medium)
        self.const_set(:RAILS_VERSIONS, [">= 6.0"].freeze)
        self.const_set(:CONFIDENCE_FLOOR, 0.8)

        def self.applies_to?(_diff_data)
          true
        end

        def self.prompt_module
          "Check for test issues"
        end

        def self.validate(_finding, _diff_data)
          true
        end
      end
    end

    it "exposes overridden constants via accessors" do
      expect(rule_class.id).to eq("TEST001")
      expect(rule_class.category).to eq(:testing)
      expect(rule_class.severity).to eq(:medium)
      expect(rule_class.rails_versions).to eq([">= 6.0"])
      expect(rule_class.confidence_floor).to eq(0.8)
    end

    it "delegates applies_to? to the subclass" do
      expect(rule_class.applies_to?({})).to be true
    end

    it "delegates prompt_module to the subclass" do
      expect(rule_class.prompt_module).to eq("Check for test issues")
    end

    it "delegates validate to the subclass" do
      expect(rule_class.validate({}, {})).to be true
    end
  end
end
