# frozen_string_literal: true

require "spec_helper"
require "rubyn_code/rules/base"
require "rubyn_code/rules/registry"
require "rubyn_code/rules/active_record/ar002_update_column_bypass"

RSpec.describe RubynCode::Rules::ActiveRecord::Ar002UpdateColumnBypass do
  let(:rule) { described_class }
  let(:fixture_dir) { File.join(__dir__, "../../../fixtures/active_record/ar002") }

  describe "constants" do
    it "defines ID as AR002" do
      expect(rule.id).to eq("AR002")
    end

    it "defines CATEGORY as :active_record" do
      expect(rule.category).to eq(:active_record)
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
    context "with app/ Ruby files in diff" do
      it "returns true for a model file" do
        diff_data = { files: ["app/models/user.rb"] }
        expect(rule.applies_to?(diff_data)).to be true
      end

      it "returns true for a controller file" do
        diff_data = { files: ["app/controllers/users_controller.rb"] }
        expect(rule.applies_to?(diff_data)).to be true
      end

      it "returns true for a service file" do
        diff_data = { files: ["app/services/user_service.rb"] }
        expect(rule.applies_to?(diff_data)).to be true
      end

      it "returns true for a concern file" do
        diff_data = { files: ["app/models/concerns/trackable.rb"] }
        expect(rule.applies_to?(diff_data)).to be true
      end

      it "returns true when files are hashes with :path key" do
        diff_data = { files: [{ path: "app/models/order.rb" }] }
        expect(rule.applies_to?(diff_data)).to be true
      end

      it "returns true when files use string keys" do
        diff_data = { "files" => ["app/models/user.rb"] }
        expect(rule.applies_to?(diff_data)).to be true
      end
    end

    context "without app/ Ruby files in diff" do
      it "returns false for lib/ files" do
        diff_data = { files: ["lib/tasks/cleanup.rake"] }
        expect(rule.applies_to?(diff_data)).to be false
      end

      it "returns false for spec/ files" do
        diff_data = { files: ["spec/models/user_spec.rb"] }
        expect(rule.applies_to?(diff_data)).to be false
      end

      it "returns false for migration files" do
        diff_data = { files: ["db/migrate/20240101_add_users.rb"] }
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

    it "mentions AR002 in the prompt" do
      expect(rule.prompt_module).to include("AR002")
    end

    it "mentions update_column as a pattern" do
      expect(rule.prompt_module).to include("update_column")
    end

    it "mentions update_columns as a pattern" do
      expect(rule.prompt_module).to include("update_columns")
    end

    it "mentions update_all as a pattern" do
      expect(rule.prompt_module).to include("update_all")
    end
  end

  describe ".validate" do
    let(:diff_data) { { files: ["app/models/user.rb"] } }

    context "with valid findings" do
      it "accepts an update_column finding in a model file" do
        finding = {
          file: "app/models/user.rb",
          snippet: "update_column(:verified, true)"
        }
        expect(rule.validate(finding, diff_data)).to be true
      end

      it "accepts an update_columns finding" do
        finding = {
          file: "app/models/user.rb",
          snippet: 'update_columns(role: "admin", promoted_at: Time.current)'
        }
        expect(rule.validate(finding, diff_data)).to be true
      end

      it "accepts an update_all finding" do
        finding = {
          file: "app/models/user.rb",
          snippet: "User.where(active: false).update_all(deleted_at: Time.current)"
        }
        expect(rule.validate(finding, diff_data)).to be true
      end

      it "accepts findings with string keys" do
        finding = {
          "file" => "app/models/user.rb",
          "snippet" => "update_column(:admin, true)"
        }
        expect(rule.validate(finding, diff_data)).to be true
      end

      it "accepts findings in controller files" do
        controller_diff = { files: ["app/controllers/users_controller.rb"] }
        finding = {
          file: "app/controllers/users_controller.rb",
          snippet: "@user.update_column(:email_verified, true)"
        }
        expect(rule.validate(finding, controller_diff)).to be true
      end

      it "accepts findings in service files" do
        service_diff = { files: ["app/services/cleanup_service.rb"] }
        finding = {
          file: "app/services/cleanup_service.rb",
          snippet: "User.update_all(auth_token: nil)"
        }
        expect(rule.validate(finding, service_diff)).to be true
      end
    end

    context "with invalid findings" do
      it "rejects findings for non-app files" do
        finding = {
          file: "lib/tasks/cleanup.rake",
          snippet: "User.update_all(active: false)"
        }
        expect(rule.validate(finding, diff_data)).to be false
      end

      it "rejects findings for files not in the diff" do
        finding = {
          file: "app/models/order.rb",
          snippet: "update_column(:status, 'shipped')"
        }
        expect(rule.validate(finding, diff_data)).to be false
      end

      it "rejects findings with no matching pattern in snippet" do
        finding = {
          file: "app/models/user.rb",
          snippet: "update(name: 'Bob')"
        }
        expect(rule.validate(finding, diff_data)).to be false
      end

      it "rejects nil finding" do
        expect(rule.validate(nil, diff_data)).to be false
      end

      it "rejects finding with missing file" do
        finding = { snippet: "update_column(:admin, true)" }
        expect(rule.validate(finding, diff_data)).to be false
      end

      it "rejects finding with empty file" do
        finding = { file: "", snippet: "update_column(:admin, true)" }
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
      it "detects update_column in a model" do
        expect(fixture_matches?("positive_update_column.rb")).to be true
      end

      it "detects update_columns in a model" do
        expect(fixture_matches?("positive_update_columns.rb")).to be true
      end

      it "detects update_all on a scoped query" do
        expect(fixture_matches?("positive_update_all_scope.rb")).to be true
      end

      it "detects update_all on a class directly" do
        expect(fixture_matches?("positive_update_all_class.rb")).to be true
      end

      it "detects update_column in a controller" do
        expect(fixture_matches?("positive_update_column_controller.rb")).to be true
      end

      it "detects update_columns in a concern" do
        expect(fixture_matches?("positive_update_columns_concern.rb")).to be true
      end

      it "detects update_all with raw SQL string" do
        expect(fixture_matches?("positive_update_all_string_sql.rb")).to be true
      end
    end

    context "negative fixtures (should not match)" do
      it "does not match safe update methods" do
        expect(fixture_matches?("negative_safe_update.rb")).to be false
      end

      it "does not match model with no update calls" do
        expect(fixture_matches?("negative_no_update.rb")).to be false
      end

      it "does not match update_column in comments only" do
        expect(fixture_matches?("negative_update_in_comment.rb")).to be false
      end

      it "does not match overlapping method names" do
        expect(fixture_matches?("negative_method_name_overlap.rb")).to be false
      end

      it "does not match non-app files" do
        expect(fixture_matches?("negative_view_file.rb")).to be false
      end
    end
  end

  describe "registry integration" do
    before { RubynCode::Rules::Registry.register(described_class) }

    it "is registered in the Rules::Registry" do
      expect(RubynCode::Rules::Registry.get("AR002")).to eq(described_class)
    end
  end
end
