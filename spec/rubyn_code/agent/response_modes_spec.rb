# frozen_string_literal: true

RSpec.describe RubynCode::Agent::ResponseModes do
  describe '.detect' do
    it 'returns :implementing for "create a new model"' do
      expect(described_class.detect('create a new model')).to eq(:implementing)
    end

    it 'returns :debugging for "fix this error"' do
      expect(described_class.detect('fix this error')).to eq(:debugging)
    end

    it 'returns :reviewing for "review this PR"' do
      expect(described_class.detect('review this PR')).to eq(:reviewing)
    end

    it 'returns :testing for messages about specs' do
      expect(described_class.detect('run the rspec suite')).to eq(:testing)
    end

    it 'returns :exploring for "where is the user model"' do
      expect(described_class.detect('where is the user model')).to eq(:exploring)
    end

    it 'returns :explaining for "explain how this works"' do
      expect(described_class.detect('explain how this works')).to eq(:explaining)
    end

    it 'returns :chatting as default for unrecognized input' do
      expect(described_class.detect('hello there')).to eq(:chatting)
    end

    context 'when tool_calls are provided and message is generic' do
      it 'detects from the last tool call' do
        result = described_class.detect('do something', tool_calls: [{ name: 'run_specs' }])
        expect(result).to eq(:testing)
      end
    end
  end

  describe '.detect_from_tool' do
    it 'returns :testing for run_specs' do
      result = described_class.send(:detect_from_tool, { name: 'run_specs' })
      expect(result).to eq(:testing)
    end

    it 'returns :implementing for write_file' do
      result = described_class.send(:detect_from_tool, { name: 'write_file' })
      expect(result).to eq(:implementing)
    end

    it 'returns :implementing for edit_file' do
      result = described_class.send(:detect_from_tool, { name: 'edit_file' })
      expect(result).to eq(:implementing)
    end

    it 'returns :exploring for grep' do
      result = described_class.send(:detect_from_tool, { name: 'grep' })
      expect(result).to eq(:exploring)
    end

    it 'returns :exploring for glob' do
      result = described_class.send(:detect_from_tool, { name: 'glob' })
      expect(result).to eq(:exploring)
    end

    it 'returns :reviewing for review_pr' do
      result = described_class.send(:detect_from_tool, { name: 'review_pr' })
      expect(result).to eq(:reviewing)
    end

    it 'returns :chatting for unknown tools' do
      result = described_class.send(:detect_from_tool, { name: 'unknown_tool' })
      expect(result).to eq(:chatting)
    end

    it 'handles string-keyed hashes' do
      result = described_class.send(:detect_from_tool, { 'name' => 'run_specs' })
      expect(result).to eq(:testing)
    end

    it 'handles plain string tool names' do
      result = described_class.send(:detect_from_tool, 'grep')
      expect(result).to eq(:exploring)
    end
  end

  describe '.instruction_for' do
    it 'returns formatted instruction text for a known mode' do
      result = described_class.instruction_for(:implementing)
      expect(result).to include('Response Mode: implementing')
      expect(result).to include('Write the code')
    end

    it 'returns instruction text for each defined mode' do
      described_class::MODES.each_key do |mode|
        result = described_class.instruction_for(mode)
        expect(result).to include('Response Mode:')
        expect(result).to include(described_class::MODES[mode][:instruction])
      end
    end

    it 'falls back to chatting for an unknown mode' do
      result = described_class.instruction_for(:nonexistent)
      expect(result).to include('Response Mode: chatting')
      expect(result).to include('Respond naturally and concisely')
    end
  end
end
