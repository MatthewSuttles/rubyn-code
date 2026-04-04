# frozen_string_literal: true

require 'spec_helper'

RSpec.describe RubynCode::Tools::BundleAdd do
  let(:project_root) { Dir.mktmpdir('rubyn_test_') }
  let(:tool) { described_class.new(project_root: project_root) }
  let(:success_status) { instance_double(Process::Status, success?: true, exitstatus: 0) }
  let(:failure_status) { instance_double(Process::Status, success?: false, exitstatus: 1) }

  before do
    File.write(File.join(project_root, 'Gemfile'), "source 'https://rubygems.org'\n")
  end

  after { FileUtils.rm_rf(project_root) }

  describe '#execute' do
    it 'runs bundle add with the gem name and returns output' do
      allow(tool).to receive(:safe_capture3)
        .with('bundle add rspec', chdir: project_root)
        .and_return(['Fetching gem metadata...', '', success_status])

      result = tool.execute(gem_name: 'rspec')

      expect(result).to include('Fetching gem metadata...')
    end

    it 'includes --version flag when version is given' do
      allow(tool).to receive(:safe_capture3)
        .with("bundle add rspec --version '~> 3.0'", chdir: project_root)
        .and_return(['Added rspec', '', success_status])

      result = tool.execute(gem_name: 'rspec', version: '~> 3.0')

      expect(result).to include('Added rspec')
    end

    it 'includes --group flag when group is given' do
      allow(tool).to receive(:safe_capture3)
        .with('bundle add rspec --group test', chdir: project_root)
        .and_return(['Added rspec to test group', '', success_status])

      result = tool.execute(gem_name: 'rspec', group: 'test')

      expect(result).to include('Added rspec to test group')
    end

    it 'includes both --version and --group flags when both are given' do
      allow(tool).to receive(:safe_capture3)
        .with("bundle add rspec --version '~> 3.0' --group test", chdir: project_root)
        .and_return(['Added rspec ~> 3.0 to test group', '', success_status])

      result = tool.execute(gem_name: 'rspec', version: '~> 3.0', group: 'test')

      expect(result).to include('Added rspec')
    end

    it 'raises an error when no Gemfile exists' do
      FileUtils.rm_f(File.join(project_root, 'Gemfile'))

      expect { tool.execute(gem_name: 'rspec') }
        .to raise_error(RubynCode::Error, /No Gemfile found/)
    end

    it 'returns error output on failure' do
      allow(tool).to receive(:safe_capture3)
        .with('bundle add nonexistent_gem', chdir: project_root)
        .and_return(['', 'Could not find gem', failure_status])

      result = tool.execute(gem_name: 'nonexistent_gem')

      expect(result).to include('STDERR:')
      expect(result).to include('Could not find gem')
      expect(result).to include('Exit code: 1')
    end

    it 'returns (no output) when command produces no output' do
      allow(tool).to receive(:safe_capture3)
        .with('bundle add quiet_gem', chdir: project_root)
        .and_return(['', '', success_status])

      result = tool.execute(gem_name: 'quiet_gem')

      expect(result).to eq('(no output)')
    end
  end

  describe '.tool_name' do
    it 'returns bundle_add' do
      expect(described_class.tool_name).to eq('bundle_add')
    end
  end
end
