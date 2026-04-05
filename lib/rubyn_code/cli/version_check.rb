# frozen_string_literal: true

require 'faraday'
require 'json'

module RubynCode
  module CLI
    # Non-blocking version check against RubyGems.
    # Runs in a background thread so it never delays startup.
    # Caches the result for 24 hours to avoid hammering the API.
    class VersionCheck
      RUBYGEMS_API = 'https://rubygems.org/api/v1/versions/rubyn-code/latest.json'
      CACHE_FILE = File.join(Config::Defaults::HOME_DIR, '.version_check')
      CACHE_TTL = 86_400 # 24 hours

      def initialize(renderer:)
        @renderer = renderer
        @thread = nil
      end

      # Kicks off a background check. Call `notify` later to display results.
      def start
        return if ENV['RUBYN_NO_UPDATE_CHECK']

        @thread = Thread.new { check }
        @thread.abort_on_exception = false
      end

      # Waits briefly for the check to finish and prints a message if outdated.
      def notify(timeout: 2)
        return unless @thread

        @thread.join(timeout)
        return unless @result

        return unless newer?(@result, RubynCode::VERSION)

        @renderer.warning(
          "Update available: #{RubynCode::VERSION} -> #{@result}  " \
          '(gem install rubyn-code)'
        )
      end

      private

      def check
        cached = read_cache
        if cached
          @result = cached
          return
        end

        latest = fetch_latest_version
        return unless latest

        write_cache(latest)
        @result = latest
      rescue StandardError
        # Silent — never interrupt startup for a version check
      end

      def fetch_latest_version
        conn = Faraday.new do |f|
          f.options.timeout = 5
          f.options.open_timeout = 3
        end
        response = conn.get(RUBYGEMS_API)
        return unless response.success?

        latest = JSON.parse(response.body)['version']
        latest if latest&.match?(/\A\d+\.\d+/) && Gem::Version.correct?(latest)
      end

      def newer?(remote, local)
        Gem::Version.new(remote) > Gem::Version.new(local)
      rescue ArgumentError
        false
      end

      def read_cache
        return nil unless File.exist?(CACHE_FILE)
        return nil if (Time.now - File.mtime(CACHE_FILE)) > CACHE_TTL

        cached = File.read(CACHE_FILE).strip
        return nil unless valid_version?(cached)

        cached
      rescue StandardError
        nil
      end

      def valid_version?(version)
        return false unless version&.match?(/\A\d+\.\d+/)
        return false unless Gem::Version.correct?(version)

        # Sanity: remote shouldn't be more than 10 major versions ahead
        remote = Gem::Version.new(version)
        local = Gem::Version.new(RubynCode::VERSION)
        (remote.segments.first - local.segments.first).abs < 10
      rescue StandardError
        false
      end

      def write_cache(version)
        File.write(CACHE_FILE, version)
      rescue StandardError
        # Best effort
      end
    end
  end
end
