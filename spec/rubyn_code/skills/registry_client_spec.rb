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
      {
        packs: [
          { name: 'rails-testing', description: 'Rails testing', version: '1.0.0' },
          { name: 'factory-bot', description: 'Factory Bot patterns', version: '1.0.0' }
        ]
      }.to_json
    end

    it 'fetches and returns pack list' do
      response = instance_double(Faraday::Response, body: response_body, status: 200, headers: { 'etag' => '"abc"' })
      allow(connection).to receive(:get).with('/api/v1/skills/packs').and_return(response)

      packs = client.list_packs
      expect(packs).to be_an(Array)
      expect(packs.size).to eq(2)
      expect(packs.first[:name]).to eq('rails-testing')
    end

    it 'raises RegistryError on network failure' do
      allow(connection).to receive(:get).and_raise(Faraday::ConnectionFailed, 'refused')

      expect { client.list_packs }.to raise_error(
        RubynCode::Skills::RegistryError, /Failed to fetch skill catalog/
      )
    end
  end

  describe '#search_packs' do
    let(:response_body) do
      {
        packs: [
          { name: 'rails-testing', description: 'Rails testing', tags: ['testing'] },
          { name: 'factory-bot', description: 'Factory Bot patterns', tags: ['factories'] }
        ]
      }.to_json
    end

    it 'filters packs by query locally' do
      response = instance_double(Faraday::Response, body: response_body, status: 200, headers: { 'etag' => '"abc"' })
      allow(connection).to receive(:get).with('/api/v1/skills/packs').and_return(response)

      results = client.search_packs('rails')
      expect(results[:data].size).to eq(1)
      expect(results[:data].first[:name]).to eq('rails-testing')
    end

    it 'searches in description' do
      response = instance_double(Faraday::Response, body: response_body, status: 200, headers: { 'etag' => '"abc"' })
      allow(connection).to receive(:get).with('/api/v1/skills/packs').and_return(response)

      results = client.search_packs('patterns')
      expect(results[:data].size).to eq(1)
      expect(results[:data].first[:name]).to eq('factory-bot')
    end

    it 'raises RegistryError on failure' do
      allow(connection).to receive(:get).and_raise(Faraday::TimeoutError, 'timeout')

      expect { client.search_packs('rails') }.to raise_error(
        RubynCode::Skills::RegistryError, /Failed to fetch skill catalog/
      )
    end
  end

  describe '#fetch_pack' do
    let(:response_body) do
      {
        name: 'rails-testing',
        version: '1.0.0',
        files: [
          { path: 'rspec.md', title: 'RSpec', size: 1234 }
        ]
      }.to_json
    end

    let(:file_response_body) { '# RSpec Content' }

    it 'fetches pack content and file contents by name' do
      pack_response = instance_double(
        Faraday::Response,
        body: response_body, status: 200, headers: { 'etag' => '"abc"' }
      )
      file_response = instance_double(
        Faraday::Response,
        body: file_response_body, status: 200, headers: {}, success?: true
      )

      allow(connection).to receive(:get)
        .with('/api/v1/skills/packs/rails-testing').and_return(pack_response)
      allow(connection).to receive(:get)
        .with('/api/v1/skills/packs/rails-testing/files/rspec.md')
        .and_return(file_response)

      result = client.fetch_pack('rails-testing')
      expect(result[:data][:name]).to eq('rails-testing')
      expect(result[:data][:files]).to be_an(Array)
      expect(result[:data][:files].first[:filename]).to eq('rspec.md')
      expect(result[:data][:files].first[:content]).to eq('# RSpec Content')
      expect(result[:etag]).to eq('"abc"')
    end

    it 'handles pack with no files' do
      pack_response = instance_double(
        Faraday::Response,
        body: { name: 'empty-pack', version: '1.0.0', files: [] }.to_json,
        status: 200, headers: { 'etag' => '"def"' }
      )
      allow(connection).to receive(:get)
        .with('/api/v1/skills/packs/empty-pack').and_return(pack_response)

      result = client.fetch_pack('empty-pack')
      expect(result[:data][:name]).to eq('empty-pack')
      expect(result[:data][:files]).to eq([])
    end

    it 'raises RegistryError on failure' do
      allow(connection).to receive(:get).and_raise(Faraday::ResourceNotFound, '404')

      expect { client.fetch_pack('nonexistent') }.to raise_error(
        RubynCode::Skills::RegistryError, /Failed to fetch pack/
      )
    end

    it 'raises RegistryError on invalid JSON' do
      response = instance_double(Faraday::Response, body: 'not json', status: 200, headers: {})
      allow(connection).to receive(:get).with('/api/v1/skills/packs/bad').and_return(response)

      expect { client.fetch_pack('bad') }.to raise_error(
        RubynCode::Skills::RegistryError, /Invalid response/
      )
    end
  end

  describe 'User-Accept header' do
    it 'sets Accept header on connection for catalog requests' do
      stub_request(:get, %r{test\.rubyn\.ai/api/v1/skills/packs})
        .with(headers: { 'User-Accept' => 'Rubyn Code' })
        .to_return(status: 200, body: '{"packs":[]}', headers: { 'etag' => '"x"' })

      result = client.fetch_catalog

      expect(result[:data]).to eq([])
    end

    it 'sets Accept header on connection for pack fetch' do
      stub_request(:get, %r{test\.rubyn\.ai/api/v1/skills/packs/stripe})
        .with(headers: { 'User-Accept' => 'Rubyn Code' })
        .to_return(status: 200, body: '{"name":"stripe"}', headers: { 'etag' => '"x"' })

      result = client.fetch_pack('stripe')

      expect(result[:name]).to eq('stripe')
    end
  end

  describe '406 response handling' do
    it 'raises RegistryError when server returns 406' do
      stub_request(:get, %r{test\.rubyn\.ai/api/v1/skills/packs})
        .to_return(status: 406, body: 'Not Acceptable', headers: {})

      expect { client.list_packs }.to raise_error(RubynCode::Skills::RegistryError)
    end

    it 'raises RegistryError on 406 for pack fetch' do
      stub_request(:get, %r{test\.rubyn\.ai/api/v1/skills/packs/rails-testing})
        .to_return(status: 406, body: 'Not Acceptable', headers: {})

      expect { client.fetch_pack('rails-testing') }.to raise_error(RubynCode::Skills::RegistryError)
    end
  end

  describe 'ETag caching' do
    it 'sends If-None-Match header when etag is provided' do
      stub_request(:get, %r{test\.rubyn\.ai/api/v1/skills/packs})
        .with(headers: { 'If-None-Match' => '"cached-etag"' })
        .to_return(status: 304, body: '', headers: { 'etag' => '"cached-etag"' })

      result = client.fetch_catalog(etag: '"cached-etag"')

      expect(result[:not_modified]).to be true
    end

    it 'does not send If-None-Match when no etag provided' do
      stub_request(:get, %r{test\.rubyn\.ai/api/v1/skills/packs})
        .to_return(status: 200, body: '{"packs":[]}', headers: { 'etag' => '"new"' })

      client.fetch_catalog(etag: nil)

      expect(WebMock).to have_requested(:get, %r{test\.rubyn\.ai/api/v1/skills/packs})
        .with(headers: { 'If-None-Match' => absent })
    end
  end

  describe '#fetch_suggestions' do
    it 'returns suggested packs based on detected gems' do
      stub_request(:get, %r{test\.rubyn\.ai/api/v1/skills/suggestions})
        .with(query: { gems: 'stripe,sidekiq' })
        .to_return(status: 200, body: [
          { 'name' => 'stripe', 'reason' => 'stripe gem detected' },
          { 'name' => 'sidekiq', 'reason' => 'sidekiq gem detected' }
        ].to_json, headers: { 'Content-Type' => 'application/json' })

      result = client.fetch_suggestions(['stripe', 'sidekiq'])

      expect(result.size).to eq(2)
      expect(result.first['name']).to eq('stripe')
    end

    it 'returns empty array when no matching suggestions' do
      stub_request(:get, %r{test\.rubyn\.ai/api/v1/skills/suggestions})
        .with(query: { gems: 'unknown-gem' })
        .to_return(status: 200, body: [].to_json, headers: { 'Content-Type' => 'application/json' })

      result = client.fetch_suggestions(['unknown-gem'])

      expect(result).to eq([])
    end

    it 'raises RegistryError on network failure' do
      stub_request(:get, %r{test\.rubyn\.ai/api/v1/skills/suggestions})
        .to_raise(Faraday::ConnectionFailed.new('Connection refused'))

      expect { client.fetch_suggestions(['stripe']) }.to raise_error(RubynCode::Skills::RegistryError)
    end
  end
end
