# frozen_string_literal: true

require 'spec_helper'

RSpec.describe RubynCode::Tools::AskUser do
  let(:project_root) { '/tmp/test_project' }

  describe '#execute' do
    context 'with a prompt_callback injected' do
      it 'calls the callback with the question and returns the answer' do
        tool = described_class.new(project_root: project_root)
        tool.prompt_callback = ->(q) { "answer to: #{q}" }

        result = tool.execute(question: 'Which pattern should I follow?')
        expect(result).to eq('answer to: Which pattern should I follow?')
      end

      it 'returns whatever the callback returns' do
        tool = described_class.new(project_root: project_root)
        tool.prompt_callback = ->(_q) { 'use .call' }

        result = tool.execute(question: 'Service object style?')
        expect(result).to eq('use .call')
      end
    end

    context 'with an interactive TTY (no callback)' do
      it 'prompts on stdout and reads from stdin' do
        tool = described_class.new(project_root: project_root)

        # Simulate interactive stdin
        fake_stdin = StringIO.new("yes do it\n")
        allow(fake_stdin).to receive(:tty?).and_return(true)

        original_stdin = $stdin
        original_stdout = $stdout
        begin
          $stdin = fake_stdin
          $stdout = StringIO.new

          result = tool.execute(question: 'Should I proceed?')

          expect(result).to eq('yes do it')
          expect($stdout.string).to include('Should I proceed?')
          expect($stdout.string).to include('>')
        ensure
          $stdin = original_stdin
          $stdout = original_stdout
        end
      end

      it 'returns [no response] when stdin returns nil' do
        tool = described_class.new(project_root: project_root)

        fake_stdin = StringIO.new
        allow(fake_stdin).to receive(:tty?).and_return(true)
        allow(fake_stdin).to receive(:gets).and_return(nil)

        original_stdin = $stdin
        original_stdout = $stdout
        begin
          $stdin = fake_stdin
          $stdout = StringIO.new

          result = tool.execute(question: 'Hello?')
          expect(result).to eq('[no response]')
        ensure
          $stdin = original_stdin
          $stdout = original_stdout
        end
      end
    end

    context 'in a non-interactive session (no TTY, no callback)' do
      it 'returns a non-interactive message without blocking' do
        tool = described_class.new(project_root: project_root)

        fake_stdin = StringIO.new
        allow(fake_stdin).to receive(:tty?).and_return(false)

        original_stdin = $stdin
        begin
          $stdin = fake_stdin

          result = tool.execute(question: 'Are you there?')
          expect(result).to include('non-interactive')
          expect(result).to include('best judgment')
        ensure
          $stdin = original_stdin
        end
      end
    end
  end

  describe '.tool_name' do
    it 'is ask_user' do
      expect(described_class.tool_name).to eq('ask_user')
    end
  end

  describe '.risk_level' do
    it 'is read (never needs approval)' do
      expect(described_class.risk_level).to eq(:read)
    end
  end
end
