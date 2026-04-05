# frozen_string_literal: true

require 'spec_helper'

RSpec.describe RubynCode::Tools::BackgroundRun do
  let(:project_root) { '/tmp/test_project' }

  def build_tool(worker: nil)
    tool = described_class.new(project_root: project_root)
    tool.background_worker = worker if worker
    tool
  end

  describe '#execute' do
    context 'when no background_worker is available' do
      it 'returns an error message' do
        tool = build_tool

        result = tool.execute(command: 'rspec')

        expect(result).to include('Error')
        expect(result).to include('not available')
      end
    end

    context 'when background_worker is available' do
      let(:worker) do
        obj = Object.new
        def obj.run(_command, **_opts)
          'job-abc-123'
        end
        obj
      end

      it 'calls worker.run and returns job ID message' do
        tool = build_tool(worker: worker)

        result = tool.execute(command: 'rspec spec/')

        expect(result).to include('job-abc-123')
        expect(result).to include('Background job started')
        expect(result).to include('rspec spec/')
      end

      it 'includes timeout in output' do
        tool = build_tool(worker: worker)

        result = tool.execute(command: 'make build', timeout: 600)

        expect(result).to include('600s')
      end
    end

    context 'with custom timeout' do
      it 'passes timeout to worker' do
        received_timeout = nil
        worker = Object.new
        worker.define_singleton_method(:run) do |_command, timeout: 300|
          received_timeout = timeout
          'job-xyz'
        end

        tool = build_tool(worker: worker)
        tool.execute(command: 'bundle exec rspec', timeout: 120)

        expect(received_timeout).to eq(120)
      end
    end
  end

  describe '.tool_name' do
    it 'returns background_run' do
      expect(described_class.tool_name).to eq('background_run')
    end
  end
end
