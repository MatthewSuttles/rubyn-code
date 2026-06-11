# frozen_string_literal: true

require 'spec_helper'

RSpec.describe RubynCode::Teams::AgentRegistry do
  let(:db) { setup_test_db }
  let(:mailbox) { RubynCode::Teams::Mailbox.new(db) }
  let(:manager) { RubynCode::Teams::Manager.new(db, mailbox: mailbox) }
  let(:registry) { described_class.new(manager: manager, mailbox: mailbox) }

  before do
    @root = manager.spawn(name: 'lead', role: 'coordinator')
    @child = manager.spawn(name: 'coder', role: 'developer', parent_agent_id: @root.id)
    @grandchild = manager.spawn(name: 'tester', role: 'qa', parent_agent_id: @child.id)
  end

  describe '#snapshot' do
    it 'returns all agents with status and unread counts' do
      snap = registry.snapshot
      expect(snap.size).to eq(3)
      expect(snap.first[:name]).to eq('lead')
      expect(snap.first[:unread_count]).to eq(0)
    end

    it 'reflects unread message counts' do
      mailbox.send(from: 'coder', to: 'lead', content: 'done')
      snap = registry.snapshot
      lead = snap.find { |a| a[:name] == 'lead' }
      expect(lead[:unread_count]).to eq(1)
    end
  end

  describe '#active' do
    it 'returns only active agents' do
      manager.update_status('coder', 'active')
      actives = registry.active
      expect(actives.map { |a| a[:name] }).to eq(['coder'])
    end

    it 'returns empty when no agents are active' do
      expect(registry.active).to be_empty
    end
  end

  describe '#forest' do
    it 'returns nested trees from all root agents' do
      trees = registry.forest
      expect(trees.size).to eq(1) # only 'lead' is a root

      root_tree = trees.first
      expect(root_tree[:name]).to eq('lead')
      expect(root_tree[:children].size).to eq(1)
      expect(root_tree[:children].first[:name]).to eq('coder')
      expect(root_tree[:children].first[:children].first[:name]).to eq('tester')
    end

    it 'handles multiple root agents' do
      manager.spawn(name: 'another_root', role: 'lead2')
      trees = registry.forest
      expect(trees.size).to eq(2)
    end
  end

  describe '#lineage' do
    it 'returns ancestors from root to immediate parent' do
      ancestors = registry.lineage(@grandchild.id)
      expect(ancestors.map(&:name)).to eq(%w[lead coder])
    end

    it 'returns empty for a root agent' do
      expect(registry.lineage(@root.id)).to be_empty
    end

    it 'returns empty for unknown agent' do
      expect(registry.lineage('nonexistent')).to be_empty
    end

    it 'returns single parent for direct child' do
      ancestors = registry.lineage(@child.id)
      expect(ancestors.map(&:name)).to eq(['lead'])
    end
  end

  describe '#status_report' do
    it 'produces a formatted multi-line report' do
      report = registry.status_report
      expect(report).to include('Agent Registry Status:')
      expect(report).to include('lead')
      expect(report).to include('coder')
      expect(report).to include('tester')
      expect(report).to include('(root)')
    end

    it 'shows unread counts when messages are pending' do
      mailbox.send(from: 'tester', to: 'coder', content: 'bugs found')
      report = registry.status_report
      expect(report).to include('Unread: 1')
    end

    it 'returns a fallback message when no agents exist' do
      empty_manager = RubynCode::Teams::Manager.new(setup_test_db, mailbox: mailbox)
      empty_registry = described_class.new(manager: empty_manager, mailbox: mailbox)
      expect(empty_registry.status_report).to eq('No agents registered.')
    end
  end
end
