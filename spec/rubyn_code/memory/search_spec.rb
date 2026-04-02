# frozen_string_literal: true

require "spec_helper"

RSpec.describe RubynCode::Memory::Search do
  let(:db) { setup_test_db }
  let(:store) { RubynCode::Memory::Store.new(db, project_path: "/proj") }
  let(:search) { described_class.new(db, project_path: "/proj") }

  before do
    store.write(content: "Rails migration patterns", tier: "long", category: "code_pattern")
    store.write(content: "Prefer RSpec over Minitest", tier: "short", category: "user_preference")
    store.write(content: "Error handling with rescue", tier: "medium", category: "error_resolution")
  end

  describe "#search" do
    it "finds memories matching a query" do
      results = search.search("Rails migration")
      expect(results.size).to be >= 1
      expect(results.first.content).to include("Rails")
    end
  end

  describe "#recent" do
    it "returns memories ordered by creation time" do
      results = search.recent(limit: 10)
      expect(results.size).to eq(3)
    end
  end

  describe "#by_category" do
    it "filters by category" do
      results = search.by_category("user_preference")
      expect(results.size).to eq(1)
      expect(results.first.content).to include("RSpec")
    end
  end

  describe "#by_tier" do
    it "filters by tier" do
      results = search.by_tier("long")
      expect(results.size).to eq(1)
      expect(results.first.content).to include("Rails")
    end

    it "returns empty for tier with no matches" do
      expect(search.by_tier("long", limit: 10).first.tier).to eq("long")
    end
  end
end
