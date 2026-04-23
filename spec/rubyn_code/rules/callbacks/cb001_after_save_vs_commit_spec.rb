# frozen_string_literal: true

require "spec_helper"
require "rubyn_code/rules/callbacks/cb001_after_save_vs_commit"

RSpec.describe RubynCode::Rules::Callbacks::Cb001AfterSaveVsCommit do
  let(:rule) { described_class }

  describe "constants" do
    it "has the correct ID" do
      expect(rule.id).to eq("CB001")
    end

    it "has the correct category" do
      expect(rule.category).to eq(:callbacks)
    end

    it "has the correct severity" do
      expect(rule.severity).to eq(:high)
    end

    it "has the correct Rails version requirement" do
      expect(rule.rails_versions).to eq([">= 5.0"])
    end

    it "has the correct confidence floor" do
      expect(rule.confidence_floor).to eq(0.8)
    end
  end

  describe ".applies_to?" do
    it "returns true when a model file is changed" do
      diff_data = { changed_files: ["app/models/user.rb"] }
      expect(rule.applies_to?(diff_data)).to be true
    end

    it "returns true when a namespaced model file is changed" do
      diff_data = { changed_files: ["app/models/billing/subscription.rb"] }
      expect(rule.applies_to?(diff_data)).to be true
    end

    it "returns false when no model files are changed" do
      diff_data = { changed_files: ["app/controllers/users_controller.rb"] }
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
      diff_data = { changed_files: ["app/services/user_sync.rb", "lib/models/fake.rb"] }
      expect(rule.applies_to?(diff_data)).to be false
    end
  end

  describe ".prompt_module" do
    it "returns a non-empty string" do
      expect(rule.prompt_module).to be_a(String)
      expect(rule.prompt_module).not_to be_empty
    end

    it "mentions after_save and after_commit" do
      prompt = rule.prompt_module
      expect(prompt).to include("after_save")
      expect(prompt).to include("after_commit")
    end
  end

  describe ".validate" do
    let(:model_path) { "app/models/order.rb" }
    let(:base_diff_data) { { changed_files: [model_path], file_contents: {} } }

    # ── Positive fixtures (should flag) ──────────────────────────────

    context "POSITIVE: inline block enqueuing a job with perform_later" do
      let(:finding) do
        {
          line_content: 'after_save { SyncJob.perform_later(id) }',
          line_number: 10,
          file_path: model_path
        }
      end

      it "returns true" do
        expect(rule.validate(finding, base_diff_data)).to be true
      end
    end

    context "POSITIVE: inline block sending email with deliver_later" do
      let(:finding) do
        {
          line_content: 'after_save { OrderMailer.confirmation(self).deliver_later }',
          line_number: 12,
          file_path: model_path
        }
      end

      it "returns true" do
        expect(rule.validate(finding, base_diff_data)).to be true
      end
    end

    context "POSITIVE: inline block with broadcast" do
      let(:finding) do
        {
          line_content: 'after_save { broadcast_update }',
          line_number: 15,
          file_path: model_path
        }
      end

      it "returns true" do
        expect(rule.validate(finding, base_diff_data)).to be true
      end
    end

    context "POSITIVE: symbol callback with side-effect method name (enqueue)" do
      let(:finding) do
        {
          line_content: "after_save :enqueue_sync_job",
          line_number: 8,
          file_path: model_path
        }
      end

      it "returns true" do
        expect(rule.validate(finding, base_diff_data)).to be true
      end
    end

    context "POSITIVE: symbol callback with side-effect method name (send_notification)" do
      let(:finding) do
        {
          line_content: "after_save :send_notification_to_admin",
          line_number: 9,
          file_path: model_path
        }
      end

      it "returns true" do
        expect(rule.validate(finding, base_diff_data)).to be true
      end
    end

    context "POSITIVE: symbol callback with side-effect method name (trigger_webhook)" do
      let(:finding) do
        {
          line_content: "after_save :trigger_webhook",
          line_number: 11,
          file_path: model_path
        }
      end

      it "returns true" do
        expect(rule.validate(finding, base_diff_data)).to be true
      end
    end

    context "POSITIVE: symbol callback whose method body has perform_async" do
      let(:finding) do
        {
          line_content: "after_save :schedule_indexing",
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
                after_save :schedule_indexing

                private

                def schedule_indexing
                  IndexWorker.perform_async(id)
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

    context "POSITIVE: symbol callback whose method body uses Faraday" do
      let(:finding) do
        {
          line_content: "after_save :push_changes",
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
                after_save :push_changes

                private

                def push_changes
                  Faraday.post("https://api.example.com/orders", to_json)
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

    context "NEGATIVE: after_commit callback (already correct)" do
      let(:finding) do
        {
          line_content: "after_commit :enqueue_sync_job",
          line_number: 10,
          file_path: model_path
        }
      end

      it "returns false because line is after_commit, not after_save" do
        expect(rule.validate(finding, base_diff_data)).to be false
      end
    end

    context "NEGATIVE: after_save with a safe local method name" do
      let(:finding) do
        {
          line_content: "after_save :update_cached_name",
          line_number: 7,
          file_path: model_path
        }
      end

      let(:diff_data) do
        {
          changed_files: [model_path],
          file_contents: {
            model_path => <<~RUBY
              class Order < ApplicationRecord
                after_save :update_cached_name

                private

                def update_cached_name
                  self.cached_name = "Order #\#{id}"
                end
              end
            RUBY
          }
        }
      end

      it "returns false because the method has no side effects" do
        expect(rule.validate(finding, diff_data)).to be false
      end
    end

    context "NEGATIVE: after_save setting defaults (no side effect)" do
      let(:finding) do
        {
          line_content: "after_save :set_defaults",
          line_number: 4,
          file_path: model_path
        }
      end

      it "returns false" do
        expect(rule.validate(finding, base_diff_data)).to be false
      end
    end

    context "NEGATIVE: non-model file path" do
      let(:finding) do
        {
          line_content: "after_save :enqueue_sync_job",
          line_number: 10,
          file_path: "app/services/order_service.rb"
        }
      end

      it "returns false because file is not a model" do
        expect(rule.validate(finding, base_diff_data)).to be false
      end
    end

    context "NEGATIVE: inline block with only local attribute mutation" do
      let(:finding) do
        {
          line_content: 'after_save { update_column(:processed, true) }',
          line_number: 12,
          file_path: model_path
        }
      end

      it "returns false because update_column is local" do
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
  end

  describe "registry integration" do
    it "is registered in the rule registry" do
      expect(RubynCode::Rules::Registry.get("CB001")).to eq(described_class)
    end
  end
end
