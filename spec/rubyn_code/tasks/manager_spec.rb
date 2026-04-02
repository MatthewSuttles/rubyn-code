# frozen_string_literal: true

require "spec_helper"

RSpec.describe RubynCode::Tasks::Manager do
  let(:db) { setup_test_db }
  let(:manager) { described_class.new(db) }

  describe "#create" do
    it "creates a task with pending status" do
      task = manager.create(title: "Write tests")
      expect(task.title).to eq("Write tests")
      expect(task.status).to eq("pending")
    end

    it "creates a blocked task when blocked_by is provided" do
      dep = manager.create(title: "Dependency")
      task = manager.create(title: "Blocked", blocked_by: [dep.id])
      expect(task.status).to eq("blocked")
    end
  end

  describe "#claim" do
    it "sets owner and status to in_progress" do
      task = manager.create(title: "Claimable")
      claimed = manager.claim(task.id, owner: "agent-1")
      expect(claimed.owner).to eq("agent-1")
      expect(claimed.status).to eq("in_progress")
    end
  end

  describe "#ready_tasks" do
    it "returns pending unowned tasks" do
      manager.create(title: "Ready task")
      expect(manager.ready_tasks.size).to eq(1)
    end

    it "excludes claimed tasks" do
      task = manager.create(title: "Claimed")
      manager.claim(task.id, owner: "agent-1")
      expect(manager.ready_tasks).to be_empty
    end
  end

  describe "#complete" do
    it "marks task as completed and cascades unblocking" do
      dep = manager.create(title: "Dep")
      blocked = manager.create(title: "Blocked", blocked_by: [dep.id])
      manager.complete(dep.id, result: "done")

      expect(manager.get(dep.id).status).to eq("completed")
      expect(manager.get(blocked.id).status).to eq("pending")
    end
  end

  describe "#delete" do
    it "removes the task" do
      task = manager.create(title: "Doomed")
      manager.delete(task.id)
      expect(manager.get(task.id)).to be_nil
    end
  end
end
