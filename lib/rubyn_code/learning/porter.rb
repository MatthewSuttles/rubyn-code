# frozen_string_literal: true

require 'json'
require 'securerandom'

module RubynCode
  module Learning
    # Exports and imports learned instincts so a user can carry their
    # accumulated learnings to another machine. Instincts live in SQLite under
    # ~/.rubyn-code; this serializes them to a portable JSON file and loads
    # them back, regenerating ids and de-duplicating by (project_path, pattern).
    module Porter
      FORMAT_VERSION = 1
      # Columns carried across machines (id is regenerated on import).
      COLUMNS = %w[
        project_path pattern context_tags confidence decay_rate
        times_applied times_helpful created_at updated_at
      ].freeze

      class Error < RubynCode::Error; end

      class << self
        # Export instincts to a JSON file.
        #
        # @param db [DB::Connection]
        # @param path [String] destination file
        # @param project_path [String, nil] limit to one project, or nil for all
        # @return [Integer] number of instincts exported
        def export(db:, path:, project_path: nil)
          rows = fetch(db, project_path)
          payload = { 'version' => FORMAT_VERSION, 'instincts' => rows }
          File.write(path, "#{JSON.pretty_generate(payload)}\n")
          rows.size
        end

        # Import instincts from a JSON file.
        #
        # @param db [DB::Connection]
        # @param path [String] source file
        # @param remap_project [String, nil] override every row's project_path
        #   (use the current project so imported learnings apply here)
        # @return [Hash] { imported:, skipped:, total: }
        def import(db:, path:, remap_project: nil)
          raise Error, "File not found: #{path}" unless File.file?(path)

          payload = parse(path)
          instincts = Array(payload['instincts'])
          imported = instincts.count { |row| import_row(db, row, remap_project) }

          { imported: imported, skipped: instincts.size - imported, total: instincts.size }
        end

        # @return [Hash] { count:, projects: } summary for display
        def stats(db, project_path: nil)
          rows = fetch(db, project_path)
          { count: rows.size, projects: rows.map { |r| r['project_path'] }.uniq.size }
        end

        private

        def fetch(db, project_path)
          select = "SELECT #{COLUMNS.join(', ')} FROM instincts"
          if project_path
            db.query("#{select} WHERE project_path = ?", [project_path]).to_a
          else
            db.query(select).to_a
          end
        end

        def parse(path)
          payload = JSON.parse(File.read(path))
          raise Error, 'Not a Rubyn learnings file' unless payload.is_a?(Hash) && payload.key?('instincts')

          version = payload['version'].to_i
          raise Error, "Unsupported export version: #{version}" if version > FORMAT_VERSION

          payload
        rescue JSON::ParserError => e
          raise Error, "Invalid JSON: #{e.message}"
        end

        # @return [Boolean] true if inserted, false if skipped (duplicate)
        def import_row(db, row, remap_project)
          project = remap_project || row['project_path']
          return false if project.to_s.empty? || row['pattern'].to_s.empty?
          return false if exists?(db, project, row['pattern'])

          insert(db, row, project)
          true
        rescue StandardError => e
          RubynCode::Debug.warn("Skipping instinct import: #{e.message}")
          false
        end

        def exists?(db, project, pattern)
          db.query(
            'SELECT 1 FROM instincts WHERE project_path = ? AND pattern = ? LIMIT 1',
            [project, pattern]
          ).to_a.any?
        end

        def insert(db, row, project)
          now = Time.now.utc.strftime('%Y-%m-%dT%H:%M:%SZ')
          db.execute(
            <<~SQL.tr("\n", ' ').strip,
              INSERT INTO instincts (id, project_path, pattern, context_tags,
                confidence, decay_rate, times_applied, times_helpful, created_at, updated_at)
              VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
            SQL
            [
              SecureRandom.uuid, project, row['pattern'], normalize_tags(row['context_tags']),
              (row['confidence'] || 0.5).to_f, (row['decay_rate'] || 0.05).to_f,
              (row['times_applied'] || 0).to_i, (row['times_helpful'] || 0).to_i,
              row['created_at'] || now, row['updated_at'] || now
            ]
          )
        end

        # context_tags is stored as a JSON string column; accept either a JSON
        # string or an array from the export file.
        def normalize_tags(tags)
          return tags if tags.is_a?(String)

          JSON.generate(Array(tags))
        end
      end
    end
  end
end
