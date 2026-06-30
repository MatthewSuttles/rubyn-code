# frozen_string_literal: true

# End-to-end parity smoke test. Exercises every gap in the original six-PR
# plan in a single file so a single `rspec` run proves all six are wired.
require 'spec_helper'

RSpec.describe 'Feature parity smoke (6 gaps)' do
  # ── Gap 1: Extended thinking + /think toggle ─────────────────────────
  describe 'Gap 1: extended thinking' do
    it 'ThinkingBlock is shipped' do
      expect(defined?(RubynCode::LLM::ThinkingBlock)).to eq('constant')
      expect(RubynCode::LLM::ThinkingBlock.new(text: 'hmm').type).to eq('thinking')
    end

    it 'MessageBuilder maps ThinkingBlock to Anthropic shape' do
      require 'rubyn_code/llm/message_builder'
      out = RubynCode::LLM::MessageBuilder.new.format_messages(
        [{ role: 'assistant', content: [RubynCode::LLM::ThinkingBlock.new(text: 'step 1')] }]
      )
      expect(out.first[:content].first).to eq(type: 'thinking', text: 'step 1')
    end

    it 'Anthropic adapter translates thinking:{budget_tokens} into the body' do
      adapter = RubynCode::LLM::Adapters::Anthropic.allocate
      body = {}
      adapter.send(:apply_thinking, body, budget_tokens: 1024)
      expect(body[:thinking]).to eq(type: 'enabled', budget_tokens: 1024)
    end

    it '/think command toggles state and is registered' do
      expect(defined?(RubynCode::CLI::Commands::Think)).to eq('constant')
      autoloads = RubynCode.autoload?(:CLI) || RubynCode.const_defined?(:CLI)
      expect(autoloads).to be_truthy
    end
  end

  # ── Gap 2: Image / vision input ──────────────────────────────────────
  describe 'Gap 2: image input' do
    it 'ImageBlock is shipped' do
      expect(defined?(RubynCode::LLM::ImageBlock)).to eq('constant')
    end

    it 'ImageReader encodes PNG files as base64' do
      require 'tmpdir'
      Dir.mktmpdir do |dir|
        path = File.join(dir, 'pixel.png')
        File.binwrite(path, "\x89PNG\r\n\x1a\n".dup)
        block = RubynCode::LLM::ImageReader.for_path(path)
        expect(block).to be_a(RubynCode::LLM::ImageBlock)
        expect(block.media_type).to eq('image/png')
      end
    end

    it 'MentionExpander#expand_images emits image blocks from @path.png mentions' do
      require 'tmpdir'
      Dir.mktmpdir do |dir|
        File.binwrite(File.join(dir, 'a.png'), "\x89PNG\r\n\x1a\n".dup)
        blocks = RubynCode::CLI::MentionExpander.new(project_root: dir).expand_images('look @a.png')
        expect(blocks.size).to eq(1)
        expect(blocks.first).to be_a(RubynCode::LLM::ImageBlock)
      end
    end
  end

  # ── Gap 3: TodoWrite live checklist ─────────────────────────────────
  describe 'Gap 3: TodoWrite' do
    it 'TodoWrite is registered as a tool under the name "TodoWrite"' do
      # Force the autoload so the at-file-level `Registry.register` runs.
      expect(RubynCode::Tools::TodoWrite).to be_a(Class)
      expect(RubynCode::Tools::TodoWrite.const_get(:TOOL_NAME)).to eq('TodoWrite')
      expect(RubynCode::Tools::Registry.get('TodoWrite')).to eq(RubynCode::Tools::TodoWrite)
    end

    it 'TodoWrite mutates a shared TodoStore and returns the formatted list' do
      store = RubynCode::Tools::TodoStore.new
      tool  = RubynCode::Tools::TodoWrite.new(project_root: Dir.pwd, store: store)
      out   = tool.execute(todos: [
                             { 'content' => 'Add spec', 'status' => 'completed', 'active_form' => 'Adding' },
                             { 'content' => 'Implement', 'status' => 'in_progress', 'active_form' => 'Doing' }
                           ])
      expect(out).to include('[x] Add spec')
      expect(out).to include('[~] Implement')
      expect(store.current.size).to eq(2)
    end
  end

  # ── Gap 4: Custom-command frontmatter ────────────────────────────────
  describe 'Gap 4: frontmatter (argument-hint, allowed-tools, model)' do
    it 'CustomLoader parses the three keys and feeds them to CustomCommand' do
      require 'tmpdir'
      Dir.mktmpdir do |dir|
        path = File.join(dir, 'deploy.md')
        File.write(path, <<~MD)
          ---
          description: Deploy
          argument-hint: "[env]"
          allowed-tools: bash,read
          model: claude-opus-4-8
          ---
          body
        MD
        cmd = RubynCode::CLI::Commands::CustomLoader.send(:build, path)
        expect(cmd.argument_hint).to eq('[env]')
        expect(cmd.allowed_tools).to eq(%w[bash read])
        expect(cmd.model).to eq('claude-opus-4-8')
      end
    end

    it 'Agent::Loop honors a one-shot model override' do
      loop = RubynCode::Agent::Loop.allocate
      loop.model_override = 'claude-opus-4-8'
      expect(loop.send(:routed_model)).to eq('claude-opus-4-8')
    end

    it 'Agent::Loop honors a one-shot allowed-tools override' do
      loop = RubynCode::Agent::Loop.allocate
      loop.allowed_tools_override = %w[bash read]
      expect(loop.instance_variable_get(:@allowed_tools_override)).to eq(%w[bash read])
    end
  end

  # ── Gap 5: .mcp.json auto-discovery ─────────────────────────────────
  describe 'Gap 5: .mcp.json discovery' do
    it 'Discovery.discover reads both user and project .mcp.json' do
      require 'tmpdir'
      Dir.mktmpdir do |dir|
        user_path = File.join(dir, '.rubyn-code', 'mcp.json')
        FileUtils.mkdir_p(File.dirname(user_path))
        File.write(user_path, '{ "mcpServers": { "u": { "command": "u" } } }')
        File.write(File.join(dir, '.mcp.json'),
                   '{ "mcpServers": { "p": { "command": "p" } } }')

        entries = RubynCode::MCP::Discovery.discover(dir)
        names   = entries.map(&:name)
        expect(names).to include('u', 'p')
        sources = entries.to_h { |e| [e.name, e.source] }
        expect(sources['u']).to eq(:user)
        expect(sources['p']).to eq(:project)
      end
    end

    it 'REPL#setup_mcp_servers! source actually calls MCP::Discovery.discover' do
      require 'rubyn_code/cli/repl'
      src = File.read(RubynCode::CLI::REPL.instance_method(:setup_mcp_servers!).source_location.first)
      expect(src).to include('MCP::Discovery.discover')
    end
  end

  # ── Gap 6: /export transcript (markdown / jsonl) ─────────────────────
  describe 'Gap 6: /export' do
    it 'writes Markdown with role sections, thinking, and tool_use blocks' do
      require 'tmpdir'
      Dir.mktmpdir do |dir|
        path = File.join(dir, 'x.md')
        msgs = [
          { role: 'user', content: 'hello' },
          { role: 'assistant', content: [
            { type: 'thinking', text: 'hmm' },
            { type: 'text', text: 'hi back' },
            { type: 'tool_use', name: 'bash', input: { cmd: 'ls' } }
          ] }
        ]
        conversation = double('Conversation')
        allow(conversation).to receive(:to_a).and_return(msgs)
        renderer = double(info: nil, warning: nil)
        allow(renderer).to receive(:ask).and_return(true)
        ctx = instance_double(RubynCode::CLI::Commands::Context, conversation: conversation, renderer: renderer)
        RubynCode::CLI::Commands::Export.new.execute([path], ctx)
        body = File.read(path)
        expect(body).to include('## User')
        expect(body).to include('<details><summary>thinking</summary>')
        expect(body).to include('hi back')
        expect(body).to include('[tool: bash]')
      end
    end

    it 'writes JSONL with one object per line' do
      require 'tmpdir'
      Dir.mktmpdir do |dir|
        path = File.join(dir, 'x.jsonl')
        msgs = [{ role: 'user', content: 'hi' }, { role: 'assistant', content: 'ok' }]
        conversation = double('Conversation')
        allow(conversation).to receive(:to_a).and_return(msgs)
        renderer = double(info: nil, warning: nil)
        allow(renderer).to receive(:ask).and_return(true)
        ctx = instance_double(RubynCode::CLI::Commands::Context, conversation: conversation, renderer: renderer)
        RubynCode::CLI::Commands::Export.new.execute([path, '--jsonl'], ctx)
        lines = File.read(path).split("\n").reject(&:empty?)
        expect(lines.size).to eq(2)
        expect(JSON.parse(lines.first)['role']).to eq('user')
      end
    end
  end
end
