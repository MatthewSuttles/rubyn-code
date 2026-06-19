# frozen_string_literal: true

require 'spec_helper'
require 'tmpdir'

RSpec.describe RubynCode::Learning::Porter do
  let(:db) { setup_test_db_with_tables }

  around do |example|
    Dir.mktmpdir do |dir|
      @dir = dir
      example.run
    end
  end

  def file(name = 'learnings.json') = File.join(@dir, name)

  def insert_instinct(project:, pattern:, confidence: 0.8)
    db.execute(
      <<~SQL.tr("\n", ' ').strip,
        INSERT INTO instincts (id, project_path, pattern, context_tags, confidence,
          decay_rate, times_applied, times_helpful, created_at, updated_at)
        VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
      SQL
      [SecureRandom.uuid, project, pattern, '["ruby"]', confidence, 0.05, 3, 2,
       '2026-01-01T00:00:00Z', '2026-01-02T00:00:00Z']
    )
  end

  describe '.export and .import round-trip' do
    it 'exports instincts to JSON and imports them back' do
      insert_instinct(project: '/proj/a', pattern: 'prefer guard clauses')
      insert_instinct(project: '/proj/a', pattern: 'use Data.define for value objects')

      count = described_class.export(db: db, path: file)
      expect(count).to eq(2)

      payload = JSON.parse(File.read(file))
      expect(payload['version']).to eq(described_class::FORMAT_VERSION)
      expect(payload['instincts'].map { |i| i['pattern'] }).to include('prefer guard clauses')

      # Import into a fresh DB.
      fresh = setup_test_db_with_tables
      result = described_class.import(db: fresh, path: file)
      expect(result[:imported]).to eq(2)
      expect(fresh.query('SELECT COUNT(*) AS n FROM instincts').first['n']).to eq(2)
    end
  end

  describe '.import' do
    it 'skips duplicates by (project_path, pattern)' do
      insert_instinct(project: '/proj/a', pattern: 'dup pattern')
      described_class.export(db: db, path: file)

      result = described_class.import(db: db, path: file) # same DB → all dupes
      expect(result).to include(imported: 0, skipped: 1)
    end

    it 'remaps project_path when requested' do
      insert_instinct(project: '/old/machine/proj', pattern: 'remap me')
      described_class.export(db: db, path: file)

      fresh = setup_test_db_with_tables
      described_class.import(db: fresh, path: file, remap_project: '/new/here')

      row = fresh.query('SELECT project_path FROM instincts').first
      expect(row['project_path']).to eq('/new/here')
    end

    it 'raises a clear error for a missing file' do
      expect { described_class.import(db: db, path: file('nope.json')) }
        .to raise_error(described_class::Error, /not found/i)
    end

    it 'raises a clear error for invalid JSON' do
      File.write(file, 'not json{')
      expect { described_class.import(db: db, path: file) }
        .to raise_error(described_class::Error, /invalid json/i)
    end

    it 'rejects a file that is not a learnings export' do
      File.write(file, JSON.generate({ 'something' => 'else' }))
      expect { described_class.import(db: db, path: file) }
        .to raise_error(described_class::Error, /not a rubyn learnings file/i)
    end
  end

  describe '.stats' do
    it 'counts instincts and distinct projects' do
      insert_instinct(project: '/a', pattern: 'one')
      insert_instinct(project: '/b', pattern: 'two')
      expect(described_class.stats(db)).to eq(count: 2, projects: 2)
    end
  end
end
