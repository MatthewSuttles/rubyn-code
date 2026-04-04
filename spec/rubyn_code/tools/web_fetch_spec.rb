# frozen_string_literal: true

require 'spec_helper'

RSpec.describe RubynCode::Tools::WebFetch do
  let(:tool) do
    with_temp_project do |dir|
      return described_class.new(project_root: dir)
    end
  end

  describe 'class-level attributes' do
    it 'has the correct tool name' do
      expect(described_class.tool_name).to eq('web_fetch')
    end

    it 'has a description' do
      expect(described_class.description).not_to be_empty
    end

    it 'has external risk level' do
      expect(described_class.risk_level).to eq(:external)
    end

    it 'requires confirmation' do
      expect(described_class.requires_confirmation?).to be true
    end

    it 'has required url parameter' do
      expect(described_class.parameters[:url][:required]).to be true
      expect(described_class.parameters[:url][:type]).to eq(:string)
    end

    it 'has optional max_length parameter with default 10_000' do
      expect(described_class.parameters[:max_length][:required]).to be false
      expect(described_class.parameters[:max_length][:default]).to eq(10_000)
    end
  end

  describe '#execute' do
    context 'happy path' do
      it 'fetches HTML, strips tags, and returns formatted text' do
        html = '<html><body><h1>Hello World</h1><p>This is a test page.</p></body></html>'
        stub_request(:get, 'https://example.com/page')
          .to_return(status: 200, body: html)

        result = tool.execute(url: 'https://example.com/page')

        expect(result).to include('Content from: https://example.com/page')
        expect(result).to include('=' * 60)
        expect(result).to include('Hello World')
        expect(result).to include('This is a test page.')
        expect(result).not_to include('<h1>')
        expect(result).not_to include('<p>')
      end
    end

    context 'with empty body' do
      it 'returns no readable text message for empty response body' do
        stub_request(:get, 'https://example.com/empty')
          .to_return(status: 200, body: '')

        result = tool.execute(url: 'https://example.com/empty')

        expect(result).to eq('Fetched https://example.com/empty but no readable text content was found.')
      end

      it 'returns no readable text message for HTML with only tags and whitespace' do
        html = '<html><head><title></title></head><body>   </body></html>'
        stub_request(:get, 'https://example.com/blank')
          .to_return(status: 200, body: html)

        result = tool.execute(url: 'https://example.com/blank')

        expect(result).to eq('Fetched https://example.com/blank but no readable text content was found.')
      end
    end

    context 'with max_length truncation' do
      it 'truncates content when it exceeds max_length' do
        long_text = 'A' * 2000
        html = "<html><body><p>#{long_text}</p></body></html>"
        stub_request(:get, 'https://example.com/long')
          .to_return(status: 200, body: html)

        result = tool.execute(url: 'https://example.com/long', max_length: 600)

        expect(result).to include('Content from: https://example.com/long')
        expect(result).to include('... [truncated at 600 characters]')
        expect(result.length).to be < 2000
      end
    end

    context 'with max_length clamping' do
      it 'clamps max_length below 500 up to 500' do
        text = 'B' * 1000
        html = "<html><body><p>#{text}</p></body></html>"
        stub_request(:get, 'https://example.com/clamp')
          .to_return(status: 200, body: html)

        result = tool.execute(url: 'https://example.com/clamp', max_length: 100)

        # Should use 500 as the effective max_length
        expect(result).to include('... [truncated at 500 characters]')
      end

      it 'clamps max_length above 100_000 down to 100_000' do
        # We just verify the code doesn't error; content fits within 100k
        html = '<html><body><p>Short text</p></body></html>'
        stub_request(:get, 'https://example.com/bigmax')
          .to_return(status: 200, body: html)

        result = tool.execute(url: 'https://example.com/bigmax', max_length: 200_000)

        expect(result).to include('Short text')
        expect(result).not_to include('truncated')
      end

      it 'converts max_length to integer' do
        html = '<html><body><p>Some content</p></body></html>'
        stub_request(:get, 'https://example.com/convert')
          .to_return(status: 200, body: html)

        # Passes a string — should be converted via to_i
        result = tool.execute(url: 'https://example.com/convert', max_length: '5000')

        expect(result).to include('Some content')
      end
    end
  end

  describe 'URL validation' do
    it 'raises Error for URLs not starting with http:// or https://' do
      expect {
        tool.execute(url: 'ftp://example.com')
      }.to raise_error(RubynCode::Error, /Invalid URL.*ftp:\/\/example\.com/)
    end

    it 'raises Error for bare domain names' do
      expect {
        tool.execute(url: 'example.com')
      }.to raise_error(RubynCode::Error, /Invalid URL/)
    end

    it 'raises Error for empty string' do
      expect {
        tool.execute(url: '')
      }.to raise_error(RubynCode::Error, /Invalid URL/)
    end

    it 'accepts http:// URLs' do
      stub_request(:get, 'http://example.com')
        .to_return(status: 200, body: '<p>OK</p>')

      result = tool.execute(url: 'http://example.com')

      expect(result).to include('Content from: http://example.com')
    end

    it 'accepts https:// URLs' do
      stub_request(:get, 'https://example.com')
        .to_return(status: 200, body: '<p>OK</p>')

      result = tool.execute(url: 'https://example.com')

      expect(result).to include('Content from: https://example.com')
    end

    it 'accepts URLs with uppercase scheme (case-insensitive validation)' do
      # Validate that the regex is case-insensitive by calling the private method directly
      expect {
        tool.send(:validate_url!, 'HTTP://example.com')
      }.not_to raise_error

      expect {
        tool.send(:validate_url!, 'HTTPS://example.com')
      }.not_to raise_error
    end
  end

  describe 'redirect handling' do
    it 'follows a single redirect' do
      stub_request(:get, 'https://example.com/old')
        .to_return(status: 301, headers: { 'Location' => 'https://example.com/new' })
      stub_request(:get, 'https://example.com/new')
        .to_return(status: 200, body: '<p>New page</p>')

      result = tool.execute(url: 'https://example.com/old')

      expect(result).to include('New page')
    end

    it 'follows multiple redirects in sequence' do
      stub_request(:get, 'https://example.com/a')
        .to_return(status: 302, headers: { 'Location' => 'https://example.com/b' })
      stub_request(:get, 'https://example.com/b')
        .to_return(status: 303, headers: { 'Location' => 'https://example.com/c' })
      stub_request(:get, 'https://example.com/c')
        .to_return(status: 200, body: '<p>Final destination</p>')

      result = tool.execute(url: 'https://example.com/a')

      expect(result).to include('Final destination')
    end

    it 'follows 307 and 308 redirects' do
      stub_request(:get, 'https://example.com/temp')
        .to_return(status: 307, headers: { 'Location' => 'https://example.com/perm' })
      stub_request(:get, 'https://example.com/perm')
        .to_return(status: 308, headers: { 'Location' => 'https://example.com/final' })
      stub_request(:get, 'https://example.com/final')
        .to_return(status: 200, body: '<p>Done</p>')

      result = tool.execute(url: 'https://example.com/temp')

      expect(result).to include('Done')
    end

    it 'raises Error after too many redirects' do
      (0..5).each do |i|
        stub_request(:get, "https://example.com/loop#{i}")
          .to_return(status: 301, headers: { 'Location' => "https://example.com/loop#{i + 1}" })
      end

      expect {
        tool.execute(url: 'https://example.com/loop0')
      }.to raise_error(RubynCode::Error, /Too many redirects/)
    end

    it 'raises Error when redirect has no Location header' do
      stub_request(:get, 'https://example.com/noloc')
        .to_return(status: 302, headers: {})

      expect {
        tool.execute(url: 'https://example.com/noloc')
      }.to raise_error(RubynCode::Error, /Redirect with no Location header/)
    end

    it 'resolves relative Location headers against the request URL' do
      stub_request(:get, 'https://example.com/dir/page')
        .to_return(status: 301, headers: { 'Location' => '/other/page' })
      stub_request(:get, 'https://example.com/other/page')
        .to_return(status: 200, body: '<p>Resolved</p>')

      result = tool.execute(url: 'https://example.com/dir/page')

      expect(result).to include('Resolved')
    end
  end

  describe 'HTTP error handling' do
    it 'raises Error for 404 status' do
      stub_request(:get, 'https://example.com/missing')
        .to_return(status: 404, body: 'Not Found')

      expect {
        tool.execute(url: 'https://example.com/missing')
      }.to raise_error(RubynCode::Error, /HTTP 404 fetching/)
    end

    it 'raises Error for 500 status' do
      stub_request(:get, 'https://example.com/error')
        .to_return(status: 500, body: 'Internal Server Error')

      expect {
        tool.execute(url: 'https://example.com/error')
      }.to raise_error(RubynCode::Error, /HTTP 500 fetching/)
    end
  end

  describe 'Faraday error handling' do
    it 'raises Error on Faraday::TimeoutError' do
      stub_request(:get, 'https://example.com/slow')
        .to_raise(Faraday::TimeoutError.new('execution expired'))

      expect {
        tool.execute(url: 'https://example.com/slow')
      }.to raise_error(RubynCode::Error, /Request timed out after 30 seconds/)
    end

    it 'raises Error on Faraday::ConnectionFailed' do
      stub_request(:get, 'https://example.com/down')
        .to_raise(Faraday::ConnectionFailed.new('Connection refused'))

      expect {
        tool.execute(url: 'https://example.com/down')
      }.to raise_error(RubynCode::Error, /Connection failed for.*Connection refused/)
    end

    it 'raises Error on generic Faraday::Error' do
      stub_request(:get, 'https://example.com/fail')
        .to_raise(Faraday::Error.new('Something went wrong'))

      expect {
        tool.execute(url: 'https://example.com/fail')
      }.to raise_error(RubynCode::Error, /Request failed for.*Something went wrong/)
    end
  end

  describe 'HTML to text conversion' do
    # Helper to access the private html_to_text method
    def html_to_text(html)
      tool.send(:html_to_text, html)
    end

    it 'strips script tags and their content' do
      html = '<p>Before</p><script>alert("xss")</script><p>After</p>'
      result = html_to_text(html)

      expect(result).to include('Before')
      expect(result).to include('After')
      expect(result).not_to include('alert')
      expect(result).not_to include('script')
    end

    it 'strips style tags and their content' do
      html = '<p>Visible</p><style>.hidden { display: none; }</style><p>Also visible</p>'
      result = html_to_text(html)

      expect(result).to include('Visible')
      expect(result).to include('Also visible')
      expect(result).not_to include('display')
      expect(result).not_to include('style')
    end

    it 'strips multiline script tags' do
      html = "<p>Before</p><script type=\"text/javascript\">\nvar x = 1;\nvar y = 2;\n</script><p>After</p>"
      result = html_to_text(html)

      expect(result).not_to include('var x')
      expect(result).to include('Before')
      expect(result).to include('After')
    end

    it 'converts br tags to newlines' do
      html = 'Line one<br>Line two<br/>Line three<br />'
      result = html_to_text(html)

      expect(result).to include("Line one\nLine two\nLine three")
    end

    it 'converts block element closing tags to newlines' do
      html = '<p>Paragraph</p><div>Division</div><h1>Heading</h1>'
      result = html_to_text(html)

      lines = result.split("\n").map(&:strip).reject(&:empty?)
      expect(lines).to include('Paragraph', 'Division', 'Heading')
    end

    it 'converts block element opening tags to newlines' do
      html = '<p>First</p><p>Second</p><div class="box">Third</div>'
      result = html_to_text(html)

      expect(result).to include('First')
      expect(result).to include('Second')
      expect(result).to include('Third')
    end

    it 'handles li, tr, blockquote, and pre elements' do
      html = '<li>Item</li><tr>Row</tr><blockquote>Quote</blockquote><pre>Code</pre>'
      result = html_to_text(html)

      lines = result.split("\n").map(&:strip).reject(&:empty?)
      expect(lines).to include('Item', 'Row', 'Quote', 'Code')
    end

    it 'handles h1 through h6' do
      html = '<h1>H1</h1><h2>H2</h2><h3>H3</h3><h4>H4</h4><h5>H5</h5><h6>H6</h6>'
      result = html_to_text(html)

      (1..6).each do |n|
        expect(result).to include("H#{n}")
      end
    end

    it 'strips all remaining HTML tags' do
      html = '<span>text</span><a href="url">link</a><em>emphasis</em><strong>bold</strong>'
      result = html_to_text(html)

      expect(result).to include('text', 'link', 'emphasis', 'bold')
      expect(result).not_to include('<', '>')
    end

    it 'decodes &amp; entity' do
      expect(html_to_text('Tom &amp; Jerry')).to include('Tom & Jerry')
    end

    it 'decodes &lt; and &gt; entities' do
      expect(html_to_text('&lt;tag&gt;')).to include('<tag>')
    end

    it 'decodes &quot; entity' do
      expect(html_to_text('&quot;quoted&quot;')).to include('"quoted"')
    end

    it 'decodes &#39; entity' do
      expect(html_to_text("it&#39;s")).to include("it's")
    end

    it 'decodes &nbsp; entity' do
      expect(html_to_text('hello&nbsp;world')).to include('hello world')
    end

    it 'decodes numeric character references' do
      # &#65; is 'A', &#8212; is em dash
      expect(html_to_text('&#65;')).to include('A')
      expect(html_to_text('&#8212;')).to include("\u2014")
    end

    it 'returns empty string for nil input' do
      expect(html_to_text(nil)).to eq('')
    end

    it 'returns empty string for empty input' do
      expect(html_to_text('')).to eq('')
    end
  end

  describe 'whitespace collapsing' do
    def collapse_whitespace(text)
      tool.send(:collapse_whitespace, text)
    end

    it 'collapses multiple spaces into one' do
      expect(collapse_whitespace('hello     world')).to eq('hello world')
    end

    it 'collapses tabs and mixed whitespace into single space' do
      expect(collapse_whitespace("hello\t\t  world")).to eq('hello world')
    end

    it 'preserves single newlines' do
      expect(collapse_whitespace("line one\nline two")).to eq("line one\nline two")
    end

    it 'collapses three or more newlines into two' do
      expect(collapse_whitespace("para one\n\n\n\npara two")).to eq("para one\n\npara two")
    end

    it 'strips leading and trailing whitespace' do
      expect(collapse_whitespace('  hello  ')).to eq('hello')
    end

    it 'does not collapse double newlines' do
      expect(collapse_whitespace("one\n\ntwo")).to eq("one\n\ntwo")
    end
  end
end
