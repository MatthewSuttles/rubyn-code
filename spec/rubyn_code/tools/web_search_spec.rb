# frozen_string_literal: true

require 'spec_helper'

RSpec.describe RubynCode::Tools::WebSearch do
  let(:tool) do
    with_temp_project do |dir|
      return described_class.new(project_root: dir)
    end
  end

  # Clear all search-related ENV vars so tests don't leak
  around do |example|
    original_env = {
      'TAVILY_API_KEY' => ENV['TAVILY_API_KEY'],
      'BRAVE_API_KEY' => ENV['BRAVE_API_KEY'],
      'SERPAPI_API_KEY' => ENV['SERPAPI_API_KEY'],
      'GOOGLE_SEARCH_API_KEY' => ENV['GOOGLE_SEARCH_API_KEY'],
      'GOOGLE_SEARCH_CX' => ENV['GOOGLE_SEARCH_CX']
    }
    ENV.delete('TAVILY_API_KEY')
    ENV.delete('BRAVE_API_KEY')
    ENV.delete('SERPAPI_API_KEY')
    ENV.delete('GOOGLE_SEARCH_API_KEY')
    ENV.delete('GOOGLE_SEARCH_CX')
    example.run
  ensure
    original_env.each { |k, v| v.nil? ? ENV.delete(k) : ENV[k] = v }
  end

  describe 'provider detection' do
    it 'detects tavily when TAVILY_API_KEY is set' do
      ENV['TAVILY_API_KEY'] = 'test-tavily-key'
      expect(tool.send(:detect_provider)).to eq('tavily')
    end

    it 'detects brave when BRAVE_API_KEY is set' do
      ENV['BRAVE_API_KEY'] = 'test-brave-key'
      expect(tool.send(:detect_provider)).to eq('brave')
    end

    it 'detects serpapi when SERPAPI_API_KEY is set' do
      ENV['SERPAPI_API_KEY'] = 'test-serpapi-key'
      expect(tool.send(:detect_provider)).to eq('serpapi')
    end

    it 'detects google when both GOOGLE_SEARCH_API_KEY and GOOGLE_SEARCH_CX are set' do
      ENV['GOOGLE_SEARCH_API_KEY'] = 'test-google-key'
      ENV['GOOGLE_SEARCH_CX'] = 'test-google-cx'
      expect(tool.send(:detect_provider)).to eq('google')
    end

    it 'falls back to duckduckgo when no keys are set' do
      expect(tool.send(:detect_provider)).to eq('duckduckgo')
    end

    it 'prioritizes tavily over all other providers' do
      ENV['TAVILY_API_KEY'] = 'test-tavily-key'
      ENV['BRAVE_API_KEY'] = 'test-brave-key'
      ENV['SERPAPI_API_KEY'] = 'test-serpapi-key'
      ENV['GOOGLE_SEARCH_API_KEY'] = 'test-google-key'
      ENV['GOOGLE_SEARCH_CX'] = 'test-google-cx'
      expect(tool.send(:detect_provider)).to eq('tavily')
    end

    it 'prioritizes brave over serpapi, google, and duckduckgo' do
      ENV['BRAVE_API_KEY'] = 'test-brave-key'
      ENV['SERPAPI_API_KEY'] = 'test-serpapi-key'
      ENV['GOOGLE_SEARCH_API_KEY'] = 'test-google-key'
      ENV['GOOGLE_SEARCH_CX'] = 'test-google-cx'
      expect(tool.send(:detect_provider)).to eq('brave')
    end

    it 'prioritizes serpapi over google and duckduckgo' do
      ENV['SERPAPI_API_KEY'] = 'test-serpapi-key'
      ENV['GOOGLE_SEARCH_API_KEY'] = 'test-google-key'
      ENV['GOOGLE_SEARCH_CX'] = 'test-google-cx'
      expect(tool.send(:detect_provider)).to eq('serpapi')
    end

    it 'does not detect google when only GOOGLE_SEARCH_API_KEY is set' do
      ENV['GOOGLE_SEARCH_API_KEY'] = 'test-google-key'
      expect(tool.send(:detect_provider)).to eq('duckduckgo')
    end
  end

  describe 'num_results clamping' do
    before do
      allow(tool).to receive(:detect_provider).and_return('duckduckgo')
      allow(tool).to receive(:search_duckduckgo).and_return([])
    end

    it 'clamps minimum to 1' do
      tool.execute(query: 'test', num_results: -5)
      expect(tool).to have_received(:search_duckduckgo).with('test', 1)
    end

    it 'clamps zero to 1' do
      tool.execute(query: 'test', num_results: 0)
      expect(tool).to have_received(:search_duckduckgo).with('test', 1)
    end

    it 'clamps maximum to 20' do
      tool.execute(query: 'test', num_results: 50)
      expect(tool).to have_received(:search_duckduckgo).with('test', 20)
    end

    it 'passes valid num_results through unchanged' do
      tool.execute(query: 'test', num_results: 10)
      expect(tool).to have_received(:search_duckduckgo).with('test', 10)
    end
  end

  describe 'DuckDuckGo adapter' do
    let(:ddg_html) do
      <<~HTML
        <table>
          <tr>
            <td><a rel="nofollow" href="https://example.com/page1">Example &amp; Page One</a></td>
            <td class="result-snippet">This is the <b>first</b> snippet.</td>
          </tr>
          <tr>
            <td><a rel="nofollow" href="https://example.org/page2">Page Two</a></td>
            <td class="result-snippet">Second snippet here.</td>
          </tr>
          <tr>
            <td><a rel="nofollow" href="https://example.net/page3">Page Three</a></td>
            <td class="result-snippet">Third snippet.</td>
          </tr>
        </table>
      HTML
    end

    let(:success_status) { instance_double(Process::Status, success?: true) }
    let(:failure_status) { instance_double(Process::Status, success?: false) }

    before do
      allow(tool).to receive(:detect_provider).and_return('duckduckgo')
    end

    it 'calls curl with correct URL and user agent' do
      allow(Open3).to receive(:capture3).and_return([ddg_html, '', success_status])

      tool.execute(query: 'ruby programming')

      expect(Open3).to have_received(:capture3).with(
        'curl', '-sL', '--max-time', '15',
        '-H', 'User-Agent: Mozilla/5.0 (compatible; RubynCode/1.0)',
        "https://lite.duckduckgo.com/lite/?q=ruby+programming"
      )
    end

    it 'parses HTML results with links and snippets' do
      allow(Open3).to receive(:capture3).and_return([ddg_html, '', success_status])

      result = tool.execute(query: 'test query')

      expect(result).to include('Search results for: test query (via duckduckgo)')
      expect(result).to include('Example & Page One')
      expect(result).to include('https://example.com/page1')
      expect(result).to include('first snippet')
      expect(result).to include('Page Two')
      expect(result).to include('https://example.org/page2')
    end

    it 'returns empty array when curl fails' do
      allow(Open3).to receive(:capture3).and_return(['', '', failure_status])

      result = tool.execute(query: 'failing query')

      expect(result).to eq('No results found for: failing query')
    end

    it 'limits results to num_results' do
      allow(Open3).to receive(:capture3).and_return([ddg_html, '', success_status])

      result = tool.execute(query: 'test', num_results: 1)

      expect(result).to include('1. Example & Page One')
      expect(result).not_to include('Page Two')
      expect(result).not_to include('Page Three')
    end

    it 'strips HTML tags and decodes entities from results' do
      allow(Open3).to receive(:capture3).and_return([ddg_html, '', success_status])

      result = tool.execute(query: 'test')

      expect(result).to include('Example & Page One')
      expect(result).to include('first snippet')
      expect(result).not_to include('<b>')
      expect(result).not_to include('&amp;')
    end

    it 'skips results with duckduckgo.com in the URL' do
      html_with_ddg_link = <<~HTML
        <a rel="nofollow" href="https://duckduckgo.com/something">DDG Link</a>
        <a rel="nofollow" href="https://example.com/real">Real Result</a>
        <td class="result-snippet">Real snippet.</td>
      HTML
      allow(Open3).to receive(:capture3).and_return([html_with_ddg_link, '', success_status])

      result = tool.execute(query: 'test')

      expect(result).not_to include('DDG Link')
      expect(result).to include('Real Result')
    end

    it 'falls back to non-nofollow link pattern when nofollow links are empty' do
      html_without_nofollow = <<~HTML
        <a href="https://example.com/fallback">Fallback Result</a>
        <td class="result-snippet">Fallback snippet.</td>
      HTML
      allow(Open3).to receive(:capture3).and_return([html_without_nofollow, '', success_status])

      result = tool.execute(query: 'test')

      expect(result).to include('Fallback Result')
    end
  end

  describe 'Brave adapter' do
    let(:brave_response_body) do
      JSON.generate({
        'web' => {
          'results' => [
            { 'title' => 'Brave Result 1', 'url' => 'https://brave1.com', 'description' => 'Brave snippet 1' },
            { 'title' => 'Brave Result 2', 'url' => 'https://brave2.com', 'description' => 'Brave snippet 2' }
          ]
        }
      })
    end

    before do
      ENV['BRAVE_API_KEY'] = 'test-brave-key'
    end

    it 'makes GET request with correct headers' do
      stub_request(:get, 'https://api.search.brave.com/res/v1/web/search')
        .with(
          query: hash_including('q' => 'test query', 'count' => '5'),
          headers: { 'X-Subscription-Token' => 'test-brave-key', 'Accept' => 'application/json' }
        )
        .to_return(status: 200, body: brave_response_body)

      result = tool.execute(query: 'test query')

      expect(result).to include('Search results for: test query (via brave)')
      expect(result).to include('Brave Result 1')
      expect(result).to include('https://brave1.com')
      expect(result).to include('Brave snippet 1')
    end

    it 'parses JSON response into result hashes' do
      stub_request(:get, /api\.search\.brave\.com/)
        .to_return(status: 200, body: brave_response_body)

      result = tool.execute(query: 'test')

      expect(result).to include('Brave Result 1')
      expect(result).to include('Brave Result 2')
      expect(result).to include('Brave snippet 2')
    end

    it 'handles empty results gracefully' do
      stub_request(:get, /api\.search\.brave\.com/)
        .to_return(status: 200, body: JSON.generate({ 'web' => { 'results' => [] } }))

      result = tool.execute(query: 'nothing here')

      expect(result).to eq('No results found for: nothing here')
    end

    it 'handles missing description with empty string' do
      body = JSON.generate({
        'web' => {
          'results' => [
            { 'title' => 'No Desc', 'url' => 'https://nodesc.com' }
          ]
        }
      })
      stub_request(:get, /api\.search\.brave\.com/)
        .to_return(status: 200, body: body)

      result = tool.execute(query: 'test')

      expect(result).to include('No Desc')
      expect(result).to include('https://nodesc.com')
    end
  end

  describe 'Tavily adapter' do
    let(:tavily_response_body) do
      JSON.generate({
        'results' => [
          { 'title' => 'Tavily Result 1', 'url' => 'https://tavily1.com', 'content' => 'Tavily content 1' },
          { 'title' => 'Tavily Result 2', 'url' => 'https://tavily2.com', 'content' => 'Tavily content 2' }
        ]
      })
    end

    before do
      ENV['TAVILY_API_KEY'] = 'test-tavily-key'
    end

    it 'makes POST request with API key in body' do
      stub_request(:post, 'https://api.tavily.com/search')
        .with { |req|
          body = JSON.parse(req.body)
          body['api_key'] == 'test-tavily-key' &&
            body['query'] == 'test query' &&
            body['max_results'] == 5 &&
            body['include_answer'] == true
        }
        .to_return(status: 200, body: tavily_response_body)

      result = tool.execute(query: 'test query')

      expect(result).to include('Search results for: test query (via tavily)')
    end

    it 'parses results array' do
      stub_request(:post, 'https://api.tavily.com/search')
        .to_return(status: 200, body: tavily_response_body)

      result = tool.execute(query: 'test')

      expect(result).to include('Tavily Result 1')
      expect(result).to include('https://tavily1.com')
      expect(result).to include('Tavily content 1')
      expect(result).to include('Tavily Result 2')
    end

    it 'prepends AI answer when present' do
      body_with_answer = JSON.generate({
        'answer' => 'The AI-generated answer.',
        'results' => [
          { 'title' => 'Result', 'url' => 'https://example.com', 'content' => 'Content' }
        ]
      })
      stub_request(:post, 'https://api.tavily.com/search')
        .to_return(status: 200, body: body_with_answer)

      result = tool.execute(query: 'test')

      expect(result).to include('1. AI Answer')
      expect(result).to include('The AI-generated answer.')
      expect(result).to include('2. Result')
    end

    it 'does not prepend AI answer when absent' do
      stub_request(:post, 'https://api.tavily.com/search')
        .to_return(status: 200, body: tavily_response_body)

      result = tool.execute(query: 'test')

      expect(result).not_to include('AI Answer')
      expect(result).to include('1. Tavily Result 1')
    end
  end

  describe 'SerpAPI adapter' do
    let(:serpapi_response_body) do
      JSON.generate({
        'organic_results' => [
          { 'title' => 'Serp Result 1', 'link' => 'https://serp1.com', 'snippet' => 'Serp snippet 1' },
          { 'title' => 'Serp Result 2', 'link' => 'https://serp2.com', 'snippet' => 'Serp snippet 2' }
        ]
      })
    end

    before do
      ENV['SERPAPI_API_KEY'] = 'test-serpapi-key'
    end

    it 'makes GET request with api_key param' do
      stub_request(:get, 'https://serpapi.com/search.json')
        .with(query: hash_including('q' => 'test query', 'api_key' => 'test-serpapi-key'))
        .to_return(status: 200, body: serpapi_response_body)

      result = tool.execute(query: 'test query')

      expect(result).to include('Search results for: test query (via serpapi)')
    end

    it 'parses organic_results' do
      stub_request(:get, /serpapi\.com\/search\.json/)
        .to_return(status: 200, body: serpapi_response_body)

      result = tool.execute(query: 'test')

      expect(result).to include('Serp Result 1')
      expect(result).to include('https://serp1.com')
      expect(result).to include('Serp snippet 1')
      expect(result).to include('Serp Result 2')
    end

    it 'handles empty organic_results' do
      stub_request(:get, /serpapi\.com\/search\.json/)
        .to_return(status: 200, body: JSON.generate({ 'organic_results' => [] }))

      result = tool.execute(query: 'empty')

      expect(result).to eq('No results found for: empty')
    end
  end

  describe 'Google adapter' do
    let(:google_response_body) do
      JSON.generate({
        'items' => [
          { 'title' => 'Google Result 1', 'link' => 'https://google1.com', 'snippet' => 'Google snippet 1' },
          { 'title' => 'Google Result 2', 'link' => 'https://google2.com', 'snippet' => 'Google snippet 2' }
        ]
      })
    end

    before do
      ENV['GOOGLE_SEARCH_API_KEY'] = 'test-google-key'
      ENV['GOOGLE_SEARCH_CX'] = 'test-google-cx'
    end

    it 'makes GET request with key and cx params' do
      stub_request(:get, 'https://www.googleapis.com/customsearch/v1')
        .with(query: hash_including(
          'q' => 'test query',
          'key' => 'test-google-key',
          'cx' => 'test-google-cx'
        ))
        .to_return(status: 200, body: google_response_body)

      result = tool.execute(query: 'test query')

      expect(result).to include('Search results for: test query (via google)')
      expect(result).to include('Google Result 1')
    end

    it 'parses items from response' do
      stub_request(:get, /googleapis\.com\/customsearch/)
        .to_return(status: 200, body: google_response_body)

      result = tool.execute(query: 'test')

      expect(result).to include('Google Result 1')
      expect(result).to include('https://google1.com')
      expect(result).to include('Google snippet 1')
      expect(result).to include('Google Result 2')
    end

    it 'caps num_results at 10' do
      stub_request(:get, 'https://www.googleapis.com/customsearch/v1')
        .with(query: hash_including('num' => '10'))
        .to_return(status: 200, body: google_response_body)

      tool.execute(query: 'test', num_results: 15)
    end

    it 'passes num_results through when 10 or less' do
      stub_request(:get, 'https://www.googleapis.com/customsearch/v1')
        .with(query: hash_including('num' => '3'))
        .to_return(status: 200, body: google_response_body)

      tool.execute(query: 'test', num_results: 3)
    end
  end

  describe 'result formatting' do
    before do
      allow(tool).to receive(:detect_provider).and_return('duckduckgo')
    end

    it 'formats results with query, provider, numbered titles, URLs, and snippets' do
      results = [
        { title: 'First', url: 'https://first.com', snippet: 'First snippet' },
        { title: 'Second', url: 'https://second.com', snippet: 'Second snippet' }
      ]
      allow(tool).to receive(:search_duckduckgo).and_return(results)

      output = tool.execute(query: 'my query')

      expect(output).to include('Search results for: my query (via duckduckgo)')
      expect(output).to include('1. First')
      expect(output).to include('   URL: https://first.com')
      expect(output).to include('   First snippet')
      expect(output).to include('2. Second')
      expect(output).to include('   URL: https://second.com')
      expect(output).to include('   Second snippet')
    end

    it 'returns "No results found" for empty results' do
      allow(tool).to receive(:search_duckduckgo).and_return([])

      result = tool.execute(query: 'nothing')

      expect(result).to eq('No results found for: nothing')
    end

    it 'omits URL line when URL is empty' do
      results = [{ title: 'AI Answer', url: '', snippet: 'An answer' }]
      allow(tool).to receive(:search_duckduckgo).and_return(results)

      output = tool.execute(query: 'test')

      expect(output).to include('1. AI Answer')
      expect(output).not_to include('URL:')
      expect(output).to include('An answer')
    end

    it 'omits snippet line when snippet is empty' do
      results = [{ title: 'No Snippet', url: 'https://example.com', snippet: '' }]
      allow(tool).to receive(:search_duckduckgo).and_return(results)

      output = tool.execute(query: 'test')

      expect(output).to include('1. No Snippet')
      expect(output).to include('URL: https://example.com')
      # There should be no indented snippet line after the URL line
      expect(output).not_to match(/URL: https:\/\/example\.com\n   \S/)
    end
  end

  describe 'error handling' do
    it 'returns error string instead of raising on StandardError' do
      allow(tool).to receive(:detect_provider).and_return('duckduckgo')
      allow(tool).to receive(:search_duckduckgo).and_raise(StandardError.new('connection refused'))

      result = tool.execute(query: 'test')

      expect(result).to include('Search failed')
      expect(result).to include('connection refused')
      expect(result).to include('duckduckgo')
    end

    it 'includes provider name in error message' do
      ENV['BRAVE_API_KEY'] = 'test-key'
      stub_request(:get, /api\.search\.brave\.com/)
        .to_return(status: 500, body: 'invalid json{{{')

      result = tool.execute(query: 'test')

      expect(result).to include('Search failed (brave)')
    end
  end

  describe 'class-level attributes' do
    it 'has the correct tool name' do
      expect(described_class.tool_name).to eq('web_search')
    end

    it 'has a description' do
      expect(described_class.description).not_to be_empty
    end

    it 'has required query parameter' do
      expect(described_class.parameters[:query][:required]).to be true
      expect(described_class.parameters[:query][:type]).to eq(:string)
    end

    it 'has optional num_results parameter with default 5' do
      expect(described_class.parameters[:num_results][:required]).to be false
      expect(described_class.parameters[:num_results][:default]).to eq(5)
    end

    it 'has external risk level' do
      expect(described_class.risk_level).to eq(:external)
    end

    it 'requires confirmation' do
      expect(described_class.requires_confirmation?).to be true
    end
  end

  describe 'strip_html' do
    it 'strips HTML tags and decodes entities' do
      html = '<b>Hello</b> &amp; <i>World</i> &lt;test&gt; &quot;quoted&quot; &#39;apos&#39; &nbsp;spaced'
      result = tool.send(:strip_html, html)
      expect(result).to eq("Hello & World <test> \"quoted\" 'apos' spaced")
    end

    it 'returns empty string for nil input' do
      expect(tool.send(:strip_html, nil)).to eq('')
    end

    it 'collapses multiple whitespace into single space' do
      expect(tool.send(:strip_html, 'hello    world')).to eq('hello world')
    end
  end
end
