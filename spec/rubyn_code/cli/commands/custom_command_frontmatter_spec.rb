# frozen_string_literal: true

require 'spec_helper'
require 'tmpdir'
require 'fileutils'

RSpec.describe RubynCode::CLI::Commands::CustomCommand do
  describe 'frontmatter parsing' do
    around do |ex|
      Dir.mktmpdir do |dir|
        @dir = dir
        ex.run
      end
    end

    def load(content)
      RubynCode::CLI::Commands::CustomLoader.send(:parse, content)
    end

    it 'extracts description from frontmatter' do
      meta, body = load("---\ndescription: Hi\n---\nbody")
      expect(meta['description']).to eq('Hi')
      expect(body).to eq('body')
    end

    it 'extracts argument-hint (hyphen)' do
      meta, = load("---\nargument-hint: <name>\n---\n")
      expect(meta['argument-hint']).to eq('<name>')
    end

    it 'extracts argument_hint (underscore)' do
      meta, = load("---\nargument_hint: <name>\n---\n")
      expect(meta['argument_hint']).to eq('<name>')
    end

    it 'parses allowed-tools as comma-separated list' do
      meta, = load("---\nallowed-tools: bash, read\n---\n")
      expect(meta['allowed-tools']).to eq('bash, read')
    end

    it 'parses allowed-tools as YAML array' do
      meta, = load("---\nallowed-tools:\n  - bash\n  - read\n---\n")
      expect(meta['allowed-tools']).to eq(%w[bash read])
    end

    it 'extracts model override' do
      meta, = load("---\nmodel: claude-opus-4-8\n---\n")
      expect(meta['model']).to eq('claude-opus-4-8')
    end
  end

  describe RubynCode::CLI::Commands::CustomLoader, '.build' do
    around do |ex|
      Dir.mktmpdir do |dir|
        @dir = dir
        ex.run
      end
    end

    it 'builds a CustomCommand with argument_hint, allowed_tools, model from frontmatter' do
      path = File.join(@dir, 'deploy.md')
      File.write(path, <<~MD)
        ---
        description: Deploy the app
        argument-hint: "[env]"
        allowed-tools: bash,read
        model: claude-opus-4-8
        ---
        Deploy to $ARGUMENTS now.
      MD

      cmd = RubynCode::CLI::Commands::CustomLoader.send(:build, path)
      expect(cmd).to be_a(RubynCode::CLI::Commands::CustomCommand)
      expect(cmd.description).to eq('Deploy the app')
      expect(cmd.argument_hint).to eq('[env]')
      expect(cmd.allowed_tools).to eq(%w[bash read])
      expect(cmd.model).to eq('claude-opus-4-8')
    end

    it 'fills in a default description when missing' do
      path = File.join(@dir, 'noop.md')
      File.write(path, '')
      cmd = RubynCode::CLI::Commands::CustomLoader.send(:build, path)
      expect(cmd.description).to eq('Custom command: /noop')
      expect(cmd.argument_hint).to be_nil
      expect(cmd.allowed_tools).to be_nil
      expect(cmd.model).to be_nil
    end

    it 'leaves allowed_tools nil when not declared' do
      path = File.join(@dir, 'plain.md')
      File.write(path, "---\ndescription: plain\n---\n")
      cmd = RubynCode::CLI::Commands::CustomLoader.send(:build, path)
      expect(cmd.allowed_tools).to be_nil
      expect(cmd.model).to be_nil
      expect(cmd.argument_hint).to be_nil
      expect(cmd.restricts_tools?).to be(false)
      expect(cmd.overrides_model?).to be(false)
    end

    it 'flags a custom command with allowed_tools as restricting' do
      path = File.join(@dir, 'restrict.md')
      File.write(path, "---\nallowed-tools:\n  - bash\n  - read\n---\nbody")
      cmd = RubynCode::CLI::Commands::CustomLoader.send(:build, path)
      expect(cmd.allowed_tools).to eq(%w[bash read])
      expect(cmd.restricts_tools?).to be(true)
    end
  end

  describe RubynCode::CLI::Commands::CustomCommand, '#help_label' do
    it 'shows argument hint in brackets when set' do
      cmd = described_class.new(name: 'x', description: 'd', body: 'b', argument_hint: '[env]')
      expect(cmd.help_label).to eq('d  [env]')
    end

    it 'falls back to description when no hint' do
      cmd = described_class.new(name: 'x', description: 'd', body: 'b')
      expect(cmd.help_label).to eq('d')
    end

    it 'omits brackets when argument hint is empty string' do
      cmd = described_class.new(name: 'x', description: 'd', body: 'b', argument_hint: '  ')
      expect(cmd.help_label).to eq('d')
    end
  end

  describe RubynCode::CLI::Commands::CustomCommand, '#execute' do
    let(:ctx) { instance_double(RubynCode::CLI::Commands::Context) }

    before do
      allow(ctx).to receive(:with_optional_model).and_yield
      allow(ctx).to receive(:with_allowed_tools).and_yield
      allow(ctx).to receive(:send_message)
    end

    it 'renders the template and sends the message' do
      cmd = described_class.new(name: 'hi', description: '', body: 'hello $ARGUMENTS', argument_hint: '<name>')
      cmd.execute(['world'], ctx)
      expect(ctx).to have_received(:send_message).with('hello world')
    end

    it 'invokes the model override wrapper when set' do
      cmd = described_class.new(name: 'm', description: '', body: 'b', model: 'claude-opus-4-8')
      cmd.execute([], ctx)
      expect(ctx).to have_received(:with_optional_model).with('claude-opus-4-8')
    end

    it 'invokes the allowed-tools wrapper when set' do
      cmd = described_class.new(name: 'a', description: '', body: 'b', allowed_tools: %w[bash])
      cmd.execute([], ctx)
      expect(ctx).to have_received(:with_allowed_tools).with(%w[bash])
    end

    it 'skips wrappers when neither override is set' do
      cmd = described_class.new(name: 's', description: '', body: 'b')
      cmd.execute([], ctx)
      expect(ctx).not_to have_received(:with_optional_model)
      expect(ctx).not_to have_received(:with_allowed_tools)
    end
  end
end
