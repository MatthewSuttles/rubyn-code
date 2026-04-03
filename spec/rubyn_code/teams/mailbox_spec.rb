# frozen_string_literal: true

require "spec_helper"

RSpec.describe RubynCode::Teams::Mailbox do
  let(:db) { setup_test_db }
  subject(:mailbox) { described_class.new(db) }

  describe "#send and #read_inbox" do
    it "delivers a message and marks it as read" do
      mailbox.send(from: "alice", to: "bob", content: "hello")
      messages = mailbox.read_inbox("bob")

      expect(messages.size).to eq(1)
      expect(messages.first[:content]).to eq("hello")
      expect(messages.first[:from]).to eq("alice")

      # Second read returns empty (already marked read)
      expect(mailbox.read_inbox("bob")).to be_empty
    end
  end

  describe "#broadcast" do
    it "sends to all names except the sender" do
      ids = mailbox.broadcast(from: "lead", content: "update", all_names: %w[lead dev1 dev2])
      expect(ids.size).to eq(2)
      expect(mailbox.read_inbox("dev1").size).to eq(1)
      expect(mailbox.read_inbox("dev2").size).to eq(1)
      expect(mailbox.read_inbox("lead")).to be_empty
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

  describe "#unread_count" do
    it "returns the number of unread messages" do
      mailbox.send(from: "a", to: "b", content: "1")
      mailbox.send(from: "a", to: "b", content: "2")
      expect(mailbox.unread_count("b")).to eq(2)
    end

    it "decreases after reading" do
      mailbox.send(from: "a", to: "b", content: "msg")
      mailbox.read_inbox("b")
      expect(mailbox.unread_count("b")).to eq(0)
    end
  end
end
