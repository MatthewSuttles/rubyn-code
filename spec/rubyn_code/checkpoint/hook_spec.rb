# frozen_string_literal: true

require 'spec_helper'

RSpec.describe RubynCode::Checkpoint::Hook do
  let(:manager) { instance_double(RubynCode::Checkpoint::Manager, record_file: nil) }
  subject(:hook) { described_class.new(manager: manager) }

  it 'records the file path for a mutating tool' do
    hook.call(tool_name: 'write_file', tool_input: { path: 'lib/foo.rb' })
    expect(manager).to have_received(:record_file).with('lib/foo.rb')
  end

  it 'handles string-keyed tool input' do
    hook.call(tool_name: 'edit_file', tool_input: { 'path' => 'a.rb' })
    expect(manager).to have_received(:record_file).with('a.rb')
  end

  it 'ignores non-mutating tools' do
    hook.call(tool_name: 'read_file', tool_input: { path: 'a.rb' })
    expect(manager).not_to have_received(:record_file)
  end

  it 'never returns a deny decision' do
    expect(hook.call(tool_name: 'write_file', tool_input: { path: 'a.rb' })).to be_nil
  end
end
