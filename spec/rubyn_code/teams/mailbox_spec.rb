# frozen_string_literal: true

require 'spec_helper'

RSpec.describe RubynCode::Teams::Mailbox do
  let(:db) { setup_test_db }
  subject(:mailbox) { described_class.new(db) }

  describe '#send and #read_inbox' do
    it 'delivers a message and marks it as read' do
      mailbox.send(from: 'alice', to: 'bob', content: 'hello')
      messages = mailbox.read_inbox('bob')

      expect(messages.size).to eq(1)
      expect(messages.first[:content]).to eq('hello')
      expect(messages.first[:from]).to eq('alice')

      # Second read returns empty (already marked read)
      expect(mailbox.read_inbox('bob')).to be_empty
    end
  end

  describe '#send with structured data' do
    it 'stores and retrieves correlation_id' do
      mailbox.send(from: 'a', to: 'b', content: 'task', correlation_id: 'corr-123')
      messages = mailbox.read_inbox('b')

      expect(messages.first[:correlation_id]).to eq('corr-123')
    end

    it 'stores and retrieves structured data' do
      mailbox.send(from: 'a', to: 'b', content: 'result', data: { status: 'ok', count: 42 })
      messages = mailbox.read_inbox('b')

      expect(messages.first[:data]).to eq({ status: 'ok', count: 42 })
    end

    it 'omits correlation_id and data keys when not provided' do
      mailbox.send(from: 'a', to: 'b', content: 'plain')
      messages = mailbox.read_inbox('b')

      expect(messages.first).not_to have_key(:correlation_id)
      expect(messages.first).not_to have_key(:data)
    end
  end

  describe '#send_structured' do
    it 'sends a typed message with structured data and auto-generated correlation_id' do
      mailbox.send_structured(from: 'worker', to: 'lead', type: 'result', data: { files: %w[a.rb b.rb] })
      messages = mailbox.read_inbox('lead')

      expect(messages.size).to eq(1)
      msg = messages.first
      expect(msg[:message_type]).to eq('result')
      expect(msg[:data]).to eq({ files: %w[a.rb b.rb] })
      expect(msg[:correlation_id]).to be_a(String)
      expect(msg[:correlation_id]).not_to be_empty
    end

    it 'uses provided correlation_id' do
      mailbox.send_structured(from: 'a', to: 'b', type: 'task', data: { cmd: 'test' }, correlation_id: 'my-corr')
      messages = mailbox.read_inbox('b')

      expect(messages.first[:correlation_id]).to eq('my-corr')
    end

    it 'auto-generates a content summary when content is nil' do
      mailbox.send_structured(from: 'a', to: 'b', type: 'error', data: { msg: 'boom' })
      messages = mailbox.read_inbox('b')

      expect(messages.first[:content]).to include('error')
    end

    it 'uses provided content when given' do
      mailbox.send_structured(from: 'a', to: 'b', type: 'result', data: {}, content: 'All done!')
      messages = mailbox.read_inbox('b')

      expect(messages.first[:content]).to eq('All done!')
    end
  end

  describe '#find_by_correlation_id' do
    it 'returns all messages with the same correlation_id' do
      corr = 'task-abc'
      mailbox.send(from: 'lead', to: 'worker', content: 'do this', correlation_id: corr, message_type: 'task')
      mailbox.send(from: 'worker', to: 'lead', content: 'done', correlation_id: corr, message_type: 'result')
      mailbox.send(from: 'other', to: 'someone', content: 'unrelated')

      chain = mailbox.find_by_correlation_id(corr)
      expect(chain.size).to eq(2)
      expect(chain.map { |m| m[:message_type] }).to eq(%w[task result])
    end

    it 'returns empty array when no messages match' do
      expect(mailbox.find_by_correlation_id('nonexistent')).to be_empty
    end
  end

  describe '#broadcast' do
    it 'sends to all names except the sender' do
      ids = mailbox.broadcast(from: 'lead', content: 'update', all_names: %w[lead dev1 dev2])
      expect(ids.size).to eq(2)
      expect(mailbox.read_inbox('dev1').size).to eq(1)
      expect(mailbox.read_inbox('dev2').size).to eq(1)
      expect(mailbox.read_inbox('lead')).to be_empty
    end
  end

  describe '#pending_for' do
    it 'returns unread messages without marking them as read' do
      mailbox.send(from: 'alice', to: 'bob', content: 'task update')
      mailbox.send(from: 'carol', to: 'bob', content: 'another update')

      pending = mailbox.pending_for('bob')
      expect(pending.size).to eq(2)
      expect(pending.first[:content]).to eq('task update')

      # Messages should still be unread after pending_for
      expect(mailbox.unread_count('bob')).to eq(2)
    end

    it 'returns empty array when no unread messages exist' do
      expect(mailbox.pending_for('nobody')).to be_empty
    end

    it 'does not return messages for other agents' do
      mailbox.send(from: 'alice', to: 'bob', content: 'for bob')
      expect(mailbox.pending_for('carol')).to be_empty
    end

    it 'does not return already-read messages' do
      mailbox.send(from: 'alice', to: 'bob', content: 'msg')
      mailbox.read_inbox('bob') # marks as read
      expect(mailbox.pending_for('bob')).to be_empty
    end
  end

  describe '#unread_count' do
    it 'returns the number of unread messages' do
      mailbox.send(from: 'a', to: 'b', content: '1')
      mailbox.send(from: 'a', to: 'b', content: '2')
      expect(mailbox.unread_count('b')).to eq(2)
    end

    it 'decreases after reading' do
      mailbox.send(from: 'a', to: 'b', content: 'msg')
      mailbox.read_inbox('b')
      expect(mailbox.unread_count('b')).to eq(0)
    end
  end
end
