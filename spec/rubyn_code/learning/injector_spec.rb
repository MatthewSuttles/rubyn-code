# frozen_string_literal: true

require "spec_helper"

RSpec.describe RubynCode::Learning::Injector do
  let(:db) { setup_test_db }
  let(:now) { Time.now.utc.strftime("%Y-%m-%d %H:%M:%S") }

  before do
    db.execute(<<~SQL)
      CREATE TABLE IF NOT EXISTS instincts (
        id TEXT PRIMARY KEY, project_path TEXT, pattern TEXT,
        context_tags TEXT, confidence REAL, decay_rate REAL,
        times_applied INTEGER, times_helpful INTEGER,
        created_at TEXT, updated_at TEXT
      )
    SQL
  end

  def insert_instinct(id:, confidence:, tags: "[]")
    db.execute(
      "INSERT INTO instincts VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?)",
      [id, "/proj", "Pattern #{id}", tags, confidence, 0.01, 0, 0, now, now]
    )
  end

  describe ".call" do
    it "injects relevant instincts above minimum confidence" do
      insert_instinct(id: "high", confidence: 0.8)
      insert_instinct(id: "low", confidence: 0.1)

      result = described_class.call(db: db, project_path: "/proj")
      expect(result).to include("Pattern high")
      expect(result).not_to include("Pattern low")
    end

    it "returns empty string when no instincts exist" do
      result = described_class.call(db: db, project_path: "/proj")
      expect(result).to eq("")
    end

    it "respects the max_instincts limit" do
      6.times { |i| insert_instinct(id: "i#{i}", confidence: 0.7) }

      result = described_class.call(db: db, project_path: "/proj", max_instincts: 3)
      # Count pattern lines
      lines = result.lines.select { |l| l.start_with?("- ") }
      expect(lines.size).to be <= 3
    end

    it "wraps output in instincts tags" do
      insert_instinct(id: "tagged", confidence: 0.7)
      result = described_class.call(db: db, project_path: "/proj")
      expect(result).to start_with("<instincts>")
      expect(result).to end_with("</instincts>")
    end
  end
end
