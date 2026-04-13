# frozen_string_literal: true

require "spec_helper"
require "rubyn_code/ide/server"

RSpec.describe RubynCode::IDE::Handlers::AcceptEditHandler do
  let(:server)  { RubynCode::IDE::Server.new }
  let(:handler) { described_class.new(server) }

  describe "accepts edit" do
    it "returns applied: true when accepted" do
      allow(server).to receive(:notify)

      accepted = nil
      waiter = Thread.new do
        accepted = handler.wait_for_acceptance("edit-1", "/path/to/file.rb", "- old\n+ new")
      end
      sleep 0.1

      result = handler.call({ "editId" => "edit-1", "accepted" => true })
      waiter.join(2)

      expect(result["applied"]).to eq(true)
      expect(accepted).to eq(true)
    end
  end

  describe "rejects edit" do
    it "returns applied: false when rejected" do
      allow(server).to receive(:notify)

      accepted = nil
      waiter = Thread.new do
        accepted = handler.wait_for_acceptance("edit-2", "/path/to/file.rb", "- old\n+ new")
      end
      sleep 0.1

      result = handler.call({ "editId" => "edit-2", "accepted" => false })
      waiter.join(2)

      expect(result["applied"]).to eq(false)
      expect(accepted).to eq(false)
    end
  end

  describe "unknown editId" do
    it "returns applied: false with error message" do
      result = handler.call({ "editId" => "nonexistent", "accepted" => true })
      expect(result["applied"]).to eq(false)
      expect(result["error"]).to include("No pending edit")
    end
  end

  describe "missing editId" do
    it "returns applied: false with error" do
      result = handler.call({ "accepted" => true })
      expect(result["applied"]).to eq(false)
      expect(result["error"]).to include("Missing editId")
    end
  end

  describe "#wait_for_acceptance" do
    it "emits edit/proposed notification with file path and diff" do
      notifications = []
      allow(server).to receive(:notify) do |method, params|
        notifications << { "method" => method, "params" => params }
      end

      waiter = Thread.new do
        handler.wait_for_acceptance("edit-3", "/src/app.rb", "- line1\n+ line2")
      end
      sleep 0.1

      handler.call({ "editId" => "edit-3", "accepted" => true })
      waiter.join(2)

      edit_notif = notifications.find { |n| n["method"] == "edit/proposed" }
      expect(edit_notif).not_to be_nil
      expect(edit_notif["params"]["editId"]).to eq("edit-3")
      expect(edit_notif["params"]["filePath"]).to eq("/src/app.rb")
      expect(edit_notif["params"]["diff"]).to eq("- line1\n+ line2")
    end
  end

  describe "#pending?" do
    it "returns false when no edits are pending" do
      expect(handler.pending?).to be false
    end

    it "returns true when an edit is pending" do
      allow(server).to receive(:notify)

      Thread.new do
        handler.wait_for_acceptance("edit-4", "/file.rb", "diff")
      end
      sleep 0.1

      expect(handler.pending?).to be true

      # Clean up
      handler.call({ "editId" => "edit-4", "accepted" => true })
      sleep 0.1
    end
  end

  describe "concurrent edits" do
    it "handles multiple pending edits independently" do
      allow(server).to receive(:notify)

      results = {}

      t1 = Thread.new do
        results["edit-a"] = handler.wait_for_acceptance("edit-a", "/a.rb", "diff-a")
      end
      t2 = Thread.new do
        results["edit-b"] = handler.wait_for_acceptance("edit-b", "/b.rb", "diff-b")
      end
      sleep 0.2

      handler.call({ "editId" => "edit-a", "accepted" => true })
      handler.call({ "editId" => "edit-b", "accepted" => false })

      t1.join(2)
      t2.join(2)

      expect(results["edit-a"]).to eq(true)
      expect(results["edit-b"]).to eq(false)
    end
  end
end
