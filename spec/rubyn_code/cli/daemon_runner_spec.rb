# frozen_string_literal: true

require 'spec_helper'

RSpec.describe RubynCode::CLI::DaemonRunner do
  let(:db) { setup_test_db }
  let(:llm_client) { instance_double(RubynCode::LLM::Client) }
  let(:renderer) { instance_double(RubynCode::CLI::Renderer) }

  let(:options) do
    {
      command: :daemon,
      daemon: {
        agent_name: 'test-daemon',
        role: 'test agent',
        max_runs: 1,
        max_cost: 1.0,
        idle_timeout: 0.05,
        poll_interval: 0.01
      }
    }
  end

  before do
    allow(RubynCode::CLI::Renderer).to receive(:new).and_return(renderer)
    allow(renderer).to receive(:info)
    allow(renderer).to receive(:success)
    allow(renderer).to receive(:error)

    # Stub infrastructure
    allow(RubynCode::Auth::TokenStore).to receive(:valid?).and_return(true)
    allow(RubynCode::LLM::Client).to receive(:new).and_return(llm_client)
    allow(RubynCode::DB::Connection).to receive(:instance).and_return(db)

    migrator = instance_double(RubynCode::DB::Migrator)
    allow(RubynCode::DB::Migrator).to receive(:new).and_return(migrator)
    allow(migrator).to receive(:migrate!)

    allow(Signal).to receive(:trap)
  end

  describe '#run' do
    it 'starts the daemon and displays the banner' do
      text_response = RubynCode::LLM::Response.new(
        id: 'msg_test',
        content: [RubynCode::LLM::TextBlock.new(text: 'Done')],
        stop_reason: 'end_turn',
        usage: RubynCode::LLM::Usage.new(input_tokens: 10, output_tokens: 5)
      )
      allow(llm_client).to receive(:chat).and_return(text_response)

      runner = described_class.new(options)

      # Create a task so the daemon has something to do
      task_manager = RubynCode::Tasks::Manager.new(db)
      task_manager.create(title: 'Test task', priority: 1)

      expect(renderer).to receive(:info).with(/GOLEM Daemon Starting/).at_least(:once)
      expect(renderer).to receive(:info).with(/GOLEM Daemon Stopped/).at_least(:once)

      runner.run
    end

    it 'exits when auth is not valid' do
      allow(RubynCode::Auth::TokenStore).to receive(:load_for_provider).and_return(nil)
      runner = described_class.new(options)

      expect(renderer).to receive(:error).with(/No valid authentication/)
      expect { runner.run }.to raise_error(SystemExit)
    end
  end
end
