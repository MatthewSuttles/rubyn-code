# frozen_string_literal: true

require 'spec_helper'
require 'tmpdir'

RSpec.describe RubynCode::MCP::Discovery do
  around do |ex|
    Dir.mktmpdir do |dir|
      @dir = dir
      ex.run
    end
  end

  def write_mcp_json(content)
    path = File.join(@dir, '.mcp.json')
    File.write(path, content)
    path
  end

  it 'returns an empty array when the project root has no .mcp.json' do
    expect(described_class.load_project(@dir)).to eq([])
  end

  it 'returns an empty array when project_root is nil' do
    expect(described_class.load_project(nil)).to eq([])
  end

  it 'parses a stdio server entry' do
    write_mcp_json(<<~JSON)
      {
        "mcpServers": {
          "github": {
            "command": "npx",
            "args": ["-y", "@modelcontextprotocol/server-github"],
            "env": { "GITHUB_TOKEN": "secret" }
          }
        }
      }
    JSON

    entries = described_class.load_project(@dir)
    expect(entries.size).to eq(1)
    e = entries.first
    expect(e.name).to eq('github')
    expect(e.command).to eq('npx')
    expect(e.args).to eq(['-y', '@modelcontextprotocol/server-github'])
    expect(e.env).to eq('GITHUB_TOKEN' => 'secret')
    expect(e.source).to eq(:project)
    expect(e.url).to eq('')
  end

  it 'parses a URL-based server entry' do
    write_mcp_json(<<~JSON)
      {
        "mcpServers": {
          "remote": {
            "url": "https://example.com/mcp"
          }
        }
      }
    JSON

    entries = described_class.load_project(@dir)
    expect(entries.first.url).to eq('https://example.com/mcp')
    expect(entries.first.command).to eq('')
  end

  it 'skips entries with neither command nor url' do
    write_mcp_json(<<~JSON)
      {
        "mcpServers": {
          "broken": { "type": "stdio" }
        }
      }
    JSON

    expect(described_class.load_project(@dir)).to be_empty
  end

  it 'returns [] on malformed JSON without raising' do
    write_mcp_json('this is not JSON')
    expect { described_class.load_project(@dir) }.not_to raise_error
    expect(described_class.load_project(@dir)).to eq([])
  end

  it 'classifies stdio vs remote servers' do
    write_mcp_json(<<~JSON)
      {
        "mcpServers": {
          "a": { "command": "x" },
          "b": { "url": "https://x" }
        }
      }
    JSON

    entries = described_class.load_project(@dir)
    expect(described_class.stdio_servers(entries).map(&:name)).to eq(['a'])
    expect(described_class.remote_servers(entries).map(&:name)).to eq(['b'])
  end

  it 'merges user + project entries via #discover, marking sources' do
    user_path = File.join(@dir, '.rubyn-code', 'mcp.json')
    FileUtils.mkdir_p(File.dirname(user_path))
    File.write(user_path, <<~JSON)
      {
        "mcpServers": {
          "user-server": { "command": "u" }
        }
      }
    JSON
    write_mcp_json(<<~JSON)
      {
        "mcpServers": {
          "project-server": { "command": "p" }
        }
      }
    JSON

    entries = described_class.discover(@dir)
    by_name = entries.to_h { |e| [e.name, e] }
    expect(by_name['user-server'].source).to eq(:user)
    expect(by_name['project-server'].source).to eq(:project)
  end
end
