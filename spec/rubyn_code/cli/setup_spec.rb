# frozen_string_literal: true

require 'spec_helper'
require 'open3'
require 'rubyn_code/cli/setup'

RSpec.describe RubynCode::CLI::Setup do
  let(:tmpdir)        { Dir.mktmpdir('rubyn_setup_') }
  let(:launcher_path) { File.join(tmpdir, 'rubyn-code') }
  let(:gem_wrapper)   { File.join(tmpdir, 'fake-gem-wrapper') }
  let(:pinned_ruby)   { File.join(tmpdir, 'fake-ruby') }
  let(:setup)         { described_class.new }

  after { FileUtils.rm_rf(tmpdir) }

  describe '#write_launcher' do
    before { setup.send(:write_launcher, launcher_path, gem_wrapper, pinned_ruby) }

    it 'emits the exec line that runs the pinned Ruby with the gem wrapper' do
      expect(File.read(launcher_path))
        .to include(%(exec "#{pinned_ruby}" "#{gem_wrapper}" "$@"))
    end

    it 'guards the exec with an existence check on the pinned Ruby and wrapper' do
      content = File.read(launcher_path)
      expect(content).to include(%([ ! -x "#{pinned_ruby}" ]))
      expect(content).to include(%([ ! -f "#{gem_wrapper}" ]))
    end

    context 'when the pinned Ruby and gem wrapper are missing' do
      before { File.chmod(0o755, launcher_path) }

      it 'exits 127 with a recovery hint instead of bash\'s "No such file" error' do
        output, status = Open3.capture2e(launcher_path)

        expect(status.exitstatus).to eq(127)
        expect(output).to include('rubyn-code: launcher target missing')
        expect(output).to include("pinned Ruby: #{pinned_ruby}")
        expect(output).to include("gem wrapper: #{gem_wrapper}")
        expect(output).to include("rm '#{launcher_path}'")
        expect(output).to include('gem install rubyn-code')
        expect(output).to include('rubyn-code --setup')
      end
    end

    context 'when the pinned Ruby and gem wrapper exist' do
      before do
        File.write(pinned_ruby, "#!/bin/bash\necho \"ruby called with: $*\"\n")
        File.write(gem_wrapper, "# fake wrapper\n")
        File.chmod(0o755, pinned_ruby)
        File.chmod(0o755, launcher_path)
      end

      it 'execs the pinned Ruby with the gem wrapper as the first arg' do
        output, status = Open3.capture2e(launcher_path, 'hello', 'world')

        expect(status.exitstatus).to eq(0)
        expect(output).to include("ruby called with: #{gem_wrapper} hello world")
      end
    end
  end
end
