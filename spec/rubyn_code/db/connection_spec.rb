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

  describe '.execute' do
    it 'delegates to the singleton instance' do
      instance = described_class.new(db_path)
      allow(described_class).to receive(:instance).and_return(instance)

      instance.execute('CREATE TABLE delegate_test (v TEXT)')
      described_class.execute('INSERT INTO delegate_test (v) VALUES (?)', ['delegated'])

      rows = instance.query('SELECT v FROM delegate_test')
      expect(rows.first['v']).to eq('delegated')
      instance.close
    end
  end

  describe '.query' do
    it 'delegates to the singleton instance' do
      instance = described_class.new(db_path)
      allow(described_class).to receive(:instance).and_return(instance)

      instance.execute('CREATE TABLE query_test (v TEXT)')
      instance.execute('INSERT INTO query_test (v) VALUES (?)', ['found'])

      rows = described_class.query('SELECT v FROM query_test')
      expect(rows.first['v']).to eq('found')
      instance.close
    end
  end

  describe '.transaction' do
    it 'delegates to the singleton instance and wraps in BEGIN/COMMIT' do
      instance = described_class.new(db_path)
      allow(described_class).to receive(:instance).and_return(instance)

      instance.execute('CREATE TABLE txn_test (v TEXT)')
      result = described_class.transaction do
        instance.execute('INSERT INTO txn_test (v) VALUES (?)', ['wrapped'])
        'return_value'
      end

      expect(result).to eq('return_value')
      rows = instance.query('SELECT v FROM txn_test')
      expect(rows.first['v']).to eq('wrapped')
      instance.close
    end
  end

  describe '.reset!' do
    it 'closes the connection and nils the singleton instance' do
      instance = described_class.new(db_path)
      described_class.instance_variable_set(:@instance, instance)
      described_class.instance_variable_set(:@mutex, Mutex.new)

      expect(instance).to be_open
      described_class.reset!
      expect(instance).not_to be_open
      expect(described_class.instance_variable_get(:@instance)).to be_nil
    end
  end

  describe '#transaction with nested savepoints' do
    it 'commits nested transactions using savepoints' do
      conn = described_class.new(db_path)
      conn.execute('CREATE TABLE nested (v TEXT)')

      conn.transaction do
        conn.execute("INSERT INTO nested (v) VALUES ('outer')")
        conn.transaction do
          conn.execute("INSERT INTO nested (v) VALUES ('inner')")
        end
      end

      rows = conn.query('SELECT v FROM nested ORDER BY rowid')
      expect(rows.map { |r| r['v'] }).to eq(%w[outer inner])
      conn.close
    end

    it 'rolls back only the inner savepoint on inner error' do
      conn = described_class.new(db_path)
      conn.execute('CREATE TABLE nested_rb (v TEXT)')

      conn.transaction do
        conn.execute("INSERT INTO nested_rb (v) VALUES ('outer')")
        begin
          conn.transaction do
            conn.execute("INSERT INTO nested_rb (v) VALUES ('inner_bad')")
            raise 'inner boom'
          end
        rescue RuntimeError
          nil
        end
      end

      rows = conn.query('SELECT v FROM nested_rb')
      expect(rows.map { |r| r['v'] }).to eq(['outer'])
      conn.close
    end
  end

  describe '#open?' do
    it 'returns true when the connection is open' do
      conn = described_class.new(db_path)
      expect(conn).to be_open
      conn.close
    end

    it 'returns false after the connection is closed' do
      conn = described_class.new(db_path)
      conn.close
      expect(conn).not_to be_open
    end
  end
end
