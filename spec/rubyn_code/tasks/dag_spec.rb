# frozen_string_literal: true

require "spec_helper"

RSpec.describe RubynCode::Tasks::DAG do
  let(:db) { setup_test_db }
  let(:manager) { RubynCode::Tasks::Manager.new(db) }
  let(:dag) { RubynCode::Tasks::DAG.new(db) }

  describe "#add_dependency / #remove_dependency" do
    it "records and removes a dependency edge" do
      a = manager.create(title: "A")
      b = manager.create(title: "B")
      dag.add_dependency(b.id, a.id)
      expect(dag.dependencies_for(b.id)).to include(a.id)
      dag.remove_dependency(b.id, a.id)
      expect(dag.dependencies_for(b.id)).to be_empty
    end

    it "raises on self-dependency" do
      a = manager.create(title: "A")
      expect { dag.add_dependency(a.id, a.id) }.to raise_error(ArgumentError, /itself/)
    end

    it "raises on cycle detection" do
      a, b = manager.create(title: "A"), manager.create(title: "B")
      dag.add_dependency(b.id, a.id)
      expect { dag.add_dependency(a.id, b.id) }.to raise_error(ArgumentError, /Cycle/)
    end
  end

  describe "#blocked?" do
    it "returns true when dependency is incomplete, false otherwise" do
      a, b = manager.create(title: "A"), manager.create(title: "B")
      expect(dag.blocked?(a.id)).to be false
      dag.add_dependency(b.id, a.id)
      expect(dag.blocked?(b.id)).to be true
    end
  end

  describe "#topological_sort" do
    it "returns nodes in valid execution order" do
      a, b, c = manager.create(title: "A"), manager.create(title: "B"), manager.create(title: "C")
      dag.add_dependency(b.id, a.id)
      dag.add_dependency(c.id, b.id)
      sorted = dag.topological_sort
      expect(sorted.index(a.id)).to be < sorted.index(b.id)
      expect(sorted.index(b.id)).to be < sorted.index(c.id)
    end
  end

  describe "#unblock_cascade" do
    it "transitions blocked dependents to pending" do
      dep = manager.create(title: "Dep")
      blocked = manager.create(title: "Blocked", blocked_by: [dep.id])
      manager.complete(dep.id)
      expect(manager.get(blocked.id).status).to eq("pending")
    end
  end
end
