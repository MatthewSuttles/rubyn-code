# frozen_string_literal: true

require 'spec_helper'

RSpec.describe RubynCode::Tools::ReadInbox do
  let(:project_root) { '/tmp/test_project' }

  def build_tool(mailbox:)
    described_class.new(project_root: project_root, mailbox: mailbox)
  end

  def make_mailbox(messages = [])
    mailbox = Object.new
    mailbox.define_singleton_method(:read_inbox) { |_name| messages }
    mailbox
  end

  def make_message(attrs = {})
    {
      from: 'coder',
      message_type: 'message',
      timestamp: '2024-01-15 10:30:00',
      content: 'Hello teammate'
    }.merge(attrs)
  end

  describe '#execute' do
    context 'when inbox has messages' do
      it 'returns formatted messages' do
        messages = [make_message(from: 'reviewer', content: 'LGTM')]
        tool = build_tool(mailbox: make_mailbox(messages))

        result = tool.execute(name: 'coder')

        expect(result).to include('reviewer')
        expect(result).to include('LGTM')
        expect(result).to include("1 message for 'coder'")
      end

      it 'formats multiple messages with indices' do
        messages = [
          make_message(from: 'alice', content: 'First message'),
          make_message(from: 'bob', content: 'Second message')
        ]
        tool = build_tool(mailbox: make_mailbox(messages))

        result = tool.execute(name: 'coder')

        expect(result).to include('Message 1')
        expect(result).to include('Message 2')
        expect(result).to include('alice')
        expect(result).to include('bob')
        expect(result).to include('First message')
        expect(result).to include('Second message')
        expect(result).to include("2 messages for 'coder'")
      end

      it 'includes message metadata' do
        messages = [make_message(
          from: 'tester',
          message_type: 'alert',
          timestamp: '2024-06-01 14:00:00',
          content: 'Tests failing'
        )]
        tool = build_tool(mailbox: make_mailbox(messages))

        result = tool.execute(name: 'coder')

        expect(result).to include('From: tester')
        expect(result).to include('Type: alert')
        expect(result).to include('Time: 2024-06-01 14:00:00')
        expect(result).to include('Content: Tests failing')
      end
    end

    context 'when inbox is empty' do
      it 'returns no unread messages' do
        tool = build_tool(mailbox: make_mailbox([]))

        result = tool.execute(name: 'coder')

        expect(result).to include('No unread messages')
        expect(result).to include('coder')
      end
    end

    context 'with empty name' do
      it 'raises an error for nil name' do
        tool = build_tool(mailbox: make_mailbox)

        expect { tool.execute(name: nil) }
          .to raise_error(RubynCode::Error, /Agent name is required/)
      end

      it 'raises an error for blank name' do
        tool = build_tool(mailbox: make_mailbox)

        expect { tool.execute(name: '  ') }
          .to raise_error(RubynCode::Error, /Agent name is required/)
      end
    end

    context 'with correct mailbox delegation' do
      it 'passes name to mailbox.read_inbox' do
        received_name = nil
        mailbox = Object.new
        mailbox.define_singleton_method(:read_inbox) do |name|
          received_name = name
          []
        end

        tool = build_tool(mailbox: mailbox)
        tool.execute(name: 'reviewer-bot')

        expect(received_name).to eq('reviewer-bot')
      end
    end
  end

  describe '.tool_name' do
    it 'returns read_inbox' do
      expect(described_class.tool_name).to eq('read_inbox')
    end
  end
end
