# frozen_string_literal: true

require 'yaml'
require 'fileutils'
require_relative 'defaults'
require_relative 'settings'

module RubynCode
  module Config
    class ProjectConfig
      class LoadError < StandardError; end

      PROJECT_DIR_NAME = '.rubyn-code'
      CONFIG_FILENAME = 'config.yml'

      attr_reader :project_root, :config_path, :data

      # @param project_root [String] the root directory of the project (defaults to pwd)
      # @param global_settings [Settings, nil] global settings to fall back to
      def initialize(project_root: Dir.pwd, global_settings: nil)
        @project_root = File.expand_path(project_root)
        @project_dir = File.join(@project_root, PROJECT_DIR_NAME)
        @config_path = File.join(@project_dir, CONFIG_FILENAME)
        @global_settings = global_settings || Settings.new
        @data = {}
        load!
      end

      def get(key, default = nil)
        @data.fetch(key.to_s) { @global_settings.get(key, default) }
      end

      def set(key, value)
        @data[key.to_s] = value
      end

      # Dynamically delegate configurable keys: project-level overrides global
      Settings::CONFIGURABLE_KEYS.each do |key|
        define_method(key) do
          @data.fetch(key.to_s) { @global_settings.public_send(key) }
        end

        define_method(:"#{key}=") do |value|
          @data[key.to_s] = value
        end
      end

      def save!
        ensure_project_directory!
        File.write(@config_path, YAML.dump(@data))
      rescue Errno::EACCES => e
        raise LoadError, "Permission denied writing project config to #{@config_path}: #{e.message}"
      rescue SystemCallError => e
        raise LoadError, "Failed to save project config to #{@config_path}: #{e.message}"
      end

      def reload!
        load!
      end

      def to_h
        @global_settings.to_h.merge(@data)
      end

      def project_dir_exists?
        File.directory?(@project_dir)
      end

      # Walks up the directory tree to find the nearest .rubyn-code/config.yml
      # Returns nil if none is found before reaching the filesystem root.
      def self.find_nearest(start_dir: Dir.pwd, global_settings: nil)
        dir = File.expand_path(start_dir)

        loop do
          candidate = File.join(dir, PROJECT_DIR_NAME, CONFIG_FILENAME)
          return new(project_root: dir, global_settings: global_settings) if File.exist?(candidate)

          parent = File.dirname(dir)
          break if parent == dir # filesystem root reached

          dir = parent
        end

        nil
      end

      private

      def ensure_project_directory!
        return if File.directory?(@project_dir)

        FileUtils.mkdir_p(@project_dir)
      rescue SystemCallError => e
        raise LoadError, "Cannot create project config directory #{@project_dir}: #{e.message}"
      end

      def load!
        return unless File.exist?(@config_path)

        content = File.read(@config_path)
        return if content.strip.empty?

        parsed = YAML.safe_load(content, permitted_classes: [Symbol])

        case parsed
        in Hash => h
          @data = h.transform_keys(&:to_s)
        else
          raise LoadError, "Expected a YAML mapping in #{@config_path}, got #{parsed.class}"
        end
      rescue Psych::SyntaxError => e
        raise LoadError, "Malformed YAML in #{@config_path}: #{e.message}"
      rescue Errno::EACCES => e
        raise LoadError, "Permission denied reading #{@config_path}: #{e.message}"
      end
    end
  end
end
