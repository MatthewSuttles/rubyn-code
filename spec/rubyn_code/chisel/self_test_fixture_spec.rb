# frozen_string_literal: true

require 'spec_helper'
require 'open3'

# Guards the committed Chisel self-test fixture so its result stays consistent.
# If someone edits skills/self_test/fixtures/chisel_sample.rb, this spec (and
# skills/self_test/chisel_smoke.rb) must be updated in lock-step.
RSpec.describe 'Chisel self-test fixture' do
  fixture_dir = File.expand_path('../../../skills/self_test/fixtures', __dir__)

  let(:items) { RubynCode::Chisel::Debt.scan(fixture_dir) }

  it 'harvests exactly the three planted markers, in order' do
    expect(items.map { |i| [i.file, i.line, i.note] }).to eq(
      [
        ['chisel_sample.rb', 18, 'collapse this factory into a single build method'],
        ['chisel_sample.rb', 39, 'replace this class with Array#sum at the single call site'],
        ['chisel_sample.rb', 52, 'inline DEFAULTS[:retries] since there is only one reader']
      ]
    )
  end

  it 'ignores the decoys (string-literal and trailing-comment chisel: mentions)' do
    notes = items.map(&:note)
    expect(notes).to all(satisfy { |n| !n.include?('data, not a marker') && !n.include?('trailing') })
  end

  it 'runs the standalone smoke script green' do
    script = File.expand_path('../../../skills/self_test/chisel_smoke.rb', __dir__)
    output, error, status = Open3.capture3('bundle', 'exec', 'ruby', script)
    output = "#{output}#{error}"
    expect(status).to be_success, "smoke script failed:\n#{output}"
    expect(output).to include('CHISEL: PASS')
  end
end
