# frozen_string_literal: true

require 'spec_helper'

RSpec.describe RubynCode::Teams::Manager do
  let(:db) { setup_test_db }
  let(:mailbox) { RubynCode::Teams::Mailbox.new(db) }
  let(:manager) { described_class.new(db, mailbox: mailbox) }

  describe '#spawn' do
    it 'creates a teammate with idle status' do
      mate = manager.spawn(name: 'coder', role: 'writes code')
      expect(mate.name).to eq('coder')
      expect(mate.status).to eq('idle')
    end

    it 'raises on duplicate name' do
      manager.spawn(name: 'dup', role: 'role')
      expect { manager.spawn(name: 'dup', role: 'role') }.to raise_error(RubynCode::Error)
    end

    it 'stores parent_agent_id when provided' do
      parent = manager.spawn(name: 'parent', role: 'lead')
      child = manager.spawn(name: 'child', role: 'worker', parent_agent_id: parent.id)

      expect(child.parent_agent_id).to eq(parent.id)
    end

    it 'defaults parent_agent_id to nil' do
      mate = manager.spawn(name: 'solo', role: 'lone wolf')
      expect(mate.parent_agent_id).to be_nil
    end
  end

  describe '#list' do
    it 'returns all teammates' do
      manager.spawn(name: 'a', role: 'r1')
      manager.spawn(name: 'b', role: 'r2')
      expect(manager.list.size).to eq(2)
    end
  end

  describe '#get' do
    it 'finds by name' do
      manager.spawn(name: 'finder', role: 'test')
      expect(manager.get('finder').role).to eq('test')
    end

    it 'returns nil for unknown name' do
      expect(manager.get('ghost')).to be_nil
    end
  end

  describe '#find_by_id' do
    it 'finds a teammate by ID' do
      mate = manager.spawn(name: 'byid', role: 'test')
      found = manager.find_by_id(mate.id)
      expect(found.name).to eq('byid')
    end

    it 'returns nil for unknown ID' do
      expect(manager.find_by_id('nonexistent')).to be_nil
    end
  end

  describe '#children_of' do
    it 'returns direct children of a parent' do
      parent = manager.spawn(name: 'parent', role: 'lead')
      manager.spawn(name: 'child1', role: 'worker', parent_agent_id: parent.id)
      manager.spawn(name: 'child2', role: 'worker', parent_agent_id: parent.id)
      manager.spawn(name: 'orphan', role: 'solo')

      children = manager.children_of(parent.id)
      expect(children.map(&:name)).to contain_exactly('child1', 'child2')
    end

    it 'returns empty array when no children exist' do
      parent = manager.spawn(name: 'lonely', role: 'lead')
      expect(manager.children_of(parent.id)).to be_empty
    end
  end

  describe '#roots' do
    it 'returns only agents with no parent' do
      parent = manager.spawn(name: 'root1', role: 'lead')
      manager.spawn(name: 'root2', role: 'lead')
      manager.spawn(name: 'child', role: 'worker', parent_agent_id: parent.id)

      roots = manager.roots
      expect(roots.map(&:name)).to contain_exactly('root1', 'root2')
    end
  end

  describe '#agent_tree' do
    it 'builds a nested tree from a root agent' do
      root = manager.spawn(name: 'root', role: 'lead')
      child = manager.spawn(name: 'child', role: 'coder', parent_agent_id: root.id)
      manager.spawn(name: 'grandchild', role: 'tester', parent_agent_id: child.id)

      tree = manager.agent_tree(root.id)

      expect(tree[:agent].name).to eq('root')
      expect(tree[:children].size).to eq(1)
      expect(tree[:children].first[:agent].name).to eq('child')
      expect(tree[:children].first[:children].first[:agent].name).to eq('grandchild')
    end

    it 'returns nil for unknown root ID' do
      expect(manager.agent_tree('nope')).to be_nil
    end

    it 'returns a leaf node with empty children' do
      leaf = manager.spawn(name: 'leaf', role: 'solo')
      tree = manager.agent_tree(leaf.id)

      expect(tree[:agent].name).to eq('leaf')
      expect(tree[:children]).to be_empty
    end
  end

  describe '#update_status' do
    it 'changes the status' do
      manager.spawn(name: 'agent', role: 'test')
      manager.update_status('agent', 'active')
      expect(manager.get('agent').status).to eq('active')
    end

    it 'raises on invalid status' do
      manager.spawn(name: 'bad', role: 'test')
      expect { manager.update_status('bad', 'invalid') }.to raise_error(ArgumentError)
    end
  end

  describe '#remove' do
    it 'deletes the teammate' do
      manager.spawn(name: 'doomed', role: 'test')
      manager.remove('doomed')
      expect(manager.get('doomed')).to be_nil
    end

    it 'raises when teammate not found' do
      expect { manager.remove('ghost') }.to raise_error(RubynCode::Error)
    end
  end

  describe '#active_teammates' do
    it 'returns only active teammates' do
      manager.spawn(name: 'idle_one', role: 'test')
      manager.spawn(name: 'active_one', role: 'test')
      manager.update_status('active_one', 'active')

      actives = manager.active_teammates
      expect(actives.map(&:name)).to eq(['active_one'])
    end
  end
end
