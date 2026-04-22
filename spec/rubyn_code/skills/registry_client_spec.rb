# frozen_string_literal: true

require_relative 'skill_packs_spec_helper'

RSpec.describe RubynCode::Skills::RegistryClient do
  let(:base_url) { 'https://rubyn.ai/api/v1/skills' }
  # Faraday resolves paths with leading slash against the host root,
  # so GET '/packs' on base_url 'https://rubyn.ai/api/v1/skills'
  # actually requests 'https://rubyn.ai/packs'.
  let(:host) { 'https://rubyn.ai' }
  subject(:client) { described_class.new(base_url: base_url) }

  let(:catalog_json) do
    {
      'packs' => [
        {
          'name' => 'hotwire',
          'displayName' => 'Hotwire',
          'description' => 'Turbo and Stimulus patterns',
          'category' => 'frontend',
          'skillCount' => 14,
          'version' => '1.0.0'
        }
      ],
      'categories' => [{ 'id' => 'frontend', 'name' => 'Frontend', 'count' => 1 }],
      'totalPacks' => 1,
      'totalSkills' => 14
    }
  end

  let(:pack_json) do
    {
      'name' => 'stripe',
      'displayName' => 'Stripe',
      'description' => 'Payment processing patterns',
      'version' => '1.0.0',
      'files' => [
        { 'path' => 'webhooks.md', 'title' => 'Webhook handling', 'size' => 4200 },
        { 'path' => 'checkout_sessions.md', 'title' => 'Checkout Sessions', 'size' => 3800 }
      ]
    }
  end

  describe 'User-Accept header' do
    it 'sends User-Accept: Rubyn Code on all requests' do
      stub = stub_request(:get, "#{host}/packs")
        .with(headers: { 'User-Accept' => 'Rubyn Code' })
        .to_return(status: 200, body: catalog_json.to_json, headers: { 'Content-Type' => 'application/json' })

      client.fetch_catalog

      expect(stub).to have_been_requested
    end

    it 'includes the header on pack metadata requests' do
      stub = stub_request(:get, "#{host}/packs/stripe")
        .with(headers: { 'User-Accept' => 'Rubyn Code' })
        .to_return(status: 200, body: pack_json.to_json, headers: { 'Content-Type' => 'application/json' })

      client.fetch_pack('stripe')

      expect(stub).to have_been_requested
    end

    it 'includes the header on file download requests' do
      stub = stub_request(:get, "#{host}/packs/stripe/files/webhooks.md")
        .with(headers: { 'User-Accept' => 'Rubyn Code' })
        .to_return(status: 200, body: '# Webhooks', headers: { 'ETag' => '"abc123"' })

      client.fetch_file('stripe', 'webhooks.md')

      expect(stub).to have_been_requested
    end

    it 'includes the header on suggestion requests' do
      stub = stub_request(:get, "#{host}/packs/suggest")
        .with(
          query: { gems: 'stripe,sidekiq' },
          headers: { 'User-Accept' => 'Rubyn Code' }
        )
        .to_return(status: 200, body: { 'suggestions' => [] }.to_json)

      client.fetch_suggestions(%w[stripe sidekiq])

      expect(stub).to have_been_requested
    end
  end

  describe '403 without header' do
    it 'raises RegistryError when API returns 403' do
      stub_request(:get, "#{host}/packs")
        .to_return(status: 403, body: '{"error":"This API requires the User-Accept: Rubyn Code header."}')

      expect { client.fetch_catalog }.to raise_error(
        RubynCode::Skills::RegistryError, /403/
      )
    end
  end

  describe '#fetch_catalog' do
    before do
      stub_request(:get, "#{host}/packs")
        .with(headers: { 'User-Accept' => 'Rubyn Code' })
        .to_return(status: 200, body: catalog_json.to_json, headers: { 'Content-Type' => 'application/json' })
    end

    it 'returns the parsed catalog hash' do
      result = client.fetch_catalog

      expect(result['packs']).to be_an(Array)
      expect(result['packs'].first['name']).to eq('hotwire')
      expect(result['totalPacks']).to eq(1)
    end

    it 'raises RegistryError on invalid JSON' do
      stub_request(:get, "#{host}/packs")
        .with(headers: { 'User-Accept' => 'Rubyn Code' })
        .to_return(status: 200, body: 'not json at all')

      expect { client.fetch_catalog }.to raise_error(
        RubynCode::Skills::RegistryError, /Invalid JSON/
      )
    end

    it 'raises RegistryError on server error' do
      stub_request(:get, "#{host}/packs")
        .with(headers: { 'User-Accept' => 'Rubyn Code' })
        .to_return(status: 500, body: 'Internal Server Error')

      expect { client.fetch_catalog }.to raise_error(
        RubynCode::Skills::RegistryError, /500/
      )
    end
  end

  describe '#fetch_pack' do
    before do
      stub_request(:get, "#{host}/packs/stripe")
        .with(headers: { 'User-Accept' => 'Rubyn Code' })
        .to_return(status: 200, body: pack_json.to_json, headers: { 'Content-Type' => 'application/json' })
    end

    it 'returns the parsed pack metadata' do
      result = client.fetch_pack('stripe')

      expect(result['name']).to eq('stripe')
      expect(result['files']).to be_an(Array)
      expect(result['files'].size).to eq(2)
    end

    it 'URL-encodes pack names' do
      stub = stub_request(:get, "#{host}/packs/my%20pack")
        .with(headers: { 'User-Accept' => 'Rubyn Code' })
        .to_return(status: 200, body: pack_json.to_json)

      client.fetch_pack('my pack')

      expect(stub).to have_been_requested
    end

    it 'raises RegistryError for unknown pack (404)' do
      stub_request(:get, "#{host}/packs/nonexistent")
        .with(headers: { 'User-Accept' => 'Rubyn Code' })
        .to_return(status: 404, body: '{"error":"Pack not found"}')

      expect { client.fetch_pack('nonexistent') }.to raise_error(
        RubynCode::Skills::RegistryError, /404/
      )
    end
  end

  describe '#fetch_file' do
    it 'returns file content and ETag' do
      stub_request(:get, "#{host}/packs/stripe/files/webhooks.md")
        .with(headers: { 'User-Accept' => 'Rubyn Code' })
        .to_return(
          status: 200,
          body: '# Stripe Webhooks',
          headers: { 'ETag' => '"abc123"' }
        )

      result = client.fetch_file('stripe', 'webhooks.md')

      expect(result[:content]).to eq('# Stripe Webhooks')
      expect(result[:etag]).to eq('"abc123"')
      expect(result[:not_modified]).to be false
    end

    it 'sends If-None-Match when etag is provided' do
      stub = stub_request(:get, "#{host}/packs/stripe/files/webhooks.md")
        .with(headers: {
          'User-Accept' => 'Rubyn Code',
          'If-None-Match' => '"abc123"'
        })
        .to_return(status: 304, body: '')

      result = client.fetch_file('stripe', 'webhooks.md', etag: '"abc123"')

      expect(stub).to have_been_requested
      expect(result[:not_modified]).to be true
      expect(result[:content]).to be_nil
      expect(result[:etag]).to eq('"abc123"')
    end

    it 'returns new content when ETag has changed' do
      stub_request(:get, "#{host}/packs/stripe/files/webhooks.md")
        .with(headers: {
          'User-Accept' => 'Rubyn Code',
          'If-None-Match' => '"old_etag"'
        })
        .to_return(
          status: 200,
          body: '# Updated Webhooks',
          headers: { 'ETag' => '"new_etag"' }
        )

      result = client.fetch_file('stripe', 'webhooks.md', etag: '"old_etag"')

      expect(result[:not_modified]).to be false
      expect(result[:content]).to eq('# Updated Webhooks')
      expect(result[:etag]).to eq('"new_etag"')
    end

    it 'raises RegistryError on download failure' do
      stub_request(:get, "#{host}/packs/stripe/files/missing.md")
        .with(headers: { 'User-Accept' => 'Rubyn Code' })
        .to_return(status: 404, body: 'Not Found')

      expect { client.fetch_file('stripe', 'missing.md') }.to raise_error(
        RubynCode::Skills::RegistryError, /404/
      )
    end
  end

  describe '#fetch_suggestions' do
    it 'returns matching suggestions' do
      suggestions = [
        { 'name' => 'stripe', 'reason' => 'stripe gem detected in Gemfile' },
        { 'name' => 'sidekiq', 'reason' => 'sidekiq gem detected in Gemfile' }
      ]

      stub_request(:get, "#{host}/packs/suggest")
        .with(
          query: { gems: 'stripe,sidekiq' },
          headers: { 'User-Accept' => 'Rubyn Code' }
        )
        .to_return(status: 200, body: { 'suggestions' => suggestions }.to_json)

      result = client.fetch_suggestions(%w[stripe sidekiq])

      expect(result.size).to eq(2)
      expect(result.first['name']).to eq('stripe')
    end

    it 'returns empty array for empty gems list' do
      result = client.fetch_suggestions([])

      expect(result).to eq([])
    end

    it 'returns empty array when response has no suggestions key' do
      stub_request(:get, "#{host}/packs/suggest")
        .with(query: { gems: 'unknown' })
        .to_return(status: 200, body: {}.to_json)

      result = client.fetch_suggestions(['unknown'])

      expect(result).to eq([])
    end
  end

  describe '#available?' do
    it 'returns true when registry is reachable' do
      stub_request(:head, "#{host}/packs")
        .to_return(status: 200)

      expect(client.available?).to be true
    end

    it 'returns false when registry is unreachable' do
      stub_request(:head, "#{host}/packs")
        .to_timeout

      expect(client.available?).to be false
    end

    it 'returns false on connection error' do
      stub_request(:head, "#{host}/packs")
        .to_raise(Faraday::ConnectionFailed.new('Connection refused'))

      expect(client.available?).to be false
    end
  end

  describe 'timeout configuration' do
    it 'uses the specified timeout' do
      custom_client = described_class.new(base_url: base_url, timeout: 5)

      stub_request(:get, "#{host}/packs")
        .with(headers: { 'User-Accept' => 'Rubyn Code' })
        .to_return(status: 200, body: catalog_json.to_json)

      expect { custom_client.fetch_catalog }.not_to raise_error
    end
  end
end
