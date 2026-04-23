# frozen_string_literal: true

require "spec_helper"
require "rubyn_code/rules/base"
require "rubyn_code/rules/registry"
require "rubyn_code/rules/active_record/ar004_missing_fk_index"

RSpec.describe RubynCode::Rules::ActiveRecord::Ar004MissingFkIndex do
  let(:rule) { described_class }
  let(:fixture_dir) { File.join(__dir__, "../../../fixtures/active_record/ar004") }

  describe "constants" do
    it "defines ID as AR004" do
      expect(rule.id).to eq("AR004")
    end

    it "defines CATEGORY as :active_record" do
      expect(rule.category).to eq(:active_record)
    end

    it "defines SEVERITY as :medium" do
      expect(rule.severity).to eq(:medium)
    end

    it "defines RAILS_VERSIONS covering Rails 5+" do
      expect(rule.rails_versions).to eq([">= 5.0"])
    end

    it "defines CONFIDENCE_FLOOR as 0.8" do
      expect(rule.confidence_floor).to eq(0.8)
    end
  end

  describe ".applies_to?" do
    context "with migration files in diff" do
      it "returns true for a standard migration path" do
        diff_data = { files: ["db/migrate/20240101120000_add_user_id_to_orders.rb"] }
        expect(rule.applies_to?(diff_data)).to be true
      end

      it "returns true for a timestamped migration" do
        diff_data = { files: ["db/migrate/20231215093000_create_invoices.rb"] }
        expect(rule.applies_to?(diff_data)).to be true
      end

      it "returns true when files are hashes with :path key" do
        diff_data = { files: [{ path: "db/migrate/20240101120000_add_refs.rb" }] }
        expect(rule.applies_to?(diff_data)).to be true
      end

      it "returns true when files use string keys" do
        diff_data = { "files" => ["db/migrate/20240101120000_add_fk.rb"] }
        expect(rule.applies_to?(diff_data)).to be true
      end
    end

    context "without migration files in diff" do
      it "returns false for model files only" do
        diff_data = { files: ["app/models/user.rb"] }
        expect(rule.applies_to?(diff_data)).to be false
      end

      it "returns false for controller files only" do
        diff_data = { files: ["app/controllers/users_controller.rb"] }
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

    it "mentions AR004 in the prompt" do
      expect(rule.prompt_module).to include("AR004")
    end

    it "mentions add_column as a pattern" do
      expect(rule.prompt_module).to include("add_column")
    end

    it "mentions add_reference" do
      expect(rule.prompt_module).to include("add_reference")
    end

    it "mentions add_index" do
      expect(rule.prompt_module).to include("add_index")
    end
  end

  describe ".validate" do
    let(:migration_path) { "db/migrate/20240101120000_add_user_id_to_orders.rb" }
    let(:diff_data) { { files: [migration_path] } }

    context "with valid findings" do
      it "accepts an add_column _id finding in a migration file" do
        finding = {
          file: migration_path,
          snippet: "add_column :orders, :user_id, :integer"
        }
        expect(rule.validate(finding, diff_data)).to be true
      end

      it "accepts an add_reference index: false finding" do
        finding = {
          file: migration_path,
          snippet: "add_reference :orders, :user, index: false"
        }
        expect(rule.validate(finding, diff_data)).to be true
      end

      it "accepts an add_reference with foreign_key but no index finding" do
        finding = {
          file: migration_path,
          snippet: "add_reference :orders, :user, foreign_key: true"
        }
        expect(rule.validate(finding, diff_data)).to be true
      end

      it "accepts findings with string keys" do
        finding = {
          "file" => migration_path,
          "snippet" => "add_column :orders, :user_id, :bigint"
        }
        expect(rule.validate(finding, diff_data)).to be true
      end
    end

    context "with invalid findings" do
      it "rejects findings for non-migration files" do
        finding = {
          file: "app/models/user.rb",
          snippet: "add_column :orders, :user_id, :integer"
        }
        expect(rule.validate(finding, diff_data)).to be false
      end

      it "rejects findings for files not in the diff" do
        finding = {
          file: "db/migrate/20240201000000_other_migration.rb",
          snippet: "add_column :orders, :user_id, :integer"
        }
        expect(rule.validate(finding, diff_data)).to be false
      end

      it "rejects findings with no matching pattern in snippet" do
        finding = {
          file: migration_path,
          snippet: "add_column :orders, :title, :string"
        }
        expect(rule.validate(finding, diff_data)).to be false
      end

      it "rejects nil finding" do
        expect(rule.validate(nil, diff_data)).to be false
      end

      it "rejects finding with missing file" do
        finding = { snippet: "add_column :orders, :user_id, :integer" }
        expect(rule.validate(finding, diff_data)).to be false
      end

      it "rejects finding with empty file" do
        finding = { file: "", snippet: "add_column :orders, :user_id, :integer" }
        expect(rule.validate(finding, diff_data)).to be false
      end
    end
  end

  describe "pattern detection on fixtures" do
    # Helper: read a fixture file and check if it has an unindexed FK
    def fixture_has_unindexed_fk?(filename)
      content = File.read(File.join(fixture_dir, filename))
      described_class.unindexed_fk?(content)
    end

    context "positive fixtures (should detect missing index)" do
      it "detects add_column :user_id without add_index" do
        expect(fixture_has_unindexed_fk?("positive_add_column_user_id.rb")).to be true
      end

      it "detects add_column :category_id bigint without add_index" do
        expect(fixture_has_unindexed_fk?("positive_add_column_bigint.rb")).to be true
      end

      it "detects add_reference with index: false" do
        expect(fixture_has_unindexed_fk?("positive_add_reference_index_false.rb")).to be true
      end

      it "detects add_reference with foreign_key but no index option" do
        expect(fixture_has_unindexed_fk?("positive_add_reference_fk_no_index.rb")).to be true
      end

      it "detects partially indexed multiple FK columns" do
        expect(fixture_has_unindexed_fk?("positive_add_column_multiple_fks.rb")).to be true
      end

      it "detects add_column :organization_id with options but no index" do
        expect(fixture_has_unindexed_fk?("positive_add_column_with_options.rb")).to be true
      end

      it "detects add_reference with foreign_key: true and index: false" do
        expect(fixture_has_unindexed_fk?("positive_add_reference_index_false_with_fk.rb")).to be true
      end
    end

    context "negative fixtures (should not flag)" do
      it "does not flag bare add_reference (defaults to index: true)" do
        expect(fixture_has_unindexed_fk?("negative_add_reference_default.rb")).to be false
      end

      it "does not flag add_reference with explicit index: true" do
        expect(fixture_has_unindexed_fk?("negative_add_reference_index_true.rb")).to be false
      end

      it "does not flag add_column with matching add_index" do
        expect(fixture_has_unindexed_fk?("negative_add_column_with_index.rb")).to be false
      end

      it "does not flag non-foreign-key columns" do
        expect(fixture_has_unindexed_fk?("negative_non_fk_column.rb")).to be false
      end

      it "does not flag model files" do
        expect(fixture_has_unindexed_fk?("negative_model_file.rb")).to be false
      end
    end
  end

  describe "registry integration" do
    before { RubynCode::Rules::Registry.register(described_class) }

    it "is registered in the Rules::Registry" do
      expect(RubynCode::Rules::Registry.get("AR004")).to eq(described_class)
    end
  end
end
