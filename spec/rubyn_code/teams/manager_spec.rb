# frozen_string_literal: true

require "spec_helper"

RSpec.describe RubynCode::Teams::Manager do
  let(:db) { setup_test_db }
  let(:mailbox) { RubynCode::Teams::Mailbox.new(db) }
  let(:manager) { described_class.new(db, mailbox: mailbox) }

  describe "#spawn" do
    it "creates a teammate with idle status" do
      mate = manager.spawn(name: "coder", role: "writes code")
      expect(mate.name).to eq("coder")
      expect(mate.status).to eq("idle")
    end

    it "raises on duplicate name" do
      manager.spawn(name: "dup", role: "role")
      expect { manager.spawn(name: "dup", role: "role") }.to raise_error(RubynCode::Error)
    end
  end

  describe "#list" do
    it "returns all teammates" do
      manager.spawn(name: "a", role: "r1")
      manager.spawn(name: "b", role: "r2")
      expect(manager.list.size).to eq(2)
    end
  end

  describe "#get" do
    it "finds by name" do
      manager.spawn(name: "finder", role: "test")
      expect(manager.get("finder").role).to eq("test")
    end

    it "returns nil for unknown name" do
      expect(manager.get("ghost")).to be_nil
    end
  end

  describe "#update_status" do
    it "changes the status" do
      manager.spawn(name: "agent", role: "test")
      manager.update_status("agent", "active")
      expect(manager.get("agent").status).to eq("active")
    end

    it "raises on invalid status" do
      manager.spawn(name: "bad", role: "test")
      expect { manager.update_status("bad", "invalid") }.to raise_error(ArgumentError)
    end
  end

  describe "#remove" do
    it "deletes the teammate" do
      manager.spawn(name: "doomed", role: "test")
      manager.remove("doomed")
      expect(manager.get("doomed")).to be_nil
    end

    it "raises when teammate not found" do
      expect { manager.remove("ghost") }.to raise_error(RubynCode::Error)
    end
  end
end
