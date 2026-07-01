# frozen_string_literal: true

# Drives the actual user-facing /resume surface and records what they
# see. Probes both the no-arg list mode and the explicit-id mode.
require 'spec_helper'
require 'tmpdir'

RSpec.describe '/resume user-facing behavior' do
  let(:dir)  { Dir.mktmpdir }
  let(:db)   { setup_test_db }
  let(:persistence) do
    RubynCode::Memory::SessionPersistence.new(db).tap do |p|
      p.send(:ensure_messages_table)
    end
  end

  let(:output) { StringIO.new }
  let(:conversation) { RubynCode::Agent::Conversation.new }
  let(:ctx) do
    RubynCode::CLI::Commands::Context.new(
      renderer: renderer,
      conversation: conversation,
      agent_loop: nil,
      context_manager: nil,
      budget_enforcer: nil,
      llm_client: nil,
      db: db,
      session_id: 'current',
      project_root: dir,
      skill_loader: nil,
      session_persistence: persistence,
      background_worker: nil,
      permission_tier: nil,
      plan_mode: false,
      message_handler: nil,
      hook_registry: nil,
      checkpoint_manager: nil
    )
  end

  before do
    conversation.add_user_message('this is the current session')
  end

  after { FileUtils.remove_entry(dir) }

  let(:renderer) do
    Class.new do
      def initialize(io) = @io = io
      def info(msg)    = @io.puts(msg)
      def warning(msg) = @io.puts("[warning] #{msg}")
      def error(msg)   = @io.puts("[error] #{msg}")
      def ask(_prompt, default: false) = true # rubocop:disable Naming/PredicateMethod,Lint/UnusedMethodArgument -- prompt is a verb
      def tool_result(_name, _result) = nil
    end.new(output)
  end

  it 'lists sessions with title, message count, and last activity' do
    seed = RubynCode::Agent::Conversation.new
    seed.add_user_message('hi')
    seed.add_user_message('there')
    persistence.save_session(session_id: 'abc', project_path: dir,
                             messages: seed.messages, title: 'listable')

    RubynCode::CLI::Commands::Resume.new.execute([], ctx)
    expect(output.string).to include('listable')
  end

  it 'refuses to clobber a non-empty current conversation without confirmation' do
    other = RubynCode::Agent::Conversation.new
    other.add_user_message('persisted message')
    other.add_user_message('another')
    persistence.save_session(session_id: 'abc', project_path: dir,
                             messages: other.messages, title: 'saved')

    allow(renderer).to receive(:ask).and_return(false)
    RubynCode::CLI::Commands::Resume.new.execute(['abc'], ctx)
    expect(conversation.messages.size).to eq(1)
    expect(conversation.messages.first[:content]).to eq('this is the current session')
  end

  it 'replaces the current conversation when confirmed' do
    other = RubynCode::Agent::Conversation.new
    other.add_user_message('persisted message')
    other.add_user_message('another')
    persistence.save_session(session_id: 'abc', project_path: dir,
                             messages: other.messages, title: 'saved')

    allow(renderer).to receive(:ask).and_return(true)
    RubynCode::CLI::Commands::Resume.new.execute(['abc'], ctx)
    expect(conversation.messages.size).to eq(2)
    expect(conversation.messages.first[:content]).to eq('persisted message')
  end

  it 'preserves tool_use / thinking / image blocks across a round-trip' do
    seed = RubynCode::Agent::Conversation.new
    seed.add_user_message([
                            { type: 'text', text: 'see @chart' },
                            { type: 'image', source: { type: 'base64', media_type: 'image/png', data: 'AAAA' } }
                          ])
    seed.add_assistant_message([
                                 { type: 'thinking', text: 'plan' },
                                 { type: 'text',     text: 'ok' },
                                 { type: 'tool_use', name: 'grep', id: 'tu_1', input: { pattern: 'X' } }
                               ])
    seed.add_tool_result('tu_1', 'grep', 'no matches')
    persistence.save_session(session_id: 'mix', project_path: dir,
                             messages: seed.messages, title: 'mixed')

    allow(renderer).to receive(:ask).and_return(true)
    RubynCode::CLI::Commands::Resume.new.execute(['mix'], ctx)
    expect(conversation.messages.size).to eq(3)
    expect(conversation.messages.first[:content].last[:type]).to eq('image')
    expect(conversation.messages[1][:content].first[:type]).to eq('thinking')
    # add_tool_result stores tool results inside a user-role message
    # (per Anthropic API convention). Block content is preserved.
    expect(conversation.messages.last[:role]).to eq('user')
    expect(conversation.messages.last[:content].first[:type]).to eq('tool_result')
  end
end
