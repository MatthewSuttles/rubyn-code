# frozen_string_literal: true

require 'spec_helper'
require 'tmpdir'
require 'fileutils'

RSpec.describe RubynCode::Hooks::SettingsJsonLoader do
  def with_tempdir
    Dir.mktmpdir('rubyn_hook_settings_') { |dir| yield dir }
  end

  def write_json(dir, relative_path, content)
    full = File.join(dir, relative_path)
    FileUtils.mkdir_p(File.dirname(full))
    File.write(full, content)
    full
  end

  describe '#load' do
    it 'returns empty hash when no settings.json exists' do
      with_tempdir do |dir|
        loader = described_class.new(project_root: dir, home_dir: File.join(dir, 'home'))
        expect(loader.load).to eq({})
      end
    end

    it 'loads a single hook from project settings.json' do
      with_tempdir do |dir|
        write_json(dir, '.rubyn-code/settings.json', <<~JSON)
          {
            "hooks": {
              "PreToolUse": [
                {
                  "matcher": "bash",
                  "hooks": [
                    { "type": "command", "command": "/usr/local/bin/policy-check", "timeout": 30 }
                  ]
                }
              ]
            }
          }
        JSON

        loader = described_class.new(project_root: dir, home_dir: File.join(dir, 'home'))
        config = loader.load

        expect(config.keys).to eq(['PreToolUse'])
        expect(config['PreToolUse'].length).to eq(1)
        expect(config['PreToolUse'].first['matcher']).to eq('bash')
        expect(config['PreToolUse'].first['hooks'].first['command']).to eq('/usr/local/bin/policy-check')
        expect(config['PreToolUse'].first['hooks'].first['timeout']).to eq(30)
      end
    end

    it 'merges project and global settings (project wins for duplicates)' do
      with_tempdir do |dir|
        write_json(dir, '.rubyn-code/settings.json', <<~JSON)
          { "hooks": { "PreToolUse": [{ "matcher": "bash", "hooks": [{ "type": "command", "command": "project-hook" }] }] } }
        JSON
        home = File.join(dir, 'home')
        write_json(home, 'settings.json', <<~JSON)
          { "hooks": { "PostToolUse": [{ "matcher": "*", "hooks": [{ "type": "command", "command": "global-hook" }] }] } }
        JSON

        loader = described_class.new(project_root: dir, home_dir: home)
        config = loader.load

        expect(config.keys).to contain_exactly('PreToolUse', 'PostToolUse')
      end
    end

    it 'skips non-command hook entries' do
      with_tempdir do |dir|
        write_json(dir, '.rubyn-code/settings.json', <<~JSON)
          {
            "hooks": {
              "PreToolUse": [
                {
                  "matcher": "bash",
                  "hooks": [
                    { "type": "http", "url": "https://example.com" },
                    { "type": "command", "command": "real-hook" }
                  ]
                }
              ]
            }
          }
        JSON

        loader = described_class.new(project_root: dir, home_dir: File.join(dir, 'home'))
        config = loader.load

        expect(config['PreToolUse'].first['hooks'].length).to eq(1)
        expect(config['PreToolUse'].first['hooks'].first['command']).to eq('real-hook')
      end
    end

    it 'raises LoadError on malformed JSON' do
      with_tempdir do |dir|
        write_json(dir, '.rubyn-code/settings.json', '{ not json')
        loader = described_class.new(project_root: dir, home_dir: File.join(dir, 'home'))

        expect { loader.load }.to raise_error(described_class::LoadError, /Failed to parse/)
      end
    end

    it 'handles missing "hooks" key gracefully' do
      with_tempdir do |dir|
        write_json(dir, '.rubyn-code/settings.json', '{}')
        loader = described_class.new(project_root: dir, home_dir: File.join(dir, 'home'))
        expect(loader.load).to eq({})
      end
    end

    it 'skips matcher groups with no command hooks' do
      with_tempdir do |dir|
        write_json(dir, '.rubyn-code/settings.json', <<~JSON)
          {
            "hooks": {
              "PreToolUse": [
                { "matcher": "bash", "hooks": [{ "type": "prompt", "prompt": "Are you sure?" }] }
              ]
            }
          }
        JSON
        loader = described_class.new(project_root: dir, home_dir: File.join(dir, 'home'))
        # Event key is preserved (introspection-friendly) but contains no commands
        expect(loader.load).to eq('PreToolUse' => [])
      end
    end
  end
end
