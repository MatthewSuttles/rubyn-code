# frozen_string_literal: true

require 'tmpdir'

RSpec.describe RubynCode::Context::SchemaFilter do
  around do |example|
    Dir.mktmpdir do |dir|
      @tmpdir = dir
      example.run
    end
  end

  def write_schema(content)
    path = File.join(@tmpdir, 'schema.rb')
    File.write(path, content)
    path
  end

  let(:sample_schema) do
    <<~SCHEMA
      ActiveRecord::Schema.define(version: 2024_01_01_000000) do

        create_table "users", force: :cascade do |t|
          t.string "name"
          t.string "email"
          t.timestamps
        end

        create_table "posts", force: :cascade do |t|
          t.string "title"
          t.text "body"
          t.bigint "user_id"
          t.timestamps
        end

        create_table "comments", force: :cascade do |t|
          t.text "body"
          t.bigint "post_id"
          t.timestamps
        end

      end
    SCHEMA
  end

  describe '.filter' do
    it 'extracts matching table definitions' do
      path = write_schema(sample_schema)

      result = described_class.filter(path, table_names: ['users'])

      expect(result).to include('create_table "users"')
      expect(result).to include('t.string "name"')
      expect(result).to include('t.string "email"')
      expect(result).not_to include('create_table "posts"')
      expect(result).not_to include('create_table "comments"')
    end

    it 'extracts multiple matching tables' do
      path = write_schema(sample_schema)

      result = described_class.filter(path, table_names: ['users', 'comments'])

      expect(result).to include('create_table "users"')
      expect(result).to include('create_table "comments"')
      expect(result).not_to include('create_table "posts"')
    end

    it 'returns empty string when no tables match' do
      path = write_schema(sample_schema)

      result = described_class.filter(path, table_names: ['nonexistent'])

      expect(result).to eq('')
    end

    it 'returns empty string when table_names is empty' do
      path = write_schema(sample_schema)

      result = described_class.filter(path, table_names: [])

      expect(result).to eq('')
    end

    it 'returns empty string when schema_path does not exist' do
      result = described_class.filter('/nonexistent/schema.rb', table_names: ['users'])

      expect(result).to eq('')
    end

    it 'detects end-of-table correctly and does not bleed into next table' do
      path = write_schema(sample_schema)

      result = described_class.filter(path, table_names: ['users'])

      expect(result).not_to include('t.string "title"')
      expect(result).not_to include('t.text "body"')
      # Should include user fields but not post fields
      expect(result).to include('t.string "email"')
    end

    it 'accepts symbol table names' do
      path = write_schema(sample_schema)

      result = described_class.filter(path, table_names: [:users])

      expect(result).to include('create_table "users"')
    end
  end

  describe '.tableize' do
    it 'converts CamelCase model names to snake_case pluralized table names' do
      result = described_class.tableize(['User', 'OrderItem', 'Post'])

      expect(result).to eq(['users', 'order_items', 'posts'])
    end

    it 'handles single-word model names' do
      result = described_class.tableize(['Post'])

      expect(result).to eq(['posts'])
    end

    it 'handles multi-hump CamelCase names' do
      result = described_class.tableize(['UserAccountSetting'])

      expect(result).to eq(['user_account_settings'])
    end

    it 'returns empty array for empty input' do
      result = described_class.tableize([])

      expect(result).to eq([])
    end
  end

  describe '.filter_for_models' do
    it 'filters schema by model names using tableize' do
      path = write_schema(sample_schema)

      result = described_class.filter_for_models(path, model_names: ['User'])

      expect(result).to include('create_table "users"')
      expect(result).not_to include('create_table "posts"')
    end

    it 'handles multiple model names' do
      path = write_schema(sample_schema)

      result = described_class.filter_for_models(path, model_names: ['User', 'Post'])

      expect(result).to include('create_table "users"')
      expect(result).to include('create_table "posts"')
      expect(result).not_to include('create_table "comments"')
    end
  end
end
