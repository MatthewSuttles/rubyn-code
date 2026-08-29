# frozen_string_literal: true

require 'spec_helper'
require 'tmpdir'

RSpec.describe RubynCode::Tools::HarnessTask do
  around do |example|
    previous = ENV.fetch('RUBYN_HARNESS_CONTROL_FILE', nil)
    Dir.mktmpdir('rubyn-harness-task') do |directory|
      @control_file = File.join(directory, 'harness-control.json')
      File.write(@control_file, JSON.generate(
                                  tasks: [{ id: 4, title: 'Add policy spec', status: 'planning',
                                            dependsOn: [2] }],
                                  todos: [{ id: 7, title: 'Confirm evidence', status: 'queued' }],
                                  wayfinder: [{ map: { id: 9, title: 'Tenant boundaries', status: 'draft' },
                                                tickets: [] }]
                                ))
      ENV['RUBYN_HARNESS_CONTROL_FILE'] = @control_file
      example.run
    end
  ensure
    ENV['RUBYN_HARNESS_CONTROL_FILE'] = previous
  end

  subject(:tool) { described_class.new(project_root: File.dirname(@control_file)) }

  it 'lists the host-owned task board with dependency context' do
    expect(tool.execute(kind: 'task', action: 'list')).to eq(
      '[planning] #4 Add policy spec (blocked by #2)'
    )
  end

  it 'acknowledges mutations for the host control plane to audit and apply' do
    result = tool.execute(kind: 'todo', action: 'create', title: 'Run focused specs')

    expect(result).to include('Requested shared todo: Run focused specs')
  end

  it 'exposes app-native Wayfinder maps and acknowledges node creation' do
    expect(tool.execute(kind: 'wayfinder', action: 'list')).to include('map #9 Tenant boundaries')

    result = tool.execute(kind: 'wayfinder', action: 'create_node', map_id: '9',
                          title: 'Choose isolation boundary', node_type: 'grill')
    expect(result).to include('Requested grill node on Wayfinder map 9')
  end

  it 'fails closed when the Harness control plane is not connected' do
    ENV.delete('RUBYN_HARNESS_CONTROL_FILE')

    expect { tool.execute(kind: 'task', action: 'list') }
      .to raise_error(RubynCode::Error, /not connected/)
  end
end
