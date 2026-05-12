# frozen_string_literal: true

require 'open3'
require 'cgi'
require 'json'
require 'faraday'
require_relative 'base'
require_relative 'registry'

module RubynCode
  module Tools
    class WebSearch < Base
      TOOL_NAME = 'web_search'
      DESCRIPTION = 'Search the web for information. Returns search results with titles, URLs, and snippets.'
      PARAMETERS = {
        query: { type: :string, required: true, description: 'The search query string' },
        num_results: {
          type: :integer, required: false, default: 5,
          description: 'Number of results (default: 5)'
        }
      }.freeze
      RISK_LEVEL = :external
      REQUIRES_CONFIRMATION = true

      # Adapter registry -- add new providers here
      ADAPTERS = {
        'duckduckgo' => :search_duckduckgo,
        'brave' => :search_brave,
        'serpapi' => :search_serpapi,
        'tavily' => :search_tavily,
        'google' => :search_google
      }.freeze

      def execute(query:, num_results: 5)
        num_results = num_results.to_i.clamp(1, 20)
        provider = detect_provider

        results = send(ADAPTERS[provider], query, num_results)

        if results.empty?
          "No results found for: #{query}"
        else
          format_results(query, results, provider)
        end
      rescue StandardError => e
        "Search failed (#{detect_provider}): #{e.message}"
      end

      private

      def detect_provider
        return 'tavily'  if ENV['TAVILY_API_KEY']
        return 'brave'   if ENV['BRAVE_API_KEY']
        return 'serpapi' if ENV['SERPAPI_API_KEY']
        return 'google' if ENV['GOOGLE_SEARCH_API_KEY'] && ENV['GOOGLE_SEARCH_CX']

        'duckduckgo'
      end

      # --- DuckDuckGo (no API key, free) ---

      def search_duckduckgo(query, num_results)
        encoded = CGI.escape(query)
        url = "https://lite.duckduckgo.com/lite/?q=#{encoded}"
        stdout, _, status = safe_capture3(
          'curl', '-sL', '--max-time', '15',
          '-H', 'User-Agent: Mozilla/5.0 (compatible; RubynCode/1.0)',
          url
        )
        return [] unless status.success?

        parse_duckduckgo(stdout, num_results)
      end

      def parse_duckduckgo(html, max)
        links = extract_ddg_links(html)
        snippets = html.scan(%r{<td[^>]*class="result-snippet"[^>]*>(.*?)</td>}im)
        build_ddg_results(links, snippets, max)
      end

      def extract_ddg_links(html)
        links = html.scan(%r{<a[^>]+rel="nofollow"[^>]+href="([^"]+)"[^>]*>(.*?)</a>}i)
        return links unless links.empty?

        html.scan(%r{<a[^>]+href="(https?://(?!lite\.duckduckgo)[^"]+)"[^>]*>(.*?)</a>}i)
      end

      # -- HTML parsing with filtering
      def build_ddg_results(links, snippets, max)
        results = []
        links.each_with_index do |match, idx|
          break if results.length >= max

          url = match[0].strip
          title = strip_html(match[1]).strip
          next if url.empty? || title.empty? || url.include?('duckduckgo.com')

          snippet = snippets[idx] ? strip_html(snippets[idx][0]).strip : ''
          results << { title: title, url: url, snippet: snippet }
        end
        results
      end

      # --- Brave Search (free tier: 2000 queries/mo) ---

      def search_brave(query, num_results)
        resp = brave_request(query, num_results)
        data = JSON.parse(resp.body)
        (data.dig('web', 'results') || []).map do |r|
          { title: r['title'], url: r['url'], snippet: r['description'] || '' }
        end
      end

      def brave_request(query, num_results)
        Faraday.get('https://api.search.brave.com/res/v1/web/search') do |req|
          req.params['q'] = query
          req.params['count'] = num_results
          req.headers['Accept'] = 'application/json'
          req.headers['Accept-Encoding'] = 'gzip'
          req.headers['X-Subscription-Token'] = ENV.fetch('BRAVE_API_KEY', nil)
          req.options.timeout = 15
        end
      end

      # --- Tavily (built for AI agents, free tier: 1000 queries/mo) ---

      def search_tavily(query, num_results)
        resp = tavily_request(query, num_results)
        data = JSON.parse(resp.body)
        results = (data['results'] || []).map do |r|
          { title: r['title'], url: r['url'], snippet: r['content'] || '' }
        end
        results.unshift(title: 'AI Answer', url: '', snippet: data['answer']) if data['answer']
        results
      end

      def tavily_request(query, num_results)
        Faraday.post('https://api.tavily.com/search') do |req|
          req.headers['Content-Type'] = 'application/json'
          req.body = JSON.generate(
            api_key: ENV.fetch('TAVILY_API_KEY', nil),
            query: query, max_results: num_results, include_answer: true
          )
          req.options.timeout = 15
        end
      end

      # --- SerpAPI (free tier: 100 queries/mo) ---

      def search_serpapi(query, num_results)
        resp = serpapi_request(query, num_results)
        data = JSON.parse(resp.body)
        (data['organic_results'] || []).map do |r|
          { title: r['title'], url: r['link'], snippet: r['snippet'] || '' }
        end
      end

      def serpapi_request(query, num_results)
        Faraday.get('https://serpapi.com/search.json') do |req|
          req.params['q'] = query
          req.params['num'] = num_results
          req.params['api_key'] = ENV.fetch('SERPAPI_API_KEY', nil)
          req.options.timeout = 15
        end
      end

      # --- Google Custom Search (free tier: 100 queries/day) ---

      def search_google(query, num_results)
        resp = google_request(query, num_results)
        data = JSON.parse(resp.body)
        (data['items'] || []).map do |r|
          { title: r['title'], url: r['link'], snippet: r['snippet'] || '' }
        end
      end

      def google_request(query, num_results)
        Faraday.get('https://www.googleapis.com/customsearch/v1') do |req|
          req.params['q'] = query
          req.params['num'] = [num_results, 10].min
          req.params['key'] = ENV.fetch('GOOGLE_SEARCH_API_KEY', nil)
          req.params['cx'] = ENV.fetch('GOOGLE_SEARCH_CX', nil)
          req.options.timeout = 15
        end
      end

      # --- Shared ---

      def strip_html(text)
        return '' if text.nil?

        text.gsub(/<[^>]*>/, '').gsub('&amp;', '&').gsub('&lt;', '<')
            .gsub('&gt;', '>').gsub('&quot;', '"').gsub('&#39;', "'")
            .gsub('&nbsp;', ' ').gsub(/\s+/, ' ').strip
      end

      def format_results(query, results, provider)
        lines = ["Search results for: #{query} (via #{provider})\n"]

        results.each_with_index do |result, idx|
          lines << "#{idx + 1}. #{result[:title]}"
          lines << "   URL: #{result[:url]}" unless result[:url].empty?
          lines << "   #{result[:snippet]}" unless result[:snippet].empty?
          lines << ''
        end

        truncate(lines.join("\n"), max: 30_000)
      end
    end

    Registry.register(WebSearch)
  end
end
