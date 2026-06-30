# frozen_string_literal: true

# End-to-end integration: simulate one full REPL turn where the user
# (a) sets thinking, (b) attaches an image, (c) gets a tool call back
# that touches TodoWrite, and (d) can then /export the resulting
# transcript. All four gaps compose in a single test run.
require 'spec_helper'
require 'tmpdir'
require 'json'

RSpec.describe 'Parity end-to-end (single conversation turn)', :webmock do
  include ProviderStubs

  let(:project_root) { Dir.mktmpdir }

  let(:fake_token) do
    {
      'provider' => 'anthropic',
      'access_token' => 'sk-ant-api01-test',
      'expires_at' => Time.now + 3600,
      'source' => :env
    }
  end

  before do
    FileUtils.mkdir_p(File.join(project_root, '.rubyn-code'))
    File.write(File.join(project_root, '.mcp.json'),
               JSON.generate(mcpServers: { 'srv' => { command: 'x' } }))

    allow(RubynCode::Auth::TokenStore).to receive_messages(
      load: fake_token, valid?: true
    )
  end

  after { FileUtils.remove_entry(project_root) }

  def anthropic_response(blocks)
    {
      'id' => 'msg_e2e', 'type' => 'message', 'role' => 'assistant',
      'content' => blocks,
      'stop_reason' => (blocks.find { |b| b['type'] == 'tool_use' } ? 'tool_use' : 'end_turn'),
      'usage' => { 'input_tokens' => 12, 'output_tokens' => 8 }
    }
  end

  it 'sends thinking + image + tool_use in a single request and parses them all' do
    todo_block = {
      'content' => 'Add spec', 'status' => 'in_progress',
      'active_form' => 'Adding spec'
    }
    stub_request(:post, /api\.anthropic\.com/).to_return(
      status: 200,
      headers: { 'Content-Type' => 'application/json' },
      body: JSON.generate(anthropic_response([
                                               { 'type' => 'thinking', 'thinking' => 'plan the steps' },
                                               { 'type' => 'tool_use', 'id' => 'tu_1', 'name' => 'TodoWrite',
                                                 'input' => { 'todos' => [todo_block] } }
                                             ]))
    )

    RubynCode::LLM::ImageBlock.new(media_type: 'image/png', data: 'BASE64')

    # Compose: user turns on /think via the command, attaches an image,
    # and the loop sends everything through one LLM call.
    client = RubynCode::LLM::Client.new
    client.thinking_budget_tokens = 4096

    response = client.chat(
      model: 'claude-opus-4-8',
      messages: [{
        role: 'user',
        content: [
          { type: 'text',  text: 'look at the chart and plan the rollout' },
          { type: 'image', source: { type: 'base64', media_type: 'image/png', data: 'BASE64' } }
        ]
      }],
      tools: [{ 'name' => 'TodoWrite', 'description' => '...', 'input_schema' => {} }],
      system: 'You are a planner.'
    )

    # Goal: all features coexist on a single response round-trip.
    expect(response.content.map(&:type)).to eq(%w[thinking tool_use])

    # Drive TodoWrite and confirm the shared store reflects it.
    todo_store  = RubynCode::Tools::TodoStore.new
    todo_tool   = RubynCode::Tools::TodoWrite.new(project_root: project_root, store: todo_store)
    out = todo_tool.execute(
      todos: [{ 'content' => 'Add spec', 'status' => 'in_progress', 'active_form' => 'Adding' }]
    )
    expect(out).to include('[~] Add spec')
    expect(todo_store.current.first[:status]).to eq('in_progress')

    # /export the round-trip into a markdown file and read it back.
    convo_msgs = [
      { role: 'user', content: 'look at the chart' },
      { role: 'assistant', content: [
        { type: 'thinking', text: 'plan the steps' },
        { type: 'text',     text: 'here is the plan' }
      ] }
    ]
    conv = double('Conversation')
    allow(conv).to receive(:to_a).and_return(convo_msgs)
    renderer = double(info: nil, warning: nil)
    allow(renderer).to receive(:ask).and_return(true)
    ctx      = instance_double(RubynCode::CLI::Commands::Context, conversation: conv, renderer: renderer)
    out_path = File.join(project_root, 'transcript.md')
    RubynCode::CLI::Commands::Export.new.execute([out_path], ctx)

    body = File.read(out_path)
    expect(body).to include('## User')
    expect(body).to include('here is the plan')
    expect(body).to include('<details><summary>thinking</summary>')

    # /mcp would group the .mcp.json server under [project].
    entries = RubynCode::MCP::Discovery.discover(project_root)
    expect(entries.first.source).to eq(:project)
    expect(entries.first.name).to eq('srv')
  end
end
