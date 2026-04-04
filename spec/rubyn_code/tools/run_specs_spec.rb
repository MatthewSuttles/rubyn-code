# frozen_string_literal: true

require 'spec_helper'

RSpec.describe RubynCode::Tools::RunSpecs do
  let(:success_status) { instance_double(Process::Status, success?: true, exitstatus: 0) }
  let(:failure_status) { instance_double(Process::Status, success?: false, exitstatus: 1) }

  def build_tool(dir)
    described_class.new(project_root: dir)
  end

  describe '#execute' do
    context 'framework detection' do
      context 'when Gemfile contains rspec' do
        it 'detects rspec from Gemfile' do
          with_temp_project do |dir|
            create_test_file(dir, 'Gemfile', "gem 'rspec'\n")
            tool = build_tool(dir)

            allow(tool).to receive(:safe_capture3).and_return(['5 examples, 0 failures', '', success_status])
            result = tool.execute

            expect(tool).to have_received(:safe_capture3)
              .with(a_string_matching(/bundle exec rspec/), chdir: dir)
          end
        end

        it 'detects rspec-rails from Gemfile' do
          with_temp_project do |dir|
            create_test_file(dir, 'Gemfile', "gem 'rspec-rails'\n")
            tool = build_tool(dir)

            allow(tool).to receive(:safe_capture3).and_return(['5 examples', '', success_status])
            tool.execute

            expect(tool).to have_received(:safe_capture3)
              .with(a_string_matching(/bundle exec rspec/), chdir: dir)
          end
        end
      end

      context 'when Gemfile contains minitest' do
        it 'detects minitest from Gemfile' do
          with_temp_project do |dir|
            create_test_file(dir, 'Gemfile', "gem 'minitest'\n")
            tool = build_tool(dir)

            allow(tool).to receive(:safe_capture3).and_return(['0 failures', '', success_status])
            tool.execute

            expect(tool).to have_received(:safe_capture3)
              .with('bundle exec rails test', chdir: dir)
          end
        end
      end

      context 'when .rspec file exists' do
        it 'detects rspec from .rspec file' do
          with_temp_project do |dir|
            create_test_file(dir, '.rspec', '--format documentation')
            tool = build_tool(dir)

            allow(tool).to receive(:safe_capture3).and_return(['pass', '', success_status])
            tool.execute

            expect(tool).to have_received(:safe_capture3)
              .with(a_string_matching(/bundle exec rspec/), chdir: dir)
          end
        end
      end

      context 'when spec directory exists' do
        it 'detects rspec from spec directory' do
          with_temp_project do |dir|
            FileUtils.mkdir_p(File.join(dir, 'spec'))
            tool = build_tool(dir)

            allow(tool).to receive(:safe_capture3).and_return(['pass', '', success_status])
            tool.execute

            expect(tool).to have_received(:safe_capture3)
              .with(a_string_matching(/bundle exec rspec/), chdir: dir)
          end
        end
      end

      context 'when test directory exists' do
        it 'detects minitest from test directory' do
          with_temp_project do |dir|
            FileUtils.mkdir_p(File.join(dir, 'test'))
            tool = build_tool(dir)

            allow(tool).to receive(:safe_capture3).and_return(['pass', '', success_status])
            tool.execute

            expect(tool).to have_received(:safe_capture3)
              .with('bundle exec rails test', chdir: dir)
          end
        end
      end

      context 'when no framework is detected' do
        it 'raises an error' do
          with_temp_project do |dir|
            tool = build_tool(dir)

            expect { tool.execute }
              .to raise_error(RubynCode::Error, /Could not detect test framework/)
          end
        end
      end
    end

    context 'rspec command building' do
      it 'includes format option' do
        with_temp_project do |dir|
          create_test_file(dir, 'Gemfile', "gem 'rspec'\n")
          tool = build_tool(dir)

          allow(tool).to receive(:safe_capture3).and_return(['output', '', success_status])
          tool.execute(format: 'progress')

          expect(tool).to have_received(:safe_capture3)
            .with('bundle exec rspec --format progress', chdir: dir)
        end
      end

      it 'uses documentation format by default' do
        with_temp_project do |dir|
          create_test_file(dir, 'Gemfile', "gem 'rspec'\n")
          tool = build_tool(dir)

          allow(tool).to receive(:safe_capture3).and_return(['output', '', success_status])
          tool.execute

          expect(tool).to have_received(:safe_capture3)
            .with('bundle exec rspec --format documentation', chdir: dir)
        end
      end

      it 'includes fail-fast option' do
        with_temp_project do |dir|
          create_test_file(dir, 'Gemfile', "gem 'rspec'\n")
          tool = build_tool(dir)

          allow(tool).to receive(:safe_capture3).and_return(['output', '', success_status])
          tool.execute(fail_fast: true)

          expect(tool).to have_received(:safe_capture3)
            .with('bundle exec rspec --format documentation --fail-fast', chdir: dir)
        end
      end

      it 'includes specific path' do
        with_temp_project do |dir|
          create_test_file(dir, 'Gemfile', "gem 'rspec'\n")
          tool = build_tool(dir)

          allow(tool).to receive(:safe_capture3).and_return(['output', '', success_status])
          tool.execute(path: 'spec/models/user_spec.rb')

          expect(tool).to have_received(:safe_capture3)
            .with('bundle exec rspec --format documentation spec/models/user_spec.rb', chdir: dir)
        end
      end

      it 'combines all options' do
        with_temp_project do |dir|
          create_test_file(dir, 'Gemfile', "gem 'rspec'\n")
          tool = build_tool(dir)

          allow(tool).to receive(:safe_capture3).and_return(['output', '', success_status])
          tool.execute(path: 'spec/foo_spec.rb', format: 'json', fail_fast: true)

          expect(tool).to have_received(:safe_capture3)
            .with('bundle exec rspec --format json --fail-fast spec/foo_spec.rb', chdir: dir)
        end
      end
    end

    context 'minitest command building' do
      it 'runs specific path with ruby -Itest' do
        with_temp_project do |dir|
          create_test_file(dir, 'Gemfile', "gem 'minitest'\n")
          tool = build_tool(dir)

          allow(tool).to receive(:safe_capture3).and_return(['output', '', success_status])
          tool.execute(path: 'test/models/user_test.rb')

          expect(tool).to have_received(:safe_capture3)
            .with('bundle exec ruby -Itest test/models/user_test.rb', chdir: dir)
        end
      end

      it 'runs all tests without path' do
        with_temp_project do |dir|
          create_test_file(dir, 'Gemfile', "gem 'minitest'\n")
          tool = build_tool(dir)

          allow(tool).to receive(:safe_capture3).and_return(['output', '', success_status])
          tool.execute

          expect(tool).to have_received(:safe_capture3)
            .with('bundle exec rails test', chdir: dir)
        end
      end
    end

    context 'output building' do
      it 'returns stdout on success' do
        with_temp_project do |dir|
          create_test_file(dir, 'Gemfile', "gem 'rspec'\n")
          tool = build_tool(dir)

          allow(tool).to receive(:safe_capture3)
            .and_return(["5 examples, 0 failures\n", '', success_status])

          result = tool.execute
          expect(result).to include('5 examples, 0 failures')
        end
      end

      it 'includes stderr when present' do
        with_temp_project do |dir|
          create_test_file(dir, 'Gemfile', "gem 'rspec'\n")
          tool = build_tool(dir)

          allow(tool).to receive(:safe_capture3)
            .and_return(['output', 'warning: deprecation', success_status])

          result = tool.execute
          expect(result).to include('STDERR:')
          expect(result).to include('warning: deprecation')
        end
      end

      it 'includes exit code on failure' do
        with_temp_project do |dir|
          create_test_file(dir, 'Gemfile', "gem 'rspec'\n")
          tool = build_tool(dir)

          allow(tool).to receive(:safe_capture3)
            .and_return(["3 examples, 1 failure\n", '', failure_status])

          result = tool.execute
          expect(result).to include('Exit code: 1')
          expect(result).to include('3 examples, 1 failure')
        end
      end

      it 'returns (no output) when both stdout and stderr are empty on success' do
        with_temp_project do |dir|
          create_test_file(dir, 'Gemfile', "gem 'rspec'\n")
          tool = build_tool(dir)

          allow(tool).to receive(:safe_capture3)
            .and_return(['', '', success_status])

          result = tool.execute
          expect(result).to eq('(no output)')
        end
      end
    end
  end

  describe '.tool_name' do
    it 'returns run_specs' do
      expect(described_class.tool_name).to eq('run_specs')
    end
  end

  describe '.risk_level' do
    it 'is execute' do
      expect(described_class.risk_level).to eq(:execute)
    end
  end

  describe '.requires_confirmation?' do
    it 'is false' do
      expect(described_class.requires_confirmation?).to be false
    end
  end
end
