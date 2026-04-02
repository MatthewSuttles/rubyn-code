# frozen_string_literal: true

require "spec_helper"

RSpec.describe RubynCode::DB::Migrator do
  let(:db) { setup_test_db }
  subject(:migrator) { described_class.new(db) }

  before do
    migrator.migrate!
  end

  describe "#migrate!" do
    it "applies all migrations and returns empty for re-run" do
      # Migrations already applied in before block, re-running should be a no-op
      newly_applied = migrator.migrate!
      expect(newly_applied).to eq([])
    end
  end

  describe "#applied_versions" do
    it "returns a set of applied version numbers" do
      versions = migrator.applied_versions
      expect(versions).to be_a(Set)
      expect(versions).not_to be_empty
    end
  end

  describe "#pending_migrations" do
    it "returns empty when all migrations applied" do
      expect(migrator.pending_migrations).to be_empty
    end
  end

  describe "#current_version" do
    it "returns the highest applied version" do
      version = migrator.current_version
      expect(version).to be_a(Integer)
      expect(version).to be >= 0
    end
  end

  describe "#available_migrations" do
    it "returns migrations sorted by version" do
      migrations = migrator.available_migrations
      expect(migrations).not_to be_empty
      versions = migrations.map(&:first)
      expect(versions).to eq(versions.sort)
    end
  end
end
