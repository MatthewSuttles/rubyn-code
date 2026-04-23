# frozen_string_literal: true

require "spec_helper"
require "rubyn_code/rules/base"
require "rubyn_code/rules/registry"
require "rubyn_code/rules/security/sec001_strong_params_leak"

RSpec.describe RubynCode::Rules::Security::Sec001StrongParamsLeak do
  let(:rule) { described_class }
  let(:fixture_dir) { File.join(__dir__, "../../../fixtures/security/sec001") }

  describe "constants" do
    it "defines ID as SEC001" do
      expect(rule.id).to eq("SEC001")
    end

    it "defines CATEGORY as :security" do
      expect(rule.category).to eq(:security)
    end

    it "defines SEVERITY as :high" do
      expect(rule.severity).to eq(:high)
    end

    it "defines RAILS_VERSIONS covering Rails 4+" do
      expect(rule.rails_versions).to eq([">= 4.0"])
    end

    it "defines CONFIDENCE_FLOOR as 0.85" do
      expect(rule.confidence_floor).to eq(0.85)
    end
  end

  describe ".applies_to?" do
    context "with controller files in diff" do
      it "returns true for a standard controller path" do
        diff_data = { files: ["app/controllers/users_controller.rb"] }
        expect(rule.applies_to?(diff_data)).to be true
      end

      it "returns true for a namespaced controller path" do
        diff_data = { files: ["app/controllers/admin/users_controller.rb"] }
        expect(rule.applies_to?(diff_data)).to be true
      end

      it "returns true when files are hashes with :path key" do
        diff_data = { files: [{ path: "app/controllers/orders_controller.rb" }] }
        expect(rule.applies_to?(diff_data)).to be true
      end

      it "returns true when files use string keys" do
        diff_data = { "files" => ["app/controllers/posts_controller.rb"] }
        expect(rule.applies_to?(diff_data)).to be true
      end
    end

    context "without controller files in diff" do
      it "returns false for model files only" do
        diff_data = { files: ["app/models/user.rb"] }
        expect(rule.applies_to?(diff_data)).to be false
      end

      it "returns false for service files only" do
        diff_data = { files: ["app/services/registration_service.rb"] }
        expect(rule.applies_to?(diff_data)).to be false
      end

      it "returns false for an empty files list" do
        diff_data = { files: [] }
        expect(rule.applies_to?(diff_data)).to be false
      end

      it "returns false for nil input" do
        expect(rule.applies_to?(nil)).to be false
      end

      it "returns false for an empty hash" do
        expect(rule.applies_to?({})).to be false
      end
    end
  end

  describe ".prompt_module" do
    it "returns a non-empty string" do
      expect(rule.prompt_module).to be_a(String)
      expect(rule.prompt_module.length).to be > 100
    end

    it "mentions SEC001 in the prompt" do
      expect(rule.prompt_module).to include("SEC001")
    end

    it "mentions permit! as a pattern" do
      expect(rule.prompt_module).to include("permit!")
    end

    it "mentions nested attributes" do
      expect(rule.prompt_module).to include("_attributes")
    end
  end

  describe ".validate" do
    let(:diff_data) { { files: ["app/controllers/users_controller.rb"] } }

    context "with valid findings" do
      it "accepts a permit! finding in a controller file" do
        finding = {
          file: "app/controllers/users_controller.rb",
          snippet: "params.permit!"
        }
        expect(rule.validate(finding, diff_data)).to be true
      end

      it "accepts a nested _attributes finding" do
        finding = {
          file: "app/controllers/users_controller.rb",
          snippet: 'params.require(:user).permit(:name, address_attributes: [:street])'
        }
        expect(rule.validate(finding, diff_data)).to be true
      end

      it "accepts an association _ids finding" do
        finding = {
          file: "app/controllers/users_controller.rb",
          snippet: "params.require(:user).permit(:name, role_ids: [])"
        }
        expect(rule.validate(finding, diff_data)).to be true
      end

      it "accepts a deep nested hash finding" do
        finding = {
          file: "app/controllers/users_controller.rb",
          snippet: "params.require(:team).permit(:name, settings: {})"
        }
        expect(rule.validate(finding, diff_data)).to be true
      end

      it "accepts findings with string keys" do
        finding = {
          "file" => "app/controllers/users_controller.rb",
          "snippet" => "params.permit!"
        }
        expect(rule.validate(finding, diff_data)).to be true
      end
    end

    context "with invalid findings" do
      it "rejects findings for non-controller files" do
        finding = {
          file: "app/models/user.rb",
          snippet: "params.permit!"
        }
        expect(rule.validate(finding, diff_data)).to be false
      end

      it "rejects findings for files not in the diff" do
        finding = {
          file: "app/controllers/orders_controller.rb",
          snippet: "params.permit!"
        }
        expect(rule.validate(finding, diff_data)).to be false
      end

      it "rejects findings with no matching pattern in snippet" do
        finding = {
          file: "app/controllers/users_controller.rb",
          snippet: "params.require(:user).permit(:name, :email)"
        }
        expect(rule.validate(finding, diff_data)).to be false
      end

      it "rejects nil finding" do
        expect(rule.validate(nil, diff_data)).to be false
      end

      it "rejects finding with missing file" do
        finding = { snippet: "params.permit!" }
        expect(rule.validate(finding, diff_data)).to be false
      end

      it "rejects finding with empty file" do
        finding = { file: "", snippet: "params.permit!" }
        expect(rule.validate(finding, diff_data)).to be false
      end
    end
  end

  describe "pattern detection on fixtures" do
    # Helper: read a fixture file and check if any pattern matches a line
    def fixture_matches?(filename)
      content = File.read(File.join(fixture_dir, filename))
      content.each_line.any? do |line|
        described_class::PATTERNS.any? { |pattern| line.match?(pattern) }
      end
    end

    context "positive fixtures (should match)" do
      it "detects permit! on raw params" do
        expect(fixture_matches?("positive_permit_bang.rb")).to be true
      end

      it "detects permit! after require" do
        expect(fixture_matches?("positive_require_permit_bang.rb")).to be true
      end

      it "detects nested _attributes with empty hash" do
        expect(fixture_matches?("positive_nested_attributes_hash.rb")).to be true
      end

      it "detects nested _attributes with array" do
        expect(fixture_matches?("positive_nested_attributes_array.rb")).to be true
      end

      it "detects association _ids arrays" do
        expect(fixture_matches?("positive_association_ids.rb")).to be true
      end

      it "detects deep nested hash permissions" do
        expect(fixture_matches?("positive_deep_nested_hash.rb")).to be true
      end

      it "detects nested _attributes with %i[] symbol array" do
        expect(fixture_matches?("positive_nested_attributes_symbols.rb")).to be true
      end
    end

    context "negative fixtures (should not match)" do
      it "does not match flat scalar permit" do
        expect(fixture_matches?("negative_flat_permit.rb")).to be false
      end

      it "does not match controller with no permit calls" do
        expect(fixture_matches?("negative_no_permit.rb")).to be false
      end

      it "does not match model file" do
        expect(fixture_matches?("negative_model_file.rb")).to be false
      end

      it "does not match service file" do
        expect(fixture_matches?("negative_service_file.rb")).to be false
      end
    end
  end

  describe "registry integration" do
    before { RubynCode::Rules::Registry.register(described_class) }

    it "is registered in the Rules::Registry" do
      expect(RubynCode::Rules::Registry.get("SEC001")).to eq(described_class)
    end
  end
end
