# frozen_string_literal: true

require 'spec_helper'
require 'tmpdir'

RSpec.describe RubynCode::CLI::Commands::Mcp do
  subject(:command) { described_class.new }

  around do |ex|
    Dir.mktmpdir do |dir|
      @dir = dir
      ex.run
    end
  end

  # Stub the heavy MCP client lifecycle so we don't actually start subprocesses.
  let(:fake_client_class) do
    Class.new do
      class << self
        attr_accessor :instance
      end

      def self.from_config(_cfg)
        self.instance ||= new
      end
    end
  end

  before do
    stub_const('RubynCode::MCP::Client', fake_client_class)
    client = Object.new
    client.define_singleton_method(:connect!) {}
    client.define_singleton_method(:disconnect!) {}
    client.define_singleton_method(:connected?) { true }
    client.define_singleton_method(:tools) { %i[t1 t2] }
    client.define_singleton_method(:resources) { [] }
    client.define_singleton_method(:prompts) { [] }
    fake_client_class.instance = client
  end

  let(:renderer) { double(info: nil) }
  let(:ctx) do
    instance_double(
      RubynCode::CLI::Commands::Context,
      project_root: @dir, renderer: renderer
    )
  end

  it 'lists servers with [user] source tag from project .rubyn-code/mcp.json' do
    user_path = File.join(@dir, '.rubyn-code', 'mcp.json')
    FileUtils.mkdir_p(File.dirname(user_path))
    File.write(user_path, <<~JSON)
      { "mcpServers": { "user-server": { "command": "u" } } }
    JSON

    output = capture_stdout { command.execute([], ctx) }
    expect(output).to include('user-server')
    expect(output).to include('[user]')
    expect(output).not_to include('[project]')
  end

  it 'lists servers with [project] source tag from .mcp.json' do
    File.write(File.join(@dir, '.mcp.json'), <<~JSON)
      { "mcpServers": { "proj-server": { "command": "p" } } }
    JSON

    output = capture_stdout { command.execute([], ctx) }
    expect(output).to include('proj-server')
    expect(output).to include('[project]')
  end

  it 'lists both sources together, prefixed accordingly' do
    user_path = File.join(@dir, '.rubyn-code', 'mcp.json')
    FileUtils.mkdir_p(File.dirname(user_path))
    File.write(user_path, <<~JSON)
      { "mcpServers": { "user-server": { "command": "u" } } }
    JSON
    File.write(File.join(@dir, '.mcp.json'), <<~JSON)
      { "mcpServers": { "project-server": { "command": "p" } } }
    JSON

    output = capture_stdout { command.execute([], ctx) }
    expect(output).to include('user-server')
    expect(output).to include('project-server')
    expect(output).to include('[user]')
    expect(output).to include('[project]')
  end

  def capture_stdout
    original = $stdout
    captured = StringIO.new
    $stdout = captured
    yield
    captured.string
  ensure
    $stdout = original
  end
end
