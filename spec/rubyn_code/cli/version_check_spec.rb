# frozen_string_literal: true

require 'spec_helper'

RSpec.describe RubynCode::CLI::VersionCheck do
  subject(:version_check) { described_class.new(renderer: renderer) }

  let(:renderer) { instance_double(RubynCode::CLI::Renderer, warning: nil) }
  let(:cache_file) { described_class::CACHE_FILE }
  let(:api_url) { described_class::RUBYGEMS_API }

  before do
    allow(ENV).to receive(:[]).and_call_original
    allow(ENV).to receive(:[]).with('RUBYN_NO_UPDATE_CHECK').and_return(nil)
  end

  describe '#start' do
    context 'when RUBYN_NO_UPDATE_CHECK is set' do
      before do
        allow(ENV).to receive(:[]).with('RUBYN_NO_UPDATE_CHECK').and_return('1')
      end

      it 'does not spawn a thread' do
        version_check.start

        expect(version_check.instance_variable_get(:@thread)).to be_nil
      end
    end

    context 'when RUBYN_NO_UPDATE_CHECK is not set' do
      before do
        allow(File).to receive(:exist?).with(cache_file).and_return(false)
        stub_request(:get, api_url).to_return(
          status: 200,
          body: '{"version":"99.0.0"}',
          headers: { 'Content-Type' => 'application/json' }
        )
      end

      it 'spawns a background thread' do
        version_check.start
        thread = version_check.instance_variable_get(:@thread)

        expect(thread).to be_a(Thread)

        thread.join(2)
      end

      it 'sets abort_on_exception to false' do
        version_check.start
        thread = version_check.instance_variable_get(:@thread)
        thread.join(2)

        expect(thread.abort_on_exception).to be false
      end

      it 'calls check in the background thread' do
        allow(version_check).to receive(:send).with(:check).and_call_original

        version_check.start
        version_check.instance_variable_get(:@thread).join(2)

        expect(version_check.instance_variable_get(:@result)).to eq('99.0.0')
      end
    end
  end

  describe '#notify' do
    context 'when start was not called (thread is nil)' do
      it 'does nothing' do
        version_check.notify

        expect(renderer).not_to have_received(:warning)
      end
    end

    context 'when remote version is newer' do
      before do
        allow(File).to receive(:exist?).with(cache_file).and_return(false)
        stub_request(:get, api_url).to_return(
          status: 200,
          body: '{"version":"99.0.0"}',
          headers: { 'Content-Type' => 'application/json' }
        )
      end

      it 'shows a warning with the update message' do
        version_check.start
        version_check.notify(timeout: 2)

        expect(renderer).to have_received(:warning).with(
          "Update available: #{RubynCode::VERSION} -> 99.0.0  (gem install rubyn-code)"
        )
      end
    end

    context 'when remote version equals current version' do
      before do
        allow(File).to receive(:exist?).with(cache_file).and_return(false)
        stub_request(:get, api_url).to_return(
          status: 200,
          body: { version: RubynCode::VERSION }.to_json,
          headers: { 'Content-Type' => 'application/json' }
        )
      end

      it 'does not show a warning' do
        version_check.start
        version_check.notify(timeout: 2)

        expect(renderer).not_to have_received(:warning)
      end
    end

    context 'when remote version is older' do
      before do
        allow(File).to receive(:exist?).with(cache_file).and_return(false)
        stub_request(:get, api_url).to_return(
          status: 200,
          body: '{"version":"0.0.1"}',
          headers: { 'Content-Type' => 'application/json' }
        )
      end

      it 'does not show a warning' do
        version_check.start
        version_check.notify(timeout: 2)

        expect(renderer).not_to have_received(:warning)
      end
    end

    context 'when @result is nil (check failed)' do
      before do
        allow(File).to receive(:exist?).with(cache_file).and_return(false)
        stub_request(:get, api_url).to_return(status: 500)
      end

      it 'does not show a warning' do
        version_check.start
        version_check.notify(timeout: 2)

        expect(renderer).not_to have_received(:warning)
      end
    end
  end

  describe '#check (private)' do
    context 'when cache is fresh' do
      before do
        allow(File).to receive(:exist?).with(cache_file).and_return(true)
        allow(File).to receive(:mtime).with(cache_file).and_return(Time.now - 100)
        allow(File).to receive(:read).with(cache_file).and_return("2.0.0\n")
      end

      it 'uses cached version without hitting the API' do
        version_check.send(:check)

        expect(version_check.instance_variable_get(:@result)).to eq('2.0.0')
        expect(WebMock).not_to have_requested(:get, api_url)
      end
    end

    context 'when no cache exists' do
      before do
        allow(File).to receive(:exist?).with(cache_file).and_return(false)
      end

      it 'fetches from the RubyGems API' do
        stub_request(:get, api_url).to_return(
          status: 200,
          body: '{"version":"3.0.0"}',
          headers: { 'Content-Type' => 'application/json' }
        )

        version_check.send(:check)

        expect(version_check.instance_variable_get(:@result)).to eq('3.0.0')
        expect(WebMock).to have_requested(:get, api_url).once
      end
    end

    context 'after a successful API fetch' do
      before do
        allow(File).to receive(:exist?).with(cache_file).and_return(false)
        allow(File).to receive(:write)
        stub_request(:get, api_url).to_return(
          status: 200,
          body: '{"version":"3.0.0"}',
          headers: { 'Content-Type' => 'application/json' }
        )
      end

      it 'writes the version to the cache file' do
        version_check.send(:check)

        expect(File).to have_received(:write).with(cache_file, '3.0.0')
      end
    end

    context 'when API response is not successful' do
      before do
        allow(File).to receive(:exist?).with(cache_file).and_return(false)
        stub_request(:get, api_url).to_return(status: 503)
      end

      it 'sets no result' do
        version_check.send(:check)

        expect(version_check.instance_variable_get(:@result)).to be_nil
      end
    end

    context 'when JSON has no "version" key' do
      before do
        allow(File).to receive(:exist?).with(cache_file).and_return(false)
        stub_request(:get, api_url).to_return(
          status: 200,
          body: '{"name":"rubyn-code"}',
          headers: { 'Content-Type' => 'application/json' }
        )
      end

      it 'sets no result' do
        version_check.send(:check)

        expect(version_check.instance_variable_get(:@result)).to be_nil
      end
    end

    context 'when an error occurs during check' do
      before do
        allow(File).to receive(:exist?).with(cache_file).and_return(false)
        stub_request(:get, api_url).to_raise(Faraday::ConnectionFailed.new('connection refused'))
      end

      it 'silently rescues and sets no result' do
        expect { version_check.send(:check) }.not_to raise_error

        expect(version_check.instance_variable_get(:@result)).to be_nil
      end
    end
  end

  describe '#newer? (private)' do
    it 'returns true when remote is greater than local' do
      expect(version_check.send(:newer?, '2.0.0', '1.0.0')).to be true
    end

    it 'returns false when remote equals local' do
      expect(version_check.send(:newer?, '1.0.0', '1.0.0')).to be false
    end

    it 'returns false when remote is less than local' do
      expect(version_check.send(:newer?, '0.5.0', '1.0.0')).to be false
    end

    it 'handles multi-segment version comparisons' do
      expect(version_check.send(:newer?, '1.0.1', '1.0.0')).to be true
      expect(version_check.send(:newer?, '1.1.0', '1.0.9')).to be true
    end

    it 'returns false on invalid version strings' do
      expect(version_check.send(:newer?, 'not-a-version', '1.0.0')).to be false
    end
  end

  describe '#read_cache (private)' do
    context 'when cache file does not exist' do
      before do
        allow(File).to receive(:exist?).with(cache_file).and_return(false)
      end

      it 'returns nil' do
        expect(version_check.send(:read_cache)).to be_nil
      end
    end

    context 'when cache file is expired (older than 24 hours)' do
      before do
        allow(File).to receive(:exist?).with(cache_file).and_return(true)
        allow(File).to receive(:mtime).with(cache_file).and_return(Time.now - 86_401)
      end

      it 'returns nil' do
        expect(version_check.send(:read_cache)).to be_nil
      end
    end

    context 'when cache file is fresh' do
      before do
        allow(File).to receive(:exist?).with(cache_file).and_return(true)
        allow(File).to receive(:mtime).with(cache_file).and_return(Time.now - 3600)
        allow(File).to receive(:read).with(cache_file).and_return("1.5.0\n")
      end

      it 'returns the cached version string, stripped' do
        expect(version_check.send(:read_cache)).to eq('1.5.0')
      end
    end

    context 'when reading the file raises an error' do
      before do
        allow(File).to receive(:exist?).with(cache_file).and_return(true)
        allow(File).to receive(:mtime).with(cache_file).and_return(Time.now)
        allow(File).to receive(:read).with(cache_file).and_raise(Errno::EACCES)
      end

      it 'returns nil' do
        expect(version_check.send(:read_cache)).to be_nil
      end
    end
  end

  describe '#write_cache (private)' do
    it 'writes the version string to the cache file' do
      allow(File).to receive(:write)

      version_check.send(:write_cache, '4.0.0')

      expect(File).to have_received(:write).with(cache_file, '4.0.0')
    end

    context 'when writing raises an error' do
      before do
        allow(File).to receive(:write).and_raise(Errno::EACCES)
      end

      it 'silently rescues' do
        expect { version_check.send(:write_cache, '4.0.0') }.not_to raise_error
      end
    end
  end
end
