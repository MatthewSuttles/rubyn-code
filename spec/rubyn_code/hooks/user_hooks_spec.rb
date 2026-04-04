# frozen_string_literal: true

require 'spec_helper'

RSpec.describe RubynCode::Hooks::UserHooks do
  let(:registry) { RubynCode::Hooks::Registry.new }

  def with_temp_project
    Dir.mktmpdir('rubyn_test_') do |dir|
      yield dir
    end
  end

  def write_hooks_yml(dir, content, global: false)
    if global
      path = File.join(dir, 'hooks.yml')
    else
      hooks_dir = File.join(dir, '.rubyn-code')
      FileUtils.mkdir_p(hooks_dir)
      path = File.join(hooks_dir, 'hooks.yml')
    end
    File.write(path, content)
    path
  end

  describe '.load!' do
    it 'loads hooks from project .rubyn-code/hooks.yml' do
      with_temp_project do |dir|
        write_hooks_yml(dir, <<~YAML)
          pre_tool_use:
            - tool: bash
              match: "rm -rf"
              action: deny
              reason: "Destructive delete blocked"
        YAML

        described_class.load!(registry, project_root: dir)

        hooks = registry.hooks_for(:pre_tool_use)
        expect(hooks.length).to eq(1)
      end
    end

    it 'loads hooks from global hooks.yml' do
      with_temp_project do |dir|
        # Stub the global path to point to our temp dir
        global_dir = File.join(dir, 'global_home')
        FileUtils.mkdir_p(global_dir)
        File.write(File.join(global_dir, 'hooks.yml'), <<~YAML)
          post_tool_use:
            - tool: write_file
              action: log
        YAML

        stub_const('RubynCode::Config::Defaults::HOME_DIR', global_dir)

        described_class.load!(registry, project_root: dir)

        hooks = registry.hooks_for(:post_tool_use)
        expect(hooks.length).to eq(1)
      end
    end

    it 'registers pre_tool_use deny hooks that block matching tool calls' do
      with_temp_project do |dir|
        write_hooks_yml(dir, <<~YAML)
          pre_tool_use:
            - tool: bash
              match: "rm -rf"
              action: deny
              reason: "Destructive delete blocked"
        YAML

        described_class.load!(registry, project_root: dir)

        hook = registry.hooks_for(:pre_tool_use).first
        result = hook.call(tool_name: 'bash', tool_input: { command: 'rm -rf /' })

        expect(result).to eq({ deny: true, reason: 'Destructive delete blocked' })
      end
    end

    it 'does not deny when tool name does not match' do
      with_temp_project do |dir|
        write_hooks_yml(dir, <<~YAML)
          pre_tool_use:
            - tool: bash
              match: "rm -rf"
              action: deny
              reason: "Blocked"
        YAML

        described_class.load!(registry, project_root: dir)

        hook = registry.hooks_for(:pre_tool_use).first
        result = hook.call(tool_name: 'write_file', tool_input: { path: 'foo.rb' })

        expect(result).to be_nil
      end
    end

    it 'does not deny when match pattern is not found in input' do
      with_temp_project do |dir|
        write_hooks_yml(dir, <<~YAML)
          pre_tool_use:
            - tool: bash
              match: "rm -rf"
              action: deny
              reason: "Blocked"
        YAML

        described_class.load!(registry, project_root: dir)

        hook = registry.hooks_for(:pre_tool_use).first
        result = hook.call(tool_name: 'bash', tool_input: { command: 'ls -la' })

        expect(result).to be_nil
      end
    end

    it 'registers post_tool_use log hooks' do
      with_temp_project do |dir|
        write_hooks_yml(dir, <<~YAML)
          post_tool_use:
            - tool: write_file
              action: log
        YAML

        described_class.load!(registry, project_root: dir)

        hooks = registry.hooks_for(:post_tool_use)
        expect(hooks.length).to eq(1)

        # Execute the hook and verify it writes an audit log
        Dir.chdir(dir) do
          hook = hooks.first
          result = hook.call(tool_name: 'write_file', result: 'Wrote foo.rb')

          expect(result).to eq('Wrote foo.rb')
          audit_log = File.join('.rubyn-code', 'audit.log')
          expect(File.exist?(audit_log)).to be true
          expect(File.read(audit_log)).to include('write_file')
        end
      end
    end

    it 'skips when no hooks files exist' do
      with_temp_project do |dir|
        # Stub global to a non-existent path too
        stub_const('RubynCode::Config::Defaults::HOME_DIR', File.join(dir, 'nonexistent'))

        expect { described_class.load!(registry, project_root: dir) }.not_to raise_error

        expect(registry.hooks_for(:pre_tool_use)).to be_empty
        expect(registry.hooks_for(:post_tool_use)).to be_empty
      end
    end

    it 'handles empty config gracefully' do
      with_temp_project do |dir|
        write_hooks_yml(dir, '')

        expect { described_class.load!(registry, project_root: dir) }.not_to raise_error

        expect(registry.hooks_for(:pre_tool_use)).to be_empty
      end
    end

    it 'handles config with nil values gracefully' do
      with_temp_project do |dir|
        write_hooks_yml(dir, <<~YAML)
          pre_tool_use:
          post_tool_use:
        YAML

        expect { described_class.load!(registry, project_root: dir) }.not_to raise_error

        expect(registry.hooks_for(:pre_tool_use)).to be_empty
        expect(registry.hooks_for(:post_tool_use)).to be_empty
      end
    end

    it 'loads hooks from both project and global files' do
      with_temp_project do |dir|
        write_hooks_yml(dir, <<~YAML)
          pre_tool_use:
            - tool: bash
              match: "rm -rf"
              action: deny
              reason: "Project hook"
        YAML

        global_dir = File.join(dir, 'global_home')
        FileUtils.mkdir_p(global_dir)
        File.write(File.join(global_dir, 'hooks.yml'), <<~YAML)
          pre_tool_use:
            - tool: bash
              match: "sudo"
              action: deny
              reason: "Global hook"
        YAML

        stub_const('RubynCode::Config::Defaults::HOME_DIR', global_dir)

        described_class.load!(registry, project_root: dir)

        hooks = registry.hooks_for(:pre_tool_use)
        expect(hooks.length).to eq(2)
      end
    end
  end
end
