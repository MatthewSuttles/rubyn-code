# frozen_string_literal: true

RSpec.describe RubynCode::Skills::RegistryClient do
  subject(:client) { described_class.new(base_url: 'https://test.rubyn.ai') }

  let(:connection) { instance_double(Faraday::Connection) }

  before do
    allow(Faraday).to receive(:new).and_return(connection)
  end

  describe '#initialize' do
    it 'uses default base URL' do
      default_client = described_class.new
      expect(default_client.base_url).to eq('https://rubyn.ai')
    end

    it 'accepts custom base URL' do
      expect(client.base_url).to eq('https://test.rubyn.ai')
    end

    it 'reads RUBYN_REGISTRY_URL from environment' do
      allow(ENV).to receive(:fetch).with('RUBYN_REGISTRY_URL', anything).and_return('https://custom.rubyn.ai')
      env_client = described_class.new
      expect(env_client.base_url).to eq('https://custom.rubyn.ai')
    end
  end

  describe '#list_packs' do
    let(:response_body) do
      [
        { name: 'rails-testing', description: 'Rails testing', version: '1.0.0' },
        { name: 'factory-bot', description: 'Factory Bot patterns', version: '1.0.0' }
      ].to_json
    end

    it 'fetches and returns pack list' do
      response = instance_double(Faraday::Response, body: response_body)
      allow(connection).to receive(:get).with('/api/skills').and_return(response)

      packs = client.list_packs
      expect(packs).to be_an(Array)
      expect(packs.size).to eq(2)
      expect(packs.first[:name]).to eq('rails-testing')
    end

    it 'raises RegistryError on network failure' do
      allow(connection).to receive(:get).and_raise(Faraday::ConnectionFailed, 'refused')

      expect { client.list_packs }.to raise_error(
        RubynCode::Skills::RegistryError, /Failed to fetch skill packs/
      )
    end
  end

  describe '#search_packs' do
    let(:response_body) do
      [{ name: 'rails-testing', description: 'Rails testing' }].to_json
    end

    it 'passes query parameter' do
      response = instance_double(Faraday::Response, body: response_body)
      allow(connection).to receive(:get).with('/api/skills', { q: 'rails' }).and_return(response)

      results = client.search_packs('rails')
      expect(results.first[:name]).to eq('rails-testing')
    end

    it 'raises RegistryError on failure' do
      allow(connection).to receive(:get).and_raise(Faraday::TimeoutError, 'timeout')

      expect { client.search_packs('rails') }.to raise_error(
        RubynCode::Skills::RegistryError, /Failed to search/
      )
    end
  end

  describe '#fetch_pack' do
    let(:response_body) do
      {
        name: 'rails-testing',
        version: '1.0.0',
        files: [{ filename: 'rspec.md', content: '# RSpec' }]
      }.to_json
    end

    it 'fetches pack content by name' do
      response = instance_double(Faraday::Response, body: response_body)
      allow(connection).to receive(:get).with('/api/skills/rails-testing').and_return(response)

      pack = client.fetch_pack('rails-testing')
      expect(pack[:name]).to eq('rails-testing')
      expect(pack[:files]).to be_an(Array)
    end

    it 'raises RegistryError on failure' do
      allow(connection).to receive(:get).and_raise(Faraday::ResourceNotFound, '404')

      expect { client.fetch_pack('nonexistent') }.to raise_error(
        RubynCode::Skills::RegistryError, /Failed to fetch pack/
      )
    end

    it 'raises RegistryError on invalid JSON' do
      response = instance_double(Faraday::Response, body: 'not json')
      allow(connection).to receive(:get).and_return(response)

      expect { client.fetch_pack('bad') }.to raise_error(
        RubynCode::Skills::RegistryError, /Invalid response/
      )
    end
  end
end
