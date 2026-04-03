# frozen_string_literal: true

require "faraday"
require "json"

module RubynCode
  module CLI
    # Non-blocking version check against RubyGems.
    # Runs in a background thread so it never delays startup.
    # Caches the result for 24 hours to avoid hammering the API.
    class VersionCheck
      RUBYGEMS_API = "https://rubygems.org/api/v1/versions/rubyn-code/latest.json"
      CACHE_FILE = File.join(Config::Defaults::HOME_DIR, ".version_check")
      CACHE_TTL = 86_400 # 24 hours

      def initialize(renderer:)
        @renderer = renderer
        @thread = nil
      end

      # Kicks off a background check. Call `notify` later to display results.
      def start
        return if ENV["RUBYN_NO_UPDATE_CHECK"]

        @thread = Thread.new { check }
        @thread.abort_on_exception = false
      end

      # Waits briefly for the check to finish and prints a message if outdated.
      def notify(timeout: 2)
        return unless @thread

        @thread.join(timeout)
        return unless @result

        if newer?(@result, RubynCode::VERSION)
          @renderer.warning(
            "Update available: #{RubynCode::VERSION} -> #{@result}  " \
            "(gem install rubyn-code)"
          )
        end
      end

      private

      def check
        cached = read_cache
        if cached
          @result = cached
          return
        end

        conn = Faraday.new { |f| f.options.timeout = 5; f.options.open_timeout = 3 }
        response = conn.get(RUBYGEMS_API)
        return unless response.success?

        data = JSON.parse(response.body)
        latest = data["version"]
        return unless latest

        write_cache(latest)
        @result = latest
      rescue StandardError
        # Silent — never interrupt startup for a version check
      end

      def newer?(remote, local)
        Gem::Version.new(remote) > Gem::Version.new(local)
      rescue ArgumentError
        false
      end

      def read_cache
        return nil unless File.exist?(CACHE_FILE)
        return nil if (Time.now - File.mtime(CACHE_FILE)) > CACHE_TTL

        File.read(CACHE_FILE).strip
      rescue StandardError
        nil
      end

      def write_cache(version)
        File.write(CACHE_FILE, version)
      rescue StandardError
        # Best effort
      end
    end
  end
end
