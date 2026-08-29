# frozen_string_literal: true

require 'spec_helper'
require 'tmpdir'

RSpec.describe RubynCode::Tools::Wayfinder do
  around do |example|
    previous = ENV.fetch('RUBYN_HARNESS_CONTROL_FILE', nil)
    Dir.mktmpdir('rubyn-wayfinder') do |directory|
      @control_file = File.join(directory, 'harness-control.json')
      File.write(@control_file, JSON.generate(
                                  wayfinder: [{ map: { id: 9, title: 'Tenant boundaries', status: 'draft' },
                                                tickets: [{ id: 12, title: 'Choose storage' }] }]
                                ))
      ENV['RUBYN_HARNESS_CONTROL_FILE'] = @control_file
      example.run
    end
  ensure
    ENV['RUBYN_HARNESS_CONTROL_FILE'] = previous
  end

  subject(:tool) { described_class.new(project_root: File.dirname(@control_file)) }

  it 'lists and reads app-native maps' do
    expect(tool.execute(action: 'list_maps')).to include('map #9 Tenant boundaries')
    expect(tool.execute(action: 'get_map', map_id: '9')).to include('Choose storage')
  end

  it 'provides explicit map and node mutation actions for the host to apply' do
    expect(tool.execute(action: 'update_map', map_id: '9', destination: 'Isolation is proven'))
      .to eq('Requested update to Wayfinder map 9.')
    expect(tool.execute(action: 'create_node', map_id: '9', title: 'Test isolation', node_type: 'code'))
      .to include('Requested code node on Wayfinder map 9: Test isolation')
    expect(tool.execute(action: 'resolve_node', node_id: '12', resolution: 'Use schemas'))
      .to eq('Requested resolution of Wayfinder node 12.')
    expect(tool.execute(action: 'import_map', title: 'Existing map'))
      .to include('Requested imported Wayfinder map: Existing map')
  end

  it 'fails closed without the Harness control plane' do
    ENV.delete('RUBYN_HARNESS_CONTROL_FILE')
    expect { tool.execute(action: 'list_maps') }.to raise_error(RubynCode::Error, /not connected/)
  end
end
