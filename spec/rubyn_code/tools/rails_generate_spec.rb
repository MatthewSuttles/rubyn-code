# frozen_string_literal: true

require 'spec_helper'

RSpec.describe RubynCode::Tools::RailsGenerate do
  let(:project_root) { Dir.mktmpdir('rubyn_test_') }
  let(:tool) { described_class.new(project_root: project_root) }
  let(:success_status) { instance_double(Process::Status, success?: true, exitstatus: 0) }
  let(:failure_status) { instance_double(Process::Status, success?: false, exitstatus: 1) }

  before do
    File.write(File.join(project_root, 'Gemfile'), "gem 'rails'\n")
  end

  after { FileUtils.rm_rf(project_root) }

  describe '#execute' do
    it 'runs rails generate with generator and args' do
      allow(tool).to receive(:safe_capture3)
        .with('bundle exec rails generate model User name:string email:string', chdir: project_root)
        .and_return(["create db/migrate/001_create_users.rb\n", '', success_status])

      result = tool.execute(generator: 'model', args: 'User name:string email:string')

      expect(result).to include('create db/migrate/001_create_users.rb')
    end

    it 'raises an error when no Gemfile exists' do
      FileUtils.rm_f(File.join(project_root, 'Gemfile'))

      expect { tool.execute(generator: 'model', args: 'User') }
        .to raise_error(RubynCode::Error, /No Gemfile found/)
    end

    it 'raises an error when Gemfile does not include rails' do
      File.write(File.join(project_root, 'Gemfile'), "gem 'sinatra'\n")

      expect { tool.execute(generator: 'model', args: 'User') }
        .to raise_error(RubynCode::Error, /does not include Rails/)
    end

    it 'returns error output on failure' do
      allow(tool).to receive(:safe_capture3)
        .with('bundle exec rails generate model BadModel', chdir: project_root)
        .and_return(['', 'Error: could not generate model', failure_status])

      result = tool.execute(generator: 'model', args: 'BadModel')

      expect(result).to include('STDERR:')
      expect(result).to include('Error: could not generate model')
      expect(result).to include('Exit code: 1')
    end

    it 'returns (no output) when command produces no output' do
      allow(tool).to receive(:safe_capture3)
        .with('bundle exec rails generate controller Empty', chdir: project_root)
        .and_return(['', '', success_status])

      result = tool.execute(generator: 'controller', args: 'Empty')

      expect(result).to eq('(no output)')
    end

    it 'runs migration generator correctly' do
      allow(tool).to receive(:safe_capture3)
        .with('bundle exec rails generate migration AddAgeToUsers age:integer', chdir: project_root)
        .and_return(["create db/migrate/002_add_age_to_users.rb\n", '', success_status])

      result = tool.execute(generator: 'migration', args: 'AddAgeToUsers age:integer')

      expect(result).to include('create db/migrate/002_add_age_to_users.rb')
    end
  end

  describe '.tool_name' do
    it 'returns rails_generate' do
      expect(described_class.tool_name).to eq('rails_generate')
    end
  end
end
