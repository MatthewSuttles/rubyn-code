# frozen_string_literal: true

require 'yaml'
require 'fileutils'

module RubynCode
  module Config
    # Auto-generated project profile that caches detected project stack
    # information. First session pays the detection cost; subsequent
    # sessions load a compact ~500-token profile instead of re-exploring.
    class ProjectProfile
      PROFILE_FILENAME = 'project_profile.yml'

      DETECTABLE_KEYS = %w[
        framework ruby_version database test_framework
        factories auth background_jobs api frontend
        key_models service_pattern custom_conventions
      ].freeze

      attr_reader :data, :profile_path

      def initialize(project_root:)
        @project_root = File.expand_path(project_root)
        @project_dir = File.join(@project_root, '.rubyn-code')
        @profile_path = File.join(@project_dir, PROFILE_FILENAME)
        @data = {}
      end

      # Load existing profile or return nil if none exists.
      def load
        return nil unless File.exist?(@profile_path)

        raw = YAML.safe_load_file(@profile_path, permitted_classes: [Symbol])
        @data = raw.is_a?(Hash) ? raw : {}
        self
      rescue StandardError
        nil
      end

      # Detect project stack and save profile.
      def detect_and_save!
        @data = {}
        detect_framework
        detect_ruby_version
        detect_database
        detect_test_framework
        detect_auth
        detect_background_jobs
        detect_api_framework
        detect_key_models
        detect_service_pattern
        save!
        self
      end

      # Load if exists, otherwise detect and save.
      def load_or_detect!
        load || detect_and_save!
      end

      # Compact string representation for system prompt injection (~500 tokens).
      def to_prompt
        return '' if @data.empty?

        lines = ['Project Profile:']
        @data.each do |key, value|
          formatted = value.is_a?(Array) ? value.join(', ') : value.to_s
          lines << "  #{key}: #{formatted}" unless formatted.empty?
        end
        lines.join("\n")
      end

      # Save the current profile data to disk.
      def save!
        FileUtils.mkdir_p(@project_dir)
        File.write(@profile_path, YAML.dump(@data))
      end

      # Check if the profile is stale (older than 7 days).
      def stale?
        return true unless File.exist?(@profile_path)

        (Time.now - File.mtime(@profile_path)) > 604_800
      end

      FRAMEWORK_GEMS = { 'rails' => 'rails', 'sinatra' => 'sinatra', 'hanami' => 'hanami' }.freeze
      API_GEMS = { 'grape' => 'grape', 'graphql' => 'graphql' }.freeze
      FRONTEND_GEMS = { 'turbo-rails' => 'hotwire', 'react-rails' => 'react' }.freeze

      private

      def detect_framework
        gemfile = read_file('Gemfile')
        return unless gemfile

        @data['framework'] = FRAMEWORK_GEMS.each_value.find { |gem| gemfile.include?(gem) } || 'ruby'
      end

      def detect_ruby_version
        path = File.join(@project_root, '.ruby-version')
        @data['ruby_version'] = File.read(path).strip if File.exist?(path)
      end

      def detect_database
        gemfile = read_file('Gemfile')
        return unless gemfile

        @data['database'] = 'postgresql' if gemfile.include?('pg')
        @data['database'] ||= 'mysql' if gemfile.include?('mysql2')
        @data['database'] ||= 'sqlite' if gemfile.include?('sqlite3')
      end

      def detect_test_framework
        gemfile = read_file('Gemfile')
        return unless gemfile

        @data['test_framework'] = 'rspec' if gemfile.match?(/['"]rspec['"]/)
        @data['test_framework'] ||= 'minitest' if gemfile.include?('minitest')
        @data['factories'] = 'factory_bot' if gemfile.include?('factory_bot')
      end

      def detect_auth
        gemfile = read_file('Gemfile')
        return unless gemfile

        @data['auth'] = 'devise' if gemfile.include?('devise')
        @data['auth'] ||= 'rodauth' if gemfile.include?('rodauth')
        @data['auth'] ||= 'clearance' if gemfile.include?('clearance')
      end

      def detect_background_jobs
        gemfile = read_file('Gemfile')
        return unless gemfile

        @data['background_jobs'] = 'sidekiq' if gemfile.include?('sidekiq')
        @data['background_jobs'] ||= 'good_job' if gemfile.include?('good_job')
        @data['background_jobs'] ||= 'solid_queue' if gemfile.include?('solid_queue')
      end

      def detect_api_framework
        gemfile = read_file('Gemfile')
        return unless gemfile

        detect_gem_key(gemfile, 'api', API_GEMS)
        detect_gem_key(gemfile, 'frontend', FRONTEND_GEMS)
      end

      def detect_gem_key(gemfile, key, gem_map)
        gem_map.each do |gem_name, value|
          next if @data[key]

          @data[key] = value if gemfile.include?(gem_name)
        end
      end

      def detect_key_models
        model_dir = File.join(@project_root, 'app', 'models')
        return unless File.directory?(model_dir)

        models = Dir.glob(File.join(model_dir, '*.rb'))
                    .map { |f| File.basename(f, '.rb').split('_').map(&:capitalize).join }
                    .reject { |m| m == 'ApplicationRecord' }
                    .first(20)
        @data['key_models'] = models unless models.empty?
      end

      def detect_service_pattern
        service_dir = File.join(@project_root, 'app', 'services')
        return unless File.directory?(service_dir)

        @data['service_pattern'] = 'app/services/**/*_service.rb'
        conventions = []
        conventions << 'Service objects implement .call class method'
        @data['custom_conventions'] = conventions
      end

      def read_file(relative_path)
        path = File.join(@project_root, relative_path)
        File.read(path) if File.exist?(path)
      rescue StandardError
        nil
      end
    end
  end
end
