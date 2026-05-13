# frozen_string_literal: true

RSpec.describe RubynCode::Skills::RegistryAutoload do
  let(:loader)         { instance_double(RubynCode::Skills::Loader, catalog: catalog) }
  let(:catalog)        { instance_double(RubynCode::Skills::Catalog, refresh!: nil) }
  let(:matcher)        { instance_double(RubynCode::Skills::Matcher) }
  let(:client)         { instance_double(RubynCode::Skills::RegistryClient) }
  let(:pack_manager)   { instance_double(RubynCode::Skills::PackManager) }
  let(:on_fetching)    { ->(_name) {} }

  subject(:service) do
    described_class.new(
      loader: loader, matcher: matcher,
      registry_client: client, pack_manager: pack_manager,
      on_fetching: on_fetching
    )
  end

  let(:hotwire_pack) do
    { name: 'hotwire', tags: %w[turbo stimulus hotwire frontend] }
  end
  let(:stripe_pack) do
    { name: 'stripe', tags: %w[payments billing] }
  end

  def stub_catalog(packs)
    allow(client).to receive(:fetch_catalog).and_return({ data: packs })
  end

  describe '#try' do
    it 'returns [] for an empty message without touching the network' do
      # client.fetch_catalog isn't stubbed; calling it would raise on a verifying double.
      expect(service.try('')).to eq([])
    end

    it 'returns [] when no pack name or tag is in the message' do
      stub_catalog([hotwire_pack, stripe_pack])
      allow(pack_manager).to receive(:installed?).and_return(false)
      expect(service.try('how do I write a unit test')).to eq([])
    end

    it 'returns [] when the matching pack is already installed' do
      stub_catalog([hotwire_pack])
      allow(pack_manager).to receive(:installed?).with('hotwire').and_return(true)
      expect(service.try('explain turbo drive')).to eq([])
    end

    it 'fetches, installs, refreshes, and re-matches when an uninstalled pack hits' do
      stub_catalog([hotwire_pack])
      allow(pack_manager).to receive(:installed?).with('hotwire').and_return(false)
      allow(client).to receive(:fetch_pack).with('hotwire').and_return(
        { data: { name: 'hotwire', skills: [] }, etag: '"abc"', not_modified: false }
      )
      allow(pack_manager).to receive(:install).with({ name: 'hotwire', skills: [] }, etag: '"abc"').and_return({})

      injected = [{ name: 'turbo-drive', path: '/x', triggers: ['turbo drive'] }]
      allow(matcher).to receive(:match).with('explain turbo drive').and_return(injected)

      result = service.try('explain turbo drive')

      expect(catalog).to have_received(:refresh!)
      expect(result).to eq(injected)
    end

    it 'matches packs by tag substring as well as by name' do
      stub_catalog([hotwire_pack])
      allow(pack_manager).to receive(:installed?).with('hotwire').and_return(false)
      allow(client).to receive(:fetch_pack).with('hotwire').and_return(
        { data: { name: 'hotwire' }, etag: nil, not_modified: false }
      )
      allow(pack_manager).to receive(:install).and_return({})
      allow(matcher).to receive(:match).and_return([])

      service.try('I need help with stimulus controllers')

      expect(client).to have_received(:fetch_pack).with('hotwire')
    end

    it 'does not re-fetch a pack that already failed this session' do
      stub_catalog([hotwire_pack])
      allow(pack_manager).to receive(:installed?).with('hotwire').and_return(false)
      allow(client).to receive(:fetch_pack).with('hotwire').and_raise(
        RubynCode::Skills::RegistryError, 'boom'
      )

      service.try('turbo drive')
      service.try('turbo drive again')

      expect(client).to have_received(:fetch_pack).once
    end

    it 'fires on_fetching before each fetch' do
      observed = []
      service_with_observer = described_class.new(
        loader: loader, matcher: matcher,
        registry_client: client, pack_manager: pack_manager,
        on_fetching: ->(name) { observed << name }
      )

      stub_catalog([hotwire_pack])
      allow(pack_manager).to receive(:installed?).and_return(false)
      allow(client).to receive(:fetch_pack).with('hotwire').and_return(
        { data: { name: 'hotwire' }, etag: nil, not_modified: false }
      )
      allow(pack_manager).to receive(:install).and_return({})
      allow(matcher).to receive(:match).and_return([])

      service_with_observer.try('turbo drive')

      expect(observed).to eq(['hotwire'])
    end

    it 'returns [] silently when the registry catalog fetch fails' do
      allow(client).to receive(:fetch_catalog).and_raise(
        RubynCode::Skills::RegistryError, 'offline'
      )

      expect(service.try('turbo drive')).to eq([])
    end

    it 'does not retry catalog fetch after the first failure in a session' do
      allow(client).to receive(:fetch_catalog).and_raise(
        RubynCode::Skills::RegistryError, 'offline'
      )

      service.try('turbo drive')
      service.try('stimulus')

      expect(client).to have_received(:fetch_catalog).once
    end

    it 'skips a pack whose fetch fails but continues with other matches' do
      stub_catalog([hotwire_pack, stripe_pack])
      allow(pack_manager).to receive(:installed?).and_return(false)
      allow(client).to receive(:fetch_pack).with('hotwire').and_raise(
        RubynCode::Skills::RegistryError, 'transient'
      )
      allow(client).to receive(:fetch_pack).with('stripe').and_return(
        { data: { name: 'stripe' }, etag: nil, not_modified: false }
      )
      allow(pack_manager).to receive(:install).and_return({})
      allow(matcher).to receive(:match).and_return([])

      service.try('I need turbo drive and stripe billing')

      expect(client).to have_received(:fetch_pack).with('hotwire')
      expect(client).to have_received(:fetch_pack).with('stripe')
      expect(pack_manager).to have_received(:install).with({ name: 'stripe' }, etag: nil)
    end
  end
end
