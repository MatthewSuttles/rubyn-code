# frozen_string_literal: true

require 'spec_helper'
require 'tmpdir'
require 'fileutils'
require 'json'

RSpec.describe RubynCode::CLI::Commands::Export do
  subject(:command) { described_class.new }

  around do |ex|
    Dir.mktmpdir do |dir|
      @dir = dir
      ex.run
    end
  end

  let(:renderer) { double('Renderer', info: nil, warning: nil, ask: true) }
  let(:messages) do
    [
      { role: 'user', content: 'Hello, rubyn' },
      { role: 'assistant', content: [
        { type: 'thinking', text: 'reasoning step' },
        { type: 'text', text: 'I can help.' }
      ] },
      { role: 'user', content: 'Look at @chart.png' },
      { role: 'assistant', content: [
        { type: 'tool_use', name: 'grep', input: { pattern: 'ChartPicker' } }
      ] },
      { role: 'tool', content: 'no matches' }
    ]
  end
  let(:conversation) do
    double('Conversation').tap { |c| allow(c).to receive(:to_a).and_return(messages) }
  end
  let(:ctx) do
    instance_double(
      RubynCode::CLI::Commands::Context,
      conversation: conversation, renderer: renderer
    )
  end

  describe '.command_name / .description' do
    it { expect(described_class.command_name).to eq('/export') }
    it { expect(described_class.description).to be_a(String) }
  end

  describe '#execute' do
    it 'writes a Markdown transcript' do
      path = File.join(@dir, 'transcript.md')
      command.execute([path], ctx)
      expect(File.exist?(path)).to be(true)
      body = File.read(path)
      expect(body).to include('# Rubyn transcript')
      expect(body).to include('## User')
      expect(body).to include('Hello, rubyn')
      expect(body).to include('<details><summary>thinking</summary>')
      expect(body).to include('[tool: grep]')
      expect(renderer).to have_received(:info).with(/Exported \d+ messages/)
    end

    it 'writes a JSONL transcript when --format jsonl is given' do
      path = File.join(@dir, 'transcript.jsonl')
      command.execute([path, '--jsonl'], ctx)
      lines = File.read(path).split("\n").reject(&:empty?)
      expect(lines.size).to eq(messages.size)
      parsed = lines.map { |l| JSON.parse(l) }
      expect(parsed.first['role']).to eq('user')
      expect(parsed.first['content']).to eq('Hello, rubyn')
      expect(parsed[1]['content'].first['type']).to eq('thinking')
      expect(parsed[3]['content'].first['type']).to eq('tool_use')
    end

    it 'creates parent directories as needed' do
      path = File.join(@dir, 'nested', 'deep', 'out.md')
      command.execute([path], ctx)
      expect(File.exist?(path)).to be(true)
    end

    it 'refuses an empty conversation' do
      allow(conversation).to receive(:to_a).and_return([])
      path = File.join(@dir, 'empty.md')
      command.execute([path], ctx)
      expect(File.exist?(path)).to be(false)
      expect(renderer).to have_received(:warning).with(/No messages/)
    end

    it 'refuses to overwrite without confirmation' do
      path = File.join(@dir, 'exists.md')
      File.write(path, 'old content')
      allow(renderer).to receive(:ask).and_return(false)
      command.execute([path], ctx)
      expect(File.read(path)).to eq('old content')
      expect(renderer).to have_received(:info).with(/cancelled/i)
    end

    it 'overwrites when --force is given' do
      path = File.join(@dir, 'exists.md')
      File.write(path, 'old')
      command.execute([path, '--force'], ctx)
      expect(File.read(path)).not_to eq('old')
      expect(File.read(path)).to include('Rubyn transcript')
    end
  end

  describe '#render_markdown' do
    it 'uses _command output style for image attachments' do
      msgs = [
        { role: 'user', content: [
          { type: 'text', text: 'check this' },
          { type: 'image', source: { type: 'base64', media_type: 'image/png', data: 'X' } }
        ] }
      ]
      path = File.join(@dir, 'image.md')
      command.execute([path], ctx)
      # Need messages to populate ctx; instead test render_markdown via execute with new msgs
      convo = double('Conversation')
      allow(convo).to receive(:to_a).and_return(msgs)
      allow(renderer).to receive(:ask).and_return(true)
      ctx2 = instance_double(RubynCode::CLI::Commands::Context, conversation: convo, renderer: renderer)
      command.execute([path], ctx2)
      expect(File.read(path)).to include('_(image attachment)_')
    end
  end
end
