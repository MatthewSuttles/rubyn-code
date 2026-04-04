# frozen_string_literal: true

require 'spec_helper'

RSpec.describe RubynCode::Tools::DbMigrate do
  let(:project_root) { Dir.mktmpdir('rubyn_test_') }
  let(:tool) { described_class.new(project_root: project_root) }
  let(:success_status) { instance_double(Process::Status, success?: true, exitstatus: 0) }
  let(:failure_status) { instance_double(Process::Status, success?: false, exitstatus: 1) }

  after { FileUtils.rm_rf(project_root) }

  describe '#execute' do
    it 'runs db:migrate and returns output' do
      allow(tool).to receive(:safe_capture3)
        .with('bundle exec rails db:migrate', chdir: project_root)
        .and_return(["== CreateUsers: migrating\n", '', success_status])

      result = tool.execute

      expect(result).to include('CreateUsers: migrating')
    end

    it 'defaults direction to up' do
      allow(tool).to receive(:safe_capture3)
        .with('bundle exec rails db:migrate', chdir: project_root)
        .and_return(['Migrated', '', success_status])

      result = tool.execute(direction: 'up')

      expect(result).to include('Migrated')
    end

    it 'runs db:rollback when direction is down' do
      allow(tool).to receive(:safe_capture3)
        .with('bundle exec rails db:rollback', chdir: project_root)
        .and_return(["== CreateUsers: reverting\n", '', success_status])

      result = tool.execute(direction: 'down')

      expect(result).to include('CreateUsers: reverting')
    end

    it 'includes STEP parameter when rolling back with steps' do
      allow(tool).to receive(:safe_capture3)
        .with('bundle exec rails db:rollback STEP=3', chdir: project_root)
        .and_return(["Rolled back 3 migrations\n", '', success_status])

      result = tool.execute(direction: 'down', steps: 3)

      expect(result).to include('Rolled back 3 migrations')
    end

    it 'omits STEP when steps is nil on rollback' do
      allow(tool).to receive(:safe_capture3)
        .with('bundle exec rails db:rollback', chdir: project_root)
        .and_return(['Rolled back', '', success_status])

      result = tool.execute(direction: 'down', steps: nil)

      expect(result).to include('Rolled back')
    end

    it 'omits STEP when steps is zero on rollback' do
      allow(tool).to receive(:safe_capture3)
        .with('bundle exec rails db:rollback', chdir: project_root)
        .and_return(['Rolled back', '', success_status])

      result = tool.execute(direction: 'down', steps: 0)

      expect(result).to include('Rolled back')
    end

    it 'raises an error for invalid direction' do
      expect { tool.execute(direction: 'sideways') }
        .to raise_error(RubynCode::Error, /Invalid direction: sideways/)
    end

    it 'returns error output on failure' do
      allow(tool).to receive(:safe_capture3)
        .with('bundle exec rails db:migrate', chdir: project_root)
        .and_return(['', 'ActiveRecord::StatementInvalid', failure_status])

      result = tool.execute

      expect(result).to include('STDERR:')
      expect(result).to include('ActiveRecord::StatementInvalid')
      expect(result).to include('Exit code: 1')
    end

    it 'returns (no output) when command produces no output' do
      allow(tool).to receive(:safe_capture3)
        .with('bundle exec rails db:migrate', chdir: project_root)
        .and_return(['', '', success_status])

      result = tool.execute

      expect(result).to eq('(no output)')
    end
  end

  describe '.tool_name' do
    it 'returns db_migrate' do
      expect(described_class.tool_name).to eq('db_migrate')
    end
  end
end
