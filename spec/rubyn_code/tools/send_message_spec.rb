# frozen_string_literal: true

require 'spec_helper'

RSpec.describe RubynCode::Tools::SendMessage do
  let(:project_root) { '/tmp/test_project' }
  let(:sender_name) { 'coder-agent' }

  def build_tool(mailbox:)
    described_class.new(project_root: project_root, mailbox: mailbox, sender_name: sender_name)
  end

  def make_mailbox(message_id = 'msg-001')
    mailbox = Object.new
    mailbox.define_singleton_method(:send) { |**_kwargs| message_id }
    mailbox
  end

  describe '#execute' do
    context 'when sending succeeds' do
      it 'sends message and returns confirmation with ID' do
        tool = build_tool(mailbox: make_mailbox('msg-abc'))
        result = tool.execute(to: 'reviewer', content: 'Please review PR #42')

        expect(result).to include('msg-abc')
        expect(result).to include('reviewer')
        expect(result).to include('Message sent')
      end

      it 'passes sender_name as from' do
        received_from = nil
        mailbox = Object.new
        mailbox.define_singleton_method(:send) do |**kwargs|
          received_from = kwargs[:from]
          'msg-1'
        end

        tool = build_tool(mailbox: mailbox)
        tool.execute(to: 'tester', content: 'Run the suite')

        expect(received_from).to eq('coder-agent')
      end
    end

    context 'with empty recipient' do
      it 'raises an error for nil recipient' do
        tool = build_tool(mailbox: make_mailbox)

        expect { tool.execute(to: nil, content: 'hello') }
          .to raise_error(RubynCode::Error, /Recipient name is required/)
      end

      it 'raises an error for blank recipient' do
        tool = build_tool(mailbox: make_mailbox)

        expect { tool.execute(to: '   ', content: 'hello') }
          .to raise_error(RubynCode::Error, /Recipient name is required/)
      end
    end

    context 'with empty content' do
      it 'raises an error for nil content' do
        tool = build_tool(mailbox: make_mailbox)

        expect { tool.execute(to: 'reviewer', content: nil) }
          .to raise_error(RubynCode::Error, /Message content is required/)
      end

      it 'raises an error for blank content' do
        tool = build_tool(mailbox: make_mailbox)

        expect { tool.execute(to: 'reviewer', content: '  ') }
          .to raise_error(RubynCode::Error, /Message content is required/)
      end
    end

    context 'with message_type parameter' do
      it 'passes message_type through to mailbox' do
        received_type = nil
        mailbox = Object.new
        mailbox.define_singleton_method(:send) do |**kwargs|
          received_type = kwargs[:message_type]
          'msg-1'
        end

        tool = build_tool(mailbox: mailbox)
        tool.execute(to: 'reviewer', content: 'urgent', message_type: 'alert')

        expect(received_type).to eq('alert')
      end

      it 'includes message_type in output' do
        tool = build_tool(mailbox: make_mailbox)
        result = tool.execute(to: 'reviewer', content: 'check this', message_type: 'review_request')

        expect(result).to include('review_request')
      end

      it 'defaults message_type to message' do
        received_type = nil
        mailbox = Object.new
        mailbox.define_singleton_method(:send) do |**kwargs|
          received_type = kwargs[:message_type]
          'msg-1'
        end

        tool = build_tool(mailbox: mailbox)
        tool.execute(to: 'reviewer', content: 'hello')

        expect(received_type).to eq('message')
      end
    end
  end

  describe '.tool_name' do
    it 'returns send_message' do
      expect(described_class.tool_name).to eq('send_message')
    end
  end
end
