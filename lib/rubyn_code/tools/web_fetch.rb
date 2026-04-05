# frozen_string_literal: true

require 'faraday'
require_relative 'base'
require_relative 'registry'

module RubynCode
  module Tools
    class WebFetch < Base
      TOOL_NAME = 'web_fetch'
      DESCRIPTION = 'Fetch the content of a web page and return it as text. ' \
                    'Useful for reading documentation, READMEs, or API docs.'
      PARAMETERS = {
        url: {
          type: :string, required: true,
          description: 'The URL to fetch (must start with http:// or https://)'
        },
        max_length: {
          type: :integer, required: false, default: 10_000,
          description: 'Maximum number of characters to return (default: 10000)'
        }
      }.freeze
      RISK_LEVEL = :external
      REQUIRES_CONFIRMATION = true

      MAX_REDIRECTS = 5
      REDIRECT_STATUSES = [301, 302, 303, 307, 308].freeze

      def execute(url:, max_length: 10_000)
        validate_url!(url)
        max_length = max_length.to_i.clamp(500, 100_000)

        response = fetch_page(url)
        text = html_to_text(response.body)
        text = collapse_whitespace(text)

        format_fetched_content(url, text, max_length)
      end

      private

      def format_fetched_content(url, text, max_length)
        return "Fetched #{url} but no readable text content was found." if text.strip.empty?

        header = "Content from: #{url}\n#{'=' * 60}\n\n"
        available = max_length - header.length
        content = text.length > available ? truncate_content(text, available, max_length) : text
        "#{header}#{content}"
      end

      def truncate_content(text, available, max_length)
        "#{text[0, available]}\n\n... [truncated at #{max_length} characters]"
      end

      def validate_url!(url)
        return if url.match?(%r{\Ahttps?://}i)

        raise Error,
              "Invalid URL: must start with http:// or https:// — got: #{url}"
      end

      def fetch_page(url, redirects: 0)
        conn = build_connection
        response = conn.get(url)

        return handle_redirect(url, response, redirects) if REDIRECT_STATUSES.include?(response.status)
        raise Error, "HTTP #{response.status} fetching #{url}" unless response.success?

        response
      rescue Faraday::TimeoutError
        raise Error, "Request timed out after 30 seconds fetching #{url}"
      rescue Faraday::ConnectionFailed => e
        raise Error, "Connection failed for #{url}: #{e.message}"
      rescue Faraday::Error => e
        raise Error, "Request failed for #{url}: #{e.message}"
      end

      def build_connection
        Faraday.new do |f|
          f.options.timeout = 30
          f.options.open_timeout = 10
          f.headers['User-Agent'] = 'Mozilla/5.0 (compatible; RubynCode/1.0)'
          f.headers['Accept'] = 'text/html,application/xhtml+xml,text/plain,*/*'
        end
      end

      def handle_redirect(url, response, redirects)
        raise Error, "Too many redirects fetching #{url}" if redirects >= MAX_REDIRECTS

        location = response.headers['location']
        raise Error, "Redirect with no Location header from #{url}" unless location

        location = URI.join(url, location).to_s unless location.start_with?('http')
        fetch_page(location, redirects: redirects + 1)
      end

      def html_to_text(html)
        return '' if html.nil? || html.empty?

        text = html.dup
        strip_scripts_and_styles!(text)
        convert_block_elements!(text)
        text.gsub!(/<[^>]*>/, '')
        decode_html_entities!(text)
        text
      end

      def strip_scripts_and_styles!(text)
        text.gsub!(%r{<script[^>]*>.*?</script>}mi, '')
        text.gsub!(%r{<style[^>]*>.*?</style>}mi, '')
      end

      def convert_block_elements!(text)
        text.gsub!(%r{<br\s*/?>}i, "\n")
        text.gsub!(%r{</(p|div|h[1-6]|li|tr|blockquote|pre)>}i, "\n")
        text.gsub!(/<(p|div|h[1-6]|li|tr|blockquote|pre)[^>]*>/i, "\n")
      end

      def decode_html_entities!(text)
        text.gsub!('&amp;', '&')
        text.gsub!('&lt;', '<')
        text.gsub!('&gt;', '>')
        text.gsub!('&quot;', '"')
        text.gsub!('&#39;', "'")
        text.gsub!('&nbsp;', ' ')
        text.gsub!(/&#(\d+);/) { [::Regexp.last_match(1).to_i].pack('U') }
      end

      def collapse_whitespace(text)
        text.gsub(/[^\S\n]+/, ' ')
            .gsub(/\n{3,}/, "\n\n")
            .strip
      end
    end

    Registry.register(WebFetch)
  end
end
