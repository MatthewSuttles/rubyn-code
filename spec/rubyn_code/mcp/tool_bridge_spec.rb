# frozen_string_literal: true

require 'spec_helper'

RSpec.describe RubynCode::MCP::ToolBridge do
  let(:mcp_client) { instance_double('RubynCode::MCP::Client') }

  after do
    RubynCode::Tools::Registry.instance_variable_get(:@tools)&.delete_if { |k, _| k.start_with?('mcp_') }
  end

  describe '.bridge' do
    context 'when client.tools returns nil' do
      before { allow(mcp_client).to receive(:tools).and_return(nil) }

      it 'returns an empty array' do
        result = described_class.bridge(mcp_client)
        expect(result).to eq([])
      end
    end

    context 'when client.tools returns an empty array' do
      before { allow(mcp_client).to receive(:tools).and_return([]) }

      it 'returns an empty array' do
        result = described_class.bridge(mcp_client)
        expect(result).to eq([])
      end
    end

    context 'with tool definitions' do
      let(:tool_defs) do
        [
          {
            'name' => 'search',
            'description' => 'Search documents',
            'inputSchema' => {
              'properties' => {
                'query' => { 'type' => 'string', 'description' => 'Search query' },
                'limit' => { 'type' => 'integer', 'description' => 'Max results' }
              },
              'required' => ['query']
            }
          },
          {
            'name' => 'fetch',
            'description' => 'Fetch a URL',
            'inputSchema' => {
              'properties' => {
                'url' => { 'type' => 'string', 'description' => 'The URL' }
              },
              'required' => ['url']
            }
          }
        ]
      end

      before do
        allow(mcp_client).to receive(:tools).and_return(tool_defs)
        allow(mcp_client).to receive(:call_tool)
      end

      it 'creates a tool class for each tool definition' do
        result = described_class.bridge(mcp_client)
        expect(result.length).to eq(2)
        expect(result).to all(be < RubynCode::Tools::Base)
      end

      it 'names tools with "mcp_" prefix' do
        result = described_class.bridge(mcp_client)
        names = result.map(&:tool_name)
        expect(names).to contain_exactly('mcp_search', 'mcp_fetch')
      end

      it 'sets RISK_LEVEL to :external' do
        result = described_class.bridge(mcp_client)
        result.each do |klass|
          expect(klass.risk_level).to eq(:external)
        end
      end

      it 'sets REQUIRES_CONFIRMATION to true' do
        result = described_class.bridge(mcp_client)
        result.each do |klass|
          expect(klass.requires_confirmation?).to be true
        end
      end

      it 'registers tools with the Registry' do
        described_class.bridge(mcp_client)
        expect(RubynCode::Tools::Registry.get('mcp_search')).to be_a(Class)
        expect(RubynCode::Tools::Registry.get('mcp_fetch')).to be_a(Class)
      end

      it 'builds parameter definitions from JSON Schema' do
        result = described_class.bridge(mcp_client)
        search_klass = result.find { |k| k.tool_name == 'mcp_search' }
        params = search_klass.parameters

        expect(params[:query]).to eq({ type: :string, description: 'Search query', required: true })
        expect(params[:limit]).to eq({ type: :integer, description: 'Max results', required: false })
      end
    end

    context 'when tool definition has no description' do
      let(:tool_defs) do
        [{ 'name' => 'bare_tool', 'inputSchema' => {} }]
      end

      before do
        allow(mcp_client).to receive(:tools).and_return(tool_defs)
      end

      it 'uses a default description' do
        result = described_class.bridge(mcp_client)
        expect(result.first.description).to eq('MCP tool: bare_tool')
      end
    end

    context 'when tool definition has no inputSchema' do
      let(:tool_defs) do
        [{ 'name' => 'simple', 'description' => 'No params' }]
      end

      before do
        allow(mcp_client).to receive(:tools).and_return(tool_defs)
      end

      it 'creates a tool with empty parameters' do
        result = described_class.bridge(mcp_client)
        expect(result.first.parameters).to eq({})
      end
    end
  end

  describe 'tool name sanitization' do
    let(:tool_defs) do
      [{ 'name' => 'my-tool.v2/beta', 'description' => 'Weird name' }]
    end

    before do
      allow(mcp_client).to receive(:tools).and_return(tool_defs)
    end

    it 'replaces non-alphanumeric characters with underscores' do
      result = described_class.bridge(mcp_client)
      expect(result.first.tool_name).to eq('mcp_my_tool_v2_beta')
    end
  end

  describe 'execute delegation' do
    let(:tool_defs) do
      [
        {
          'name' => 'remote_action',
          'description' => 'Remote',
          'inputSchema' => {
            'properties' => {
              'input' => { 'type' => 'string', 'description' => 'Input value' }
            },
            'required' => ['input']
          }
        }
      ]
    end

    before do
      allow(mcp_client).to receive(:tools).and_return(tool_defs)
    end

    it 'delegates execute to client.call_tool with the remote name and params' do
      allow(mcp_client).to receive(:call_tool).with('remote_action', { input: 'hello' }).and_return('ok')

      klasses = described_class.bridge(mcp_client)
      tool = klasses.first.new(project_root: Dir.tmpdir)
      result = tool.execute(input: 'hello')

      expect(mcp_client).to have_received(:call_tool).with('remote_action', { input: 'hello' })
      expect(result).to eq('ok')
    end

    it 'formats text content from response' do
      response = {
        'content' => [
          { 'type' => 'text', 'text' => 'Hello world' },
          { 'type' => 'text', 'text' => 'Second line' }
        ]
      }
      allow(mcp_client).to receive(:call_tool).and_return(response)

      klasses = described_class.bridge(mcp_client)
      tool = klasses.first.new(project_root: Dir.tmpdir)
      result = tool.execute(input: 'test')

      expect(result).to eq("Hello world\nSecond line")
    end

    it 'formats image content from response' do
      response = {
        'content' => [
          { 'type' => 'image', 'mimeType' => 'image/png', 'data' => 'base64...' }
        ]
      }
      allow(mcp_client).to receive(:call_tool).and_return(response)

      klasses = described_class.bridge(mcp_client)
      tool = klasses.first.new(project_root: Dir.tmpdir)
      result = tool.execute(input: 'test')

      expect(result).to eq('[image: image/png]')
    end

    it 'formats resource content with text from response' do
      response = {
        'content' => [
          { 'type' => 'resource', 'resource' => { 'text' => 'Resource text', 'uri' => 'file:///foo' } }
        ]
      }
      allow(mcp_client).to receive(:call_tool).and_return(response)

      klasses = described_class.bridge(mcp_client)
      tool = klasses.first.new(project_root: Dir.tmpdir)
      result = tool.execute(input: 'test')

      expect(result).to eq('Resource text')
    end

    it 'formats resource content with URI fallback from response' do
      response = {
        'content' => [
          { 'type' => 'resource', 'resource' => { 'uri' => 'file:///bar' } }
        ]
      }
      allow(mcp_client).to receive(:call_tool).and_return(response)

      klasses = described_class.bridge(mcp_client)
      tool = klasses.first.new(project_root: Dir.tmpdir)
      result = tool.execute(input: 'test')

      expect(result).to eq('[resource: file:///bar]')
    end

    it 'handles string responses' do
      allow(mcp_client).to receive(:call_tool).and_return('plain string')

      klasses = described_class.bridge(mcp_client)
      tool = klasses.first.new(project_root: Dir.tmpdir)
      result = tool.execute(input: 'test')

      expect(result).to eq('plain string')
    end

    it 'handles Hash responses without content key' do
      allow(mcp_client).to receive(:call_tool).and_return({ 'status' => 'ok', 'value' => 42 })

      klasses = described_class.bridge(mcp_client)
      tool = klasses.first.new(project_root: Dir.tmpdir)
      result = tool.execute(input: 'test')

      parsed = JSON.parse(result)
      expect(parsed).to eq({ 'status' => 'ok', 'value' => 42 })
    end

    it 'handles non-string non-hash responses by calling to_s' do
      allow(mcp_client).to receive(:call_tool).and_return(12_345)

      klasses = described_class.bridge(mcp_client)
      tool = klasses.first.new(project_root: Dir.tmpdir)
      result = tool.execute(input: 'test')

      expect(result).to eq('12345')
    end
  end

  describe 'JSON Schema type mapping' do
    let(:tool_defs) do
      [
        {
          'name' => 'typed_tool',
          'description' => 'Typed',
          'inputSchema' => {
            'properties' => {
              'str' => { 'type' => 'string', 'description' => 'A string' },
              'num' => { 'type' => 'number', 'description' => 'A number' },
              'int' => { 'type' => 'integer', 'description' => 'An integer' },
              'bool' => { 'type' => 'boolean', 'description' => 'A boolean' },
              'arr' => { 'type' => 'array', 'description' => 'An array' },
              'obj' => { 'type' => 'object', 'description' => 'An object' },
              'unknown' => { 'type' => 'custom_thing', 'description' => 'Unknown type' }
            },
            'required' => %w[str]
          }
        }
      ]
    end

    before do
      allow(mcp_client).to receive(:tools).and_return(tool_defs)
    end

    it 'maps JSON Schema types to Ruby symbols correctly' do
      result = described_class.bridge(mcp_client)
      params = result.first.parameters

      expect(params[:str][:type]).to eq(:string)
      expect(params[:num][:type]).to eq(:number)
      expect(params[:int][:type]).to eq(:integer)
      expect(params[:bool][:type]).to eq(:boolean)
      expect(params[:arr][:type]).to eq(:array)
      expect(params[:obj][:type]).to eq(:object)
    end

    it 'defaults unknown types to :string' do
      result = described_class.bridge(mcp_client)
      params = result.first.parameters

      expect(params[:unknown][:type]).to eq(:string)
    end
  end

  describe '.build_parameters_from_schema (module-level)' do
    it 'builds parameters with all JSON Schema types' do
      schema = {
        'properties' => {
          'name' => { 'type' => 'string', 'description' => 'A name' },
          'count' => { 'type' => 'integer', 'description' => 'A count' },
          'ratio' => { 'type' => 'number', 'description' => 'A ratio' },
          'flag' => { 'type' => 'boolean', 'description' => 'A flag' },
          'items' => { 'type' => 'array', 'description' => 'Items list' },
          'config' => { 'type' => 'object', 'description' => 'Config obj' }
        },
        'required' => %w[name count]
      }

      result = described_class.send(:build_parameters_from_schema, schema)

      expect(result[:name]).to eq({ type: :string, description: 'A name', required: true })
      expect(result[:count]).to eq({ type: :integer, description: 'A count', required: true })
      expect(result[:ratio]).to eq({ type: :number, description: 'A ratio', required: false })
      expect(result[:flag]).to eq({ type: :boolean, description: 'A flag', required: false })
      expect(result[:items]).to eq({ type: :array, description: 'Items list', required: false })
      expect(result[:config]).to eq({ type: :object, description: 'Config obj', required: false })
    end

    it 'handles missing description by defaulting to empty string' do
      schema = {
        'properties' => {
          'bare' => { 'type' => 'string' }
        },
        'required' => []
      }

      result = described_class.send(:build_parameters_from_schema, schema)
      expect(result[:bare][:description]).to eq('')
    end

    it 'handles empty schema gracefully' do
      result = described_class.send(:build_parameters_from_schema, {})
      expect(result).to eq({})
    end
  end

  describe '.sanitize_name' do
    it 'replaces special characters with underscores' do
      expect(described_class.send(:sanitize_name, 'my-tool.v2/beta')).to eq('my_tool_v2_beta')
    end

    it 'collapses consecutive underscores' do
      expect(described_class.send(:sanitize_name, 'a--b..c')).to eq('a_b_c')
    end

    it 'lowercases the result' do
      expect(described_class.send(:sanitize_name, 'MyTool')).to eq('mytool')
    end
  end

  describe 'format_result with unknown content type' do
    let(:tool_defs) do
      [
        {
          'name' => 'unknown_content_tool',
          'description' => 'Unknown content',
          'inputSchema' => {
            'properties' => {
              'input' => { 'type' => 'string', 'description' => 'Input' }
            },
            'required' => ['input']
          }
        }
      ]
    end

    before do
      allow(mcp_client).to receive(:tools).and_return(tool_defs)
    end

    it 'falls back to to_s for unknown content block types' do
      response = {
        'content' => [
          { 'type' => 'unknown_fancy_type', 'data' => 'mystery' }
        ]
      }
      allow(mcp_client).to receive(:call_tool).and_return(response)

      klasses = described_class.bridge(mcp_client)
      tool = klasses.first.new(project_root: Dir.tmpdir)
      result = tool.execute(input: 'test')

      expect(result).to include('unknown_fancy_type')
    end
  end
end
