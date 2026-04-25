# frozen_string_literal: true

require 'webmock/rspec' unless defined?(WebMock)

RSpec.describe RubynCode::Skills::RegistryClient do
  let(:base_url) { 'https://rubyn.ai' }

  subject(:client) { described_class.new(base_url: base_url) }

  before do
    WebMock.enable! if defined?(WebMock)
  end

  after do
    WebMock.disable! if defined?(WebMock)
  end

  describe '#list_packs' do
    it 'returns an array of pack metadata' do
      stub_request(:get, "#{base_url}/api/skills")
        .to_return(
          status: 200,
          body: [{ name: 'rails-testing', description: 'Testing patterns', version: '1.0.0' }].to_json,
          headers: { 'Content-Type' => 'application/json' }
        )

      result = client.list_packs
      expect(result).to be_an(Array)
      expect(result.first[:name]).to eq('rails-testing')
    end

    it 'raises RegistryError on network failure' do
      stub_request(:get, "#{base_url}/api/skills").to_timeout

      expect { client.list_packs }.to raise_error(RubynCode::Skills::RegistryError, /Failed to fetch/)
    end

    it 'raises RegistryError on invalid JSON' do
      stub_request(:get, "#{base_url}/api/skills")
        .to_return(status: 200, body: 'not json')

      expect { client.list_packs }.to raise_error(RubynCode::Skills::RegistryError, /Invalid response/)
    end
  end

  describe '#search_packs' do
    it 'passes query parameter' do
      stub_request(:get, "#{base_url}/api/skills")
        .with(query: { q: 'rails' })
        .to_return(
          status: 200,
          body: [{ name: 'rails-testing' }].to_json,
          headers: { 'Content-Type' => 'application/json' }
        )

      result = client.search_packs('rails')
      expect(result.first[:name]).to eq('rails-testing')
    end

    it 'raises RegistryError on failure' do
      stub_request(:get, "#{base_url}/api/skills")
        .with(query: { q: 'broken' })
        .to_return(status: 500)

      expect { client.search_packs('broken') }.to raise_error(RubynCode::Skills::RegistryError)
    end
  end

  describe '#fetch_pack' do
    it 'returns pack data with files' do
      pack_data = {
        name: 'rails-testing',
        description: 'Testing patterns',
        version: '1.0.0',
        files: [{ filename: 'factory_bot.md', content: '# Factory Bot' }]
      }

      stub_request(:get, "#{base_url}/api/skills/rails-testing")
        .to_return(
          status: 200,
          body: pack_data.to_json,
          headers: { 'Content-Type' => 'application/json' }
        )

      result = client.fetch_pack('rails-testing')
      expect(result[:name]).to eq('rails-testing')
      expect(result[:files]).to be_an(Array)
      expect(result[:files].first[:filename]).to eq('factory_bot.md')
    end

    it 'raises RegistryError on 404' do
      stub_request(:get, "#{base_url}/api/skills/nonexistent")
        .to_return(status: 404)

      expect { client.fetch_pack('nonexistent') }.to raise_error(RubynCode::Skills::RegistryError)
    end
  end

  describe '#base_url' do
    it 'uses RUBYN_REGISTRY_URL env var when set' do
      allow(ENV).to receive(:fetch).with('RUBYN_REGISTRY_URL', 'https://rubyn.ai').and_return('https://custom.registry.dev')
      custom_client = described_class.new
      expect(custom_client.base_url).to eq('https://custom.registry.dev')
    end

    it 'defaults to https://rubyn.ai' do
      default_client = described_class.new
      expect(default_client.base_url).to start_with('https://rubyn.')
    end
  end
end
