# frozen_string_literal: true

require 'spec_helper'

RSpec.describe RubynCode::Tools::BundleInstall do
  let(:project_root) { Dir.mktmpdir('rubyn_test_') }
  let(:tool) { described_class.new(project_root: project_root) }
  let(:success_status) { instance_double(Process::Status, success?: true, exitstatus: 0) }
  let(:failure_status) { instance_double(Process::Status, success?: false, exitstatus: 1) }

  before do
    File.write(File.join(project_root, 'Gemfile'), "source 'https://rubygems.org'\n")
  end

  after { FileUtils.rm_rf(project_root) }

  describe '#execute' do
    it 'runs bundle install and returns output' do
      allow(tool).to receive(:safe_capture3)
        .with('bundle install', chdir: project_root)
        .and_return(["Bundle complete! 10 gems installed.\n", '', success_status])

      result = tool.execute

      expect(result).to include('Bundle complete!')
    end

    it 'raises an error when no Gemfile exists' do
      FileUtils.rm_f(File.join(project_root, 'Gemfile'))

      expect { tool.execute }
        .to raise_error(RubynCode::Error, /No Gemfile found/)
    end

    it 'returns error output on failure' do
      allow(tool).to receive(:safe_capture3)
        .with('bundle install', chdir: project_root)
        .and_return(['', 'Bundler could not find compatible versions', failure_status])

      result = tool.execute

      expect(result).to include('STDERR:')
      expect(result).to include('Bundler could not find compatible versions')
      expect(result).to include('Exit code: 1')
    end

    it 'returns (no output) when command produces no output' do
      allow(tool).to receive(:safe_capture3)
        .with('bundle install', chdir: project_root)
        .and_return(['', '', success_status])

      result = tool.execute

      expect(result).to eq('(no output)')
    end

    it 'includes both stdout and stderr when both are present' do
      allow(tool).to receive(:safe_capture3)
        .with('bundle install', chdir: project_root)
        .and_return(["Installing gems...\n", "Warning: something\n", success_status])

      result = tool.execute

      expect(result).to include('Installing gems...')
      expect(result).to include('STDERR:')
      expect(result).to include('Warning: something')
    end
  end

  describe '.tool_name' do
    it 'returns bundle_install' do
      expect(described_class.tool_name).to eq('bundle_install')
    end
  end
end
