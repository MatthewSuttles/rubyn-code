# frozen_string_literal: true

require "spec_helper"
require "rubyn_code/rules/base"
require "rubyn_code/rules/registry"
require "rubyn_code/rules/callbacks/cb003_before_save_association"

RSpec.describe RubynCode::Rules::Callbacks::Cb003BeforeSaveAssociation do
  let(:rule) { described_class }

  describe "constants" do
    it "has the correct ID" do
      expect(rule.id).to eq("CB003")
    end

    it "has the correct category" do
      expect(rule.category).to eq(:callbacks)
    end

    it "has the correct severity" do
      expect(rule.severity).to eq(:medium)
    end

    it "has the correct Rails version requirement" do
      expect(rule.rails_versions).to eq([">= 5.0"])
    end

    it "has the correct confidence floor" do
      expect(rule.confidence_floor).to eq(0.75)
    end
  end

  describe ".applies_to?" do
    it "returns true when a model file is changed" do
      diff_data = { changed_files: ["app/models/order.rb"] }
      expect(rule.applies_to?(diff_data)).to be true
    end

    it "returns true when a namespaced model file is changed" do
      diff_data = { changed_files: ["app/models/billing/invoice.rb"] }
      expect(rule.applies_to?(diff_data)).to be true
    end

    it "returns false when no model files are changed" do
      diff_data = { changed_files: ["app/controllers/orders_controller.rb"] }
      expect(rule.applies_to?(diff_data)).to be false
    end

    it "returns false when changed_files is empty" do
      diff_data = { changed_files: [] }
      expect(rule.applies_to?(diff_data)).to be false
    end

    it "returns false when changed_files key is missing" do
      diff_data = {}
      expect(rule.applies_to?(diff_data)).to be false
    end

    it "returns false for non-model Ruby files" do
      diff_data = { changed_files: ["app/services/order_service.rb", "lib/models/fake.rb"] }
      expect(rule.applies_to?(diff_data)).to be false
    end
  end

  describe ".prompt_module" do
    it "returns a non-empty string" do
      expect(rule.prompt_module).to be_a(String)
      expect(rule.prompt_module.length).to be > 100
    end

    it "mentions CB003 in the prompt" do
      expect(rule.prompt_module).to include("CB003")
    end

    it "mentions before_save" do
      expect(rule.prompt_module).to include("before_save")
    end

    it "mentions association mutation concepts" do
      prompt = rule.prompt_module
      expect(prompt).to include("build")
      expect(prompt).to include("create")
    end
  end

  describe ".validate" do
    let(:model_path) { "app/models/order.rb" }
    let(:base_diff_data) { { changed_files: [model_path], file_contents: {} } }

    # ── Positive fixtures (should flag) ──────────────────────────────

    context "POSITIVE: inline block building a has_one association" do
      let(:finding) do
        {
          line_content: 'before_save { build_profile(name: "default") }',
          line_number: 10,
          file_path: model_path
        }
      end

      it "returns true" do
        expect(rule.validate(finding, base_diff_data)).to be true
      end
    end

    context "POSITIVE: inline block calling .build on a collection" do
      let(:finding) do
        {
          line_content: 'before_save { comments.build(body: "auto-generated") }',
          line_number: 12,
          file_path: model_path
        }
      end

      it "returns true" do
        expect(rule.validate(finding, base_diff_data)).to be true
      end
    end

    context "POSITIVE: inline block assigning Model.new to association" do
      let(:finding) do
        {
          line_content: 'before_save { self.profile = Profile.new(bio: "default") }',
          line_number: 14,
          file_path: model_path
        }
      end

      it "returns true" do
        expect(rule.validate(finding, base_diff_data)).to be true
      end
    end

    context "POSITIVE: inline block pushing new record into collection via <<" do
      let(:finding) do
        {
          line_content: 'before_save { tags << Tag.new(name: "draft") }',
          line_number: 16,
          file_path: model_path
        }
      end

      it "returns true" do
        expect(rule.validate(finding, base_diff_data)).to be true
      end
    end

    context "POSITIVE: inline block calling .create! on association" do
      let(:finding) do
        {
          line_content: 'before_save { notes.create!(body: "initialized") }',
          line_number: 18,
          file_path: model_path
        }
      end

      it "returns true" do
        expect(rule.validate(finding, base_diff_data)).to be true
      end
    end

    context "POSITIVE: inline block calling .update! on associated record" do
      let(:finding) do
        {
          line_content: 'before_save { profile.update!(synced_at: Time.current) }',
          line_number: 20,
          file_path: model_path
        }
      end

      it "returns true" do
        expect(rule.validate(finding, base_diff_data)).to be true
      end
    end

    context "POSITIVE: symbol callback with association-implying method name (create_default_)" do
      let(:finding) do
        {
          line_content: "before_save :create_default_profile",
          line_number: 8,
          file_path: model_path
        }
      end

      it "returns true" do
        expect(rule.validate(finding, base_diff_data)).to be true
      end
    end

    context "POSITIVE: symbol callback with association-implying method name (ensure_*_exists)" do
      let(:finding) do
        {
          line_content: "before_save :ensure_billing_address_exists",
          line_number: 9,
          file_path: model_path
        }
      end

      it "returns true" do
        expect(rule.validate(finding, base_diff_data)).to be true
      end
    end

    context "POSITIVE: symbol callback whose method body calls .build" do
      let(:finding) do
        {
          line_content: "before_save :prepare_shipment",
          line_number: 5,
          file_path: model_path
        }
      end

      let(:diff_data) do
        {
          changed_files: [model_path],
          file_contents: {
            model_path => <<~RUBY
              class Order < ApplicationRecord
                before_save :prepare_shipment

                private

                def prepare_shipment
                  shipments.build(status: "pending") unless shipments.any?
                end
              end
            RUBY
          }
        }
      end

      it "returns true by inspecting the method body" do
        expect(rule.validate(finding, diff_data)).to be true
      end
    end

    context "POSITIVE: symbol callback whose method body calls .create!" do
      let(:finding) do
        {
          line_content: "before_save :setup_audit_trail",
          line_number: 6,
          file_path: model_path
        }
      end

      let(:diff_data) do
        {
          changed_files: [model_path],
          file_contents: {
            model_path => <<~RUBY
              class Order < ApplicationRecord
                before_save :setup_audit_trail

                private

                def setup_audit_trail
                  audit_entries.create!(action: "initialized", actor: "system")
                end
              end
            RUBY
          }
        }
      end

      it "returns true by inspecting the method body" do
        expect(rule.validate(finding, diff_data)).to be true
      end
    end

    # ── Negative fixtures (should NOT flag) ──────────────────────────

    context "NEGATIVE: after_commit callback (different lifecycle hook)" do
      let(:finding) do
        {
          line_content: "after_commit :create_default_profile",
          line_number: 10,
          file_path: model_path
        }
      end

      it "returns false because line is after_commit, not before_save" do
        expect(rule.validate(finding, base_diff_data)).to be false
      end
    end

    context "NEGATIVE: before_save with local attribute mutation only" do
      let(:finding) do
        {
          line_content: 'before_save { self.slug = name.parameterize }',
          line_number: 7,
          file_path: model_path
        }
      end

      it "returns false because only self attributes are modified" do
        expect(rule.validate(finding, base_diff_data)).to be false
      end
    end

    context "NEGATIVE: before_save normalizing a local attribute (symbol callback)" do
      let(:finding) do
        {
          line_content: "before_save :normalize_name",
          line_number: 4,
          file_path: model_path
        }
      end

      let(:diff_data) do
        {
          changed_files: [model_path],
          file_contents: {
            model_path => <<~RUBY
              class Order < ApplicationRecord
                before_save :normalize_name

                private

                def normalize_name
                  self.name = name.strip.titleize
                end
              end
            RUBY
          }
        }
      end

      it "returns false because the method only modifies self" do
        expect(rule.validate(finding, diff_data)).to be false
      end
    end

    context "NEGATIVE: non-model file path" do
      let(:finding) do
        {
          line_content: "before_save :create_default_profile",
          line_number: 10,
          file_path: "app/services/order_service.rb"
        }
      end

      it "returns false because file is not a model" do
        expect(rule.validate(finding, base_diff_data)).to be false
      end
    end

    context "NEGATIVE: before_save setting a boolean flag" do
      let(:finding) do
        {
          line_content: 'before_save { self.processed = true }',
          line_number: 12,
          file_path: model_path
        }
      end

      it "returns false because only a scalar attribute is set" do
        expect(rule.validate(finding, base_diff_data)).to be false
      end
    end

    context "NEGATIVE: missing line_content" do
      let(:finding) do
        {
          line_content: "",
          line_number: 1,
          file_path: model_path
        }
      end

      it "returns false gracefully" do
        expect(rule.validate(finding, base_diff_data)).to be false
      end
    end

    context "NEGATIVE: before_save reading an association without mutating" do
      let(:finding) do
        {
          line_content: "before_save :cache_tag_count",
          line_number: 5,
          file_path: model_path
        }
      end

      let(:diff_data) do
        {
          changed_files: [model_path],
          file_contents: {
            model_path => <<~RUBY
              class Order < ApplicationRecord
                before_save :cache_tag_count

                private

                def cache_tag_count
                  self.tag_count = tags.count
                end
              end
            RUBY
          }
        }
      end

      it "returns false because the association is only read, not mutated" do
        expect(rule.validate(finding, diff_data)).to be false
      end
    end
  end

  describe "registry integration" do
    it "is registered in the rule registry" do
      expect(RubynCode::Rules::Registry.get("CB003")).to eq(described_class)
    end
  end
end
