# frozen_string_literal: true

require 'tmpdir'
require 'fileutils'

RSpec.describe RubynCode::Tools::CodeGraph do
  let(:tmpdir) { Dir.mktmpdir }
  let(:tool) { described_class.new(project_root: tmpdir) }

  after { FileUtils.remove_entry(tmpdir) }

  before do
    debug_mod = Module.new do
      def self.warn(msg); end
    end
    stub_const('RubynCode::Debug', debug_mod)

    dir = File.join(tmpdir, 'app', 'services')
    FileUtils.mkdir_p(dir)
    File.write(File.join(dir, 'billing.rb'), <<~RUBY)
      class Billing
        def charge
          audit
        end

        def audit
          :ok
        end
      end
    RUBY
  end

  it 'returns verbatim line-numbered source for a matched method' do
    output = tool.execute(query: 'charge')
    expect(output).to include('## Billing#charge (app/services/billing.rb:2)')
    expect(output).to include('2|   def charge')
    expect(output).to include('3|     audit')
  end

  it 'lists callers and callees from the call graph' do
    output = tool.execute(query: 'audit')
    expect(output).to include('Called by: charge (app/services/billing.rb:3)')

    output = tool.execute(query: 'charge')
    expect(output).to include('Calls: audit')
  end

  it 'ranks exact name matches above partial matches' do
    output = tool.execute(query: 'charge', max_symbols: 1)
    expect(output).to include('Billing#charge')
  end

  it 'reports when nothing matches' do
    expect(tool.execute(query: 'nonexistent_thing')).to include('No symbols matching')
  end

  it 'is exposed by default' do
    RubynCode::Tools::Registry.register(described_class)
    expect(RubynCode::Tools::Registry.get('code_graph')).to eq(described_class)
    expect(RubynCode::Agent::DynamicToolSchema::BASE_TOOLS).to include('code_graph')
  end
end
