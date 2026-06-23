# frozen_string_literal: true

require 'spec_helper'
require 'tmpdir'
require 'fileutils'

RSpec.describe RubynCode::Hooks::SubprocessExecutor do
  let(:project_root) { Dir.mktmpdir('rubyn_hook_exec_') }
  after { FileUtils.remove_entry(project_root) if File.directory?(project_root) }

  subject(:executor) { described_class.new(project_root: project_root, default_timeout: 10) }

  # Helper: write a small Ruby script to a temp file and run it. Avoids
  # quoting hell with `-e` and the `-rjson` arg under bundled environments
  # that intermittently strip child require paths.
  def run_ruby_script(script, env_overrides: {})
    script_path = File.join(project_root, "hook_#{Process.pid}_#{rand(10_000)}.rb")
    File.write(script_path, "require 'json'\n$stdout.sync = true\n#{script}\n")
    File.chmod(0o755, script_path)
    executor.run(command: 'ruby', args: [script_path], payload: { 'hookEventName' => 'Test' })
  end

  describe '#run' do
    it 'sends the payload as JSON to stdin and parses stdout' do
      result = run_ruby_script('payload = JSON.parse(STDIN.read); puts JSON.generate(echo: payload["hookEventName"], tool: payload["toolName"])', env_overrides: { 'toolName' => 'bash' })
      # The script above only reads hookEventName; verify by re-running with full payload via direct call
      result = executor.run(
        command: 'ruby',
        args: [File.join(project_root, 'hook.rb')].tap { File.write(File.join(project_root, 'hook.rb'), "require 'json'\n$stdout.sync = true\npayload = JSON.parse(STDIN.read)\nputs JSON.generate(echo: payload['hookEventName'], tool: payload['toolName'])\n"); File.chmod(0o755, File.join(project_root, 'hook.rb')) },
        payload: { 'hookEventName' => 'PreToolUse', 'toolName' => 'bash' }
      )
      expect(result).to eq('echo' => 'PreToolUse', 'tool' => 'bash')
    end

    it 'returns empty hash when command produces no output' do
      quiet = File.join(project_root, 'quiet.rb')
      File.write(quiet, "exit 0\n")
      File.chmod(0o755, quiet)

      result = executor.run(
        command: 'ruby',
        args: [quiet],
        payload: { 'hookEventName' => 'SessionStart' }
      )
      expect(result).to eq({})
    end

    it 'raises ExecutionError when the command is not found' do
      expect do
        executor.run(command: '/nonexistent/command-xyz', payload: {})
      end.to raise_error(described_class::ExecutionError, /not found/)
    end

    it 'raises TimeoutError when the command exceeds the timeout' do
      slow = File.join(project_root, 'slow.rb')
      File.write(slow, "sleep 5\n")
      File.chmod(0o755, slow)

      expect do
        described_class.new(project_root: project_root, default_timeout: 1).run(
          command: 'ruby', args: [slow], payload: {}
        )
      end.to raise_error(described_class::TimeoutError, /timed out/)
    end

    it 'parses newline-delimited JSON when whole output is not JSON' do
      script = File.join(project_root, 'ndjson.rb')
      File.write(script, "require 'json'\n$stdout.sync = true\nputs 'log line'\nputs JSON.generate(decision: 'block', reason: 'x')\n")
      File.chmod(0o755, script)

      result = executor.run(command: 'ruby', args: [script], payload: {})
      expect(result).to eq('decision' => 'block', 'reason' => 'x')
    end

    it 'returns the first parseable line when multiple JSON objects are emitted' do
      script = File.join(project_root, 'multi.rb')
      File.write(script, "require 'json'\n$stdout.sync = true\nputs JSON.generate(first: 1)\nputs JSON.generate(second: 2)\n")
      File.chmod(0o755, script)

      result = executor.run(command: 'ruby', args: [script], payload: {})
      expect(result).to eq('first' => 1)
    end

    it 'wraps non-JSON scalar output' do
      script = File.join(project_root, 'plain.rb')
      File.write(script, "puts 'hello'\n")
      File.chmod(0o755, script)

      result = executor.run(command: 'ruby', args: [script], payload: {})
      expect(result).to eq('output' => "hello\n")
    end

    it 'sets CLAUDE_PROJECT_DIR in the hook environment' do
      script = File.join(project_root, 'env.rb')
      File.write(script, "require 'json'\n$stdout.sync = true\nputs JSON.generate(env: ENV['CLAUDE_PROJECT_DIR'])\n")
      File.chmod(0o755, script)

      result = executor.run(command: 'ruby', args: [script], payload: {})
      expect(result['env']).to eq(project_root)
    end

    it 'merges user-supplied env vars on top of defaults' do
      script = File.join(project_root, 'userenv.rb')
      File.write(script, "require 'json'\n$stdout.sync = true\nputs JSON.generate(extra: ENV['MY_HOOK_VAR'])\n")
      File.chmod(0o755, script)

      result = executor.run(
        command: 'ruby',
        args: [script],
        payload: {},
        env: { 'MY_HOOK_VAR' => 'secret-value' }
      )
      expect(result['extra']).to eq('secret-value')
    end
  end
end
