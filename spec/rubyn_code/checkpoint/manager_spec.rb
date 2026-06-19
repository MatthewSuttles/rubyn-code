# frozen_string_literal: true

require 'spec_helper'
require 'tmpdir'

RSpec.describe RubynCode::Checkpoint::Manager do
  around do |example|
    Dir.mktmpdir do |dir|
      @root = dir
      example.run
    end
  end

  subject(:manager) { described_class.new(project_root: @root) }

  let(:conversation) { RubynCode::Agent::Conversation.new }

  def path(rel) = File.join(@root, rel)

  describe '#checkpoint! and #list' do
    it 'records a checkpoint capturing the conversation' do
      conversation.add_user_message('hello')
      id = manager.checkpoint!(label: 'do a thing', conversation: conversation)

      expect(id).to eq(1)
      expect(manager.list.first).to include(id: 1, label: 'do a thing', files: 0)
    end

    it 'caps the number of stored checkpoints' do
      (described_class::MAX_CHECKPOINTS + 5).times do |i|
        manager.checkpoint!(label: "t#{i}", conversation: conversation)
      end
      expect(manager.list.size).to eq(described_class::MAX_CHECKPOINTS)
    end
  end

  describe '#record_file' do
    it 'snapshots a file\'s original content once per checkpoint' do
      File.write(path('a.rb'), 'original')
      manager.checkpoint!(label: 'edit', conversation: conversation)

      manager.record_file(path('a.rb'))
      File.write(path('a.rb'), 'changed-again')
      manager.record_file(path('a.rb')) # second call must not overwrite the snapshot

      expect(manager.list.first[:files]).to eq(1)
    end

    it 'is a no-op when no checkpoint is open' do
      expect { manager.record_file(path('a.rb')) }.not_to raise_error
    end
  end

  describe '#restore' do
    it 'restores file contents and conversation' do
      File.write(path('a.rb'), 'v1')
      conversation.add_user_message('first')
      manager.checkpoint!(label: 'turn 1', conversation: conversation)
      manager.record_file(path('a.rb'))

      # Simulate the turn's effects.
      File.write(path('a.rb'), 'v2')
      conversation.add_assistant_message([{ type: 'text', text: 'done' }])

      result = manager.restore(1, conversation)

      expect(File.read(path('a.rb'))).to eq('v1')
      expect(result[:files_restored]).to eq(1)
      expect(conversation.messages.map { |m| m[:role] }).to eq(['user'])
    end

    it 'deletes files that did not exist at checkpoint time' do
      manager.checkpoint!(label: 'create', conversation: conversation)
      manager.record_file(path('new.rb')) # captured as absent
      File.write(path('new.rb'), 'created')

      manager.restore(1, conversation)
      expect(File.exist?(path('new.rb'))).to be(false)
    end

    it 'restores only code when scope: :code' do
      File.write(path('a.rb'), 'v1')
      conversation.add_user_message('first')
      manager.checkpoint!(label: 't', conversation: conversation)
      manager.record_file(path('a.rb'))
      File.write(path('a.rb'), 'v2')
      conversation.add_assistant_message([{ type: 'text', text: 'hi' }])

      manager.restore(1, conversation, scope: :code)

      expect(File.read(path('a.rb'))).to eq('v1')
      expect(conversation.messages.size).to eq(2) # conversation untouched
    end

    it 'drops checkpoints newer than the restored one' do
      manager.checkpoint!(label: 'one', conversation: conversation)
      manager.checkpoint!(label: 'two', conversation: conversation)
      manager.restore(1, conversation)
      expect(manager.list.map { |c| c[:id] }).to eq([1])
    end

    it 'returns nil for an unknown checkpoint' do
      expect(manager.restore(99, conversation)).to be_nil
    end
  end
end
