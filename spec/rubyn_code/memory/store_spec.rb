# frozen_string_literal: true

require "spec_helper"

RSpec.describe RubynCode::Memory::Store do
  let(:db) { setup_test_db }
  let(:store) { described_class.new(db, project_path: "/test/project") }

  describe "#write" do
    it "creates a memory record with default tier" do
      record = store.write(content: "Use frozen_string_literal", category: "code_pattern")
      expect(record.content).to eq("Use frozen_string_literal")
      expect(record.tier).to eq("medium")
      expect(record.relevance_score).to eq(1.0)
    end

    it "rejects invalid tier" do
      expect { store.write(content: "x", tier: "invalid") }.to raise_error(ArgumentError)
    end

    it "rejects invalid category" do
      expect { store.write(content: "x", category: "bogus") }.to raise_error(ArgumentError)
    end
  end

  describe "#update" do
    it "updates content and syncs FTS" do
      record = store.write(content: "old", category: "decision")
      store.update(record.id, content: "new")
      # Verify via search that FTS is updated
      search = RubynCode::Memory::Search.new(db, project_path: "/test/project")
      results = search.search("new")
      expect(results.map(&:id)).to include(record.id)
    end
  end

  describe "#delete" do
    it "removes the memory" do
      record = store.write(content: "temporary")
      store.delete(record.id)
      search = RubynCode::Memory::Search.new(db, project_path: "/test/project")
      expect(search.recent(limit: 100).map(&:id)).not_to include(record.id)
    end
  end

  describe "#expire_old!" do
    it "deletes memories past their expiration" do
      store.write(content: "expired", expires_at: "2020-01-01 00:00:00")
      count = store.expire_old!
      expect(count).to eq(1)
    end

    it "returns 0 when nothing expired" do
      store.write(content: "fresh")
      expect(store.expire_old!).to eq(0)
    end
  end
end
