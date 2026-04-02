# frozen_string_literal: true

require "spec_helper"

RSpec.describe RubynCode::DB::Connection do
  let(:tmpdir) { Dir.mktmpdir("rubyn_db_test_") }
  let(:db_path) { File.join(tmpdir, "test.db") }

  after do
    FileUtils.rm_rf(tmpdir)
  end

  describe ".new (instance)" do
    it "creates a working SQLite connection" do
      conn = described_class.new(db_path)
      conn.execute("CREATE TABLE test (id INTEGER PRIMARY KEY, val TEXT)")
      conn.execute("INSERT INTO test (val) VALUES (?)", ["hello"])
      rows = conn.query("SELECT val FROM test")
      expect(rows.first["val"]).to eq("hello")
      conn.close
    end

    it "enables WAL mode and foreign keys" do
      conn = described_class.new(db_path)
      journal = conn.query("PRAGMA journal_mode").first
      fk = conn.query("PRAGMA foreign_keys").first
      expect(journal.values).to include("wal")
      expect(fk.values).to include(1)
      conn.close
    end
  end

  describe "#transaction" do
    it "commits on success" do
      conn = described_class.new(db_path)
      conn.execute("CREATE TABLE t (v TEXT)")
      conn.transaction { conn.execute("INSERT INTO t (v) VALUES ('ok')") }
      expect(conn.query("SELECT v FROM t").size).to eq(1)
      conn.close
    end

    it "rolls back on error" do
      conn = described_class.new(db_path)
      conn.execute("CREATE TABLE t (v TEXT)")
      begin
        conn.transaction do
          conn.execute("INSERT INTO t (v) VALUES ('bad')")
          raise "boom"
        end
      rescue RuntimeError
        nil
      end
      expect(conn.query("SELECT v FROM t")).to be_empty
      conn.close
    end
  end
end
