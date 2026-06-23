# frozen_string_literal: true

require 'spec_helper'

RSpec.describe RubynCode::Hooks::ExternalDispatcher do
  let(:project_root) { '/tmp/rubyn_dispatcher_test' }

  # In-process fake of the executor so we don't spawn real subprocesses.
  class FakeExecutor
    attr_reader :calls

    def initialize(responses: [])
      @responses = responses.dup
      @calls = []
    end

    def run(command:, args: [], env: {}, payload:, timeout: nil)
      @calls << { command: command, env: env, payload: payload, timeout: timeout }
      @responses.shift || {}
    end
  end

  def build(config:, responses: [], logger: nil)
    exe = FakeExecutor.new(responses: responses)
    dispatcher = described_class.new(project_root: project_root, config: config, executor: exe, logger: logger)
    [dispatcher, exe]
  end

  describe '#configured_for?' do
    it 'returns true when an event has hooks' do
      dispatcher, _ = build(config: { 'PreToolUse' => [{ 'matcher' => '*', 'hooks' => [{ 'command' => 'x' }] }] })
      expect(dispatcher.configured_for?(:pre_tool_use)).to be true
    end

    it 'returns false for events without hooks' do
      dispatcher, _ = build(config: {})
      expect(dispatcher.configured_for?(:pre_tool_use)).to be false
      expect(dispatcher.configured_for?(:on_error)).to be false
    end
  end

  describe '#fire — envelope construction' do
    it 'builds a PreToolUse envelope with toolName and toolInput' do
      dispatcher, exe = build(
        config: { 'PreToolUse' => [{ 'matcher' => '*', 'hooks' => [{ 'command' => 'check' }] }] },
        responses: [{}]
      )

      dispatcher.fire(:pre_tool_use, tool_name: 'bash', tool_input: { 'command' => 'ls' })

      expect(exe.calls.length).to eq(1)
      payload = exe.calls.first[:payload]
      expect(payload['hookEventName']).to eq('PreToolUse')
      expect(payload['toolName']).to eq('bash')
      expect(payload['toolInput']).to eq('command' => 'ls')
    end

    it 'builds a UserPromptSubmit envelope with prompt' do
      dispatcher, exe = build(
        config: { 'UserPromptSubmit' => [{ 'matcher' => '*', 'hooks' => [{ 'command' => 'inspect' }] }] },
        responses: [{}]
      )

      dispatcher.fire(:user_prompt_submit, prompt: 'Refactor foo')

      payload = exe.calls.first[:payload]
      expect(payload['hookEventName']).to eq('UserPromptSubmit')
      expect(payload['prompt']).to eq('Refactor foo')
    end

    it 'builds a SessionStart envelope' do
      dispatcher, exe = build(
        config: { 'SessionStart' => [{ 'matcher' => '*', 'hooks' => [{ 'command' => 'init' }] }] },
        responses: [{}]
      )

      dispatcher.fire(:session_start, session_id: 'sess-123')

      payload = exe.calls.first[:payload]
      expect(payload['hookEventName']).to eq('SessionStart')
      expect(payload['sessionId']).to eq('sess-123')
    end
  end

  describe '#fire — matcher filtering' do
    it 'only invokes hooks whose matcher matches the tool name' do
      dispatcher, exe = build(
        config: {
          'PreToolUse' => [
            { 'matcher' => 'bash', 'hooks' => [{ 'command' => 'bash-hook' }] },
            { 'matcher' => 'write_file', 'hooks' => [{ 'command' => 'wf-hook' }] }
          ]
        },
        responses: [{}, {}]
      )

      dispatcher.fire(:pre_tool_use, tool_name: 'bash', tool_input: {})

      commands = exe.calls.map { |c| c[:command] }
      expect(commands).to eq(['bash-hook'])
    end

    it 'treats "*" as match-all' do
      dispatcher, exe = build(
        config: { 'PreToolUse' => [{ 'matcher' => '*', 'hooks' => [{ 'command' => 'all' }] }] },
        responses: [{}]
      )

      dispatcher.fire(:pre_tool_use, tool_name: 'anything', tool_input: {})

      expect(exe.calls.length).to eq(1)
    end

    it 'accepts regex matchers' do
      dispatcher, exe = build(
        config: { 'PreToolUse' => [{ 'matcher' => '^bash|write_', 'hooks' => [{ 'command' => 'regex-hook' }] }] },
        responses: [{}]
      )

      dispatcher.fire(:pre_tool_use, tool_name: 'write_file', tool_input: {})
      dispatcher.fire(:pre_tool_use, tool_name: 'read_file', tool_input: {})

      expect(exe.calls.length).to eq(1)
      expect(exe.calls.first[:command]).to eq('regex-hook')
    end
  end

  describe '#fire — response merging' do
    it 'merges block decisions into a single Response' do
      dispatcher, _ = build(
        config: {
          'PreToolUse' => [
            { 'matcher' => '*', 'hooks' => [
              { 'command' => 'a' },
              { 'command' => 'b' }
            ] }
          ]
        },
        responses: [
          { 'decision' => 'block', 'reason' => 'denied by A' },
          { 'decision' => 'block', 'reason' => 'denied by B' }
        ]
      )

      response = dispatcher.fire(:pre_tool_use, tool_name: 'x', tool_input: {})
      expect(response.block?).to be true
      expect(response.reason).to eq('denied by A') # first wins
    end

    it 'injects additionalContext into the response envelope' do
      dispatcher, _ = build(
        config: { 'PreToolUse' => [{ 'matcher' => '*', 'hooks' => [{ 'command' => 'ctx' }] }] },
        responses: [{
          'hookSpecificOutput' => {
            'hookEventName' => 'PreToolUse',
            'additionalContext' => 'Always run rubocop'
          }
        }]
      )

      response = dispatcher.fire(:pre_tool_use, tool_name: 'x', tool_input: {})
      expect(response.additional_context?).to be true
      expect(response.additional_context).to eq('Always run rubocop')
    end

    it 'returns empty Response when no hooks are configured' do
      dispatcher, _ = build(config: {})
      response = dispatcher.fire(:pre_tool_use, tool_name: 'x', tool_input: {})
      expect(response.block?).to be false
      expect(response.stop?).to be false
      expect(response.additional_context?).to be false
    end

    it 'honors continue=false as a stop signal' do
      dispatcher, _ = build(
        config: { 'Stop' => [{ 'matcher' => '*', 'hooks' => [{ 'command' => 'stopper' }] }] },
        responses: [{ 'continue' => false, 'stopReason' => 'policy says stop' }]
      )

      response = dispatcher.fire(:stop, reason: 'agent finished')
      expect(response.stop?).to be true
      expect(response.stop_reason).to eq('policy says stop')
    end
  end

  describe '#fire — error handling' do
    let(:logger) { ->(msg) { @log_messages ||= []; @log_messages << msg } }

    it 'logs and continues when a hook subprocess fails' do
      executor = double('executor')
      allow(executor).to receive(:run).and_raise(RubynCode::Hooks::SubprocessExecutor::TimeoutError, 'Hook command timed out after 60s')

      dispatcher = described_class.new(
        project_root: project_root,
        config: { 'PreToolUse' => [{ 'matcher' => '*', 'hooks' => [{ 'command' => 'bad' }] }] },
        executor: executor,
        logger: logger
      )

      response = dispatcher.fire(:pre_tool_use, tool_name: 'x', tool_input: {})
      expect(response.block?).to be false
      expect(@log_messages.length).to eq(1)
      expect(@log_messages.first).to include("hook 'bad' failed")
      expect(@log_messages.first).to include('timed out')
    end

    it 'swallows executor errors so other hooks still run' do
      executor = double('executor')
      call_count = 0
      allow(executor).to receive(:run) do
        call_count += 1
        call_count == 1 ? raise(RubynCode::Hooks::SubprocessExecutor::ExecutionError, 'boom') : { 'decision' => 'block', 'reason' => 'second' }
      end

      dispatcher = described_class.new(
        project_root: project_root,
        config: { 'PreToolUse' => [{ 'matcher' => '*', 'hooks' => [{ 'command' => 'a' }, { 'command' => 'b' }] }] },
        executor: executor,
        logger: logger
      )

      response = dispatcher.fire(:pre_tool_use, tool_name: 'x', tool_input: {})
      expect(response.block?).to be true
      expect(response.reason).to eq('second')
    end
  end

  describe '#fire — events with no external mapping' do
    it 'returns empty Response without spawning anything' do
      executor = double('executor')
      expect(executor).not_to receive(:run)
      dispatcher = described_class.new(project_root: project_root, config: {}, executor: executor)

      response = dispatcher.fire(:on_error, error: 'boom')
      expect(response.block?).to be false
    end
  end
end
