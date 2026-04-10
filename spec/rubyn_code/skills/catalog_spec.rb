# frozen_string_literal: true

require 'tmpdir'
require 'fileutils'

RSpec.describe RubynCode::Skills::Catalog do
  let(:tmpdir) { Dir.mktmpdir }

  after { FileUtils.remove_entry(tmpdir) }

  before do
    File.write(File.join(tmpdir, 'deploy.md'), <<~MD)
      ---
      name: deploy
      description: Deploy the app
      tags: []
      ---
      Steps to deploy.
    MD

    File.write(File.join(tmpdir, 'review.md'), <<~MD)
      ---
      name: review
      description: Code review checklist
      tags: []
      ---
      Review steps.
    MD
  end

  subject(:catalog) { described_class.new(tmpdir) }

  describe '#descriptions' do
    it 'returns a formatted string with all skills' do
      desc = catalog.descriptions
      expect(desc).to include('deploy')
      expect(desc).to include('review')
    end
  end

  describe '#available' do
    it 'returns entries for each skill file' do
      expect(catalog.available.length).to eq(2)
    end
  end

  describe '#list' do
    it 'returns skill names as strings' do
      expect(catalog.list).to contain_exactly('deploy', 'review')
    end
  end

  describe '#find' do
    it 'returns the path for a known skill' do
      path = catalog.find('deploy')
      expect(path).to end_with('deploy.md')
    end

    it 'returns nil for an unknown skill' do
      expect(catalog.find('nonexistent')).to be_nil
    end
  end

  describe '#search' do
    before do
      FileUtils.mkdir_p(File.join(tmpdir, 'rails'))
      File.write(File.join(tmpdir, 'rails', 'service_objects.md'), <<~MD)
        ---
        name: service-objects
        description: Rails service object patterns
        tags:
          - rails
          - patterns
        ---
        Extract business logic into service objects.
      MD
    end

    it 'finds skills matching by name' do
      results = catalog.search('deploy')
      expect(results.map { |e| e[:name] }).to include('deploy')
    end

    it 'finds skills matching by description' do
      results = catalog.search('service object')
      expect(results.map { |e| e[:name] }).to include('service-objects')
    end

    it 'finds skills matching by tags' do
      results = catalog.search('patterns')
      expect(results.map { |e| e[:name] }).to include('service-objects')
    end

    it 'returns results sorted by relevance (higher first)' do
      results = catalog.search('deploy')
      # 'deploy' matches both name (3) and description (2) = 5
      # other entries should not match
      expect(results.first[:name]).to eq('deploy')
      expect(results.first[:relevance]).to be > 0
    end

    it 'returns empty array when nothing matches' do
      expect(catalog.search('zzzznonexistent')).to be_empty
    end

    it 'is case-insensitive' do
      results = catalog.search('DEPLOY')
      expect(results.map { |e| e[:name] }).to include('deploy')
    end
  end

  describe '#by_category' do
    before do
      FileUtils.mkdir_p(File.join(tmpdir, 'rails'))
      File.write(File.join(tmpdir, 'rails', 'migrations.md'), <<~MD)
        ---
        name: migrations
        description: Rails database migrations
        tags:
          - rails
        ---
        Migration content.
      MD
    end

    it 'returns skills in the specified category' do
      results = catalog.by_category('rails')
      names = results.map { |e| e[:name] }
      expect(names).to include('migrations')
      expect(names).not_to include('deploy', 'review')
    end

    it 'returns empty array for unknown category' do
      expect(catalog.by_category('nonexistent')).to be_empty
    end

    it 'is case-insensitive' do
      results = catalog.by_category('RAILS')
      expect(results.map { |e| e[:name] }).to include('migrations')
    end
  end

  describe '#categories' do
    before do
      FileUtils.mkdir_p(File.join(tmpdir, 'rails'))
      FileUtils.mkdir_p(File.join(tmpdir, 'rspec'))
      File.write(File.join(tmpdir, 'rails', 'routes.md'), '# Routes')
      File.write(File.join(tmpdir, 'rspec', 'mocking.md'), '# Mocking')
    end

    it 'returns unique category names sorted' do
      expect(catalog.categories).to eq(%w[rails rspec])
    end

    it 'excludes top-level skills (no category)' do
      expect(catalog.categories).not_to include('')
    end
  end
end
