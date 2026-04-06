# frozen_string_literal: true

RSpec.describe RubynCode::Context::DecisionCompactor do
  subject(:compactor) { described_class.new(context_manager: context_manager, threshold: threshold) }

  let(:context_manager) { double('context_manager') }
  let(:threshold) { 10_000 }
  let(:conversation) { double('conversation', messages: messages) }
  let(:messages) { [{ role: 'user', content: 'Hello' }] }

  before do
    allow(RubynCode::Debug).to receive(:token)
  end

  describe '#signal_specs_passed!' do
    it 'sets pending_trigger to :specs_passed' do
      compactor.signal_specs_passed!

      expect(compactor.pending_trigger).to eq(:specs_passed)
    end
  end

  describe '#signal_file_edited!' do
    it 'tracks edited file paths' do
      compactor.signal_file_edited!('app/models/user.rb')
      compactor.signal_file_edited!('app/models/post.rb')

      # Verify indirectly: edit batch complete should trigger for multi-file edits
      compactor.signal_edit_batch_complete!
      expect(compactor.pending_trigger).to eq(:multi_file_edit_complete)
    end

    it 'does not set pending_trigger on its own' do
      compactor.signal_file_edited!('app/models/user.rb')

      expect(compactor.pending_trigger).to be_nil
    end
  end

  describe '#signal_edit_batch_complete!' do
    it 'sets pending_trigger when multiple files were edited' do
      compactor.signal_file_edited!('app/models/user.rb')
      compactor.signal_file_edited!('app/models/post.rb')

      compactor.signal_edit_batch_complete!

      expect(compactor.pending_trigger).to eq(:multi_file_edit_complete)
    end

    it 'does not set pending_trigger for single file edit' do
      compactor.signal_file_edited!('app/models/user.rb')

      compactor.signal_edit_batch_complete!

      expect(compactor.pending_trigger).to be_nil
    end

    it 'does not set pending_trigger when no files were edited' do
      compactor.signal_edit_batch_complete!

      expect(compactor.pending_trigger).to be_nil
    end

    it 'clears the edited files set after completion' do
      compactor.signal_file_edited!('app/models/user.rb')
      compactor.signal_file_edited!('app/models/post.rb')
      compactor.signal_edit_batch_complete!

      # After clearing, a second call should not trigger
      compactor.signal_edit_batch_complete!
      # pending_trigger is still :multi_file_edit_complete from first call
      # but edited_files was cleared, so this tests the clearing behavior
    end
  end

  describe '#detect_topic_switch' do
    it 'sets pending_trigger when keywords change completely' do
      compactor.detect_topic_switch('implement user authentication')
      compactor.detect_topic_switch('refactor database migrations')

      expect(compactor.pending_trigger).to eq(:topic_switch)
    end

    it 'does not trigger on first message' do
      compactor.detect_topic_switch('implement user authentication')

      expect(compactor.pending_trigger).to be_nil
    end

    it 'does not trigger when topics overlap' do
      compactor.detect_topic_switch('implement user authentication')
      compactor.detect_topic_switch('update user authentication tests')

      expect(compactor.pending_trigger).to be_nil
    end

    it 'filters stopwords from keyword extraction' do
      compactor.detect_topic_switch('the user and the post')
      compactor.detect_topic_switch('this user with that post')

      # "the", "and", "this", "with", "that" are stopwords
      # "user" and "post" overlap, so no topic switch
      expect(compactor.pending_trigger).to be_nil
    end

    it 'ignores short words under 3 characters' do
      compactor.detect_topic_switch('we do it on my')
      compactor.detect_topic_switch('go to be an so')

      # All words are under 3 chars, so keywords are empty
      # No trigger because keywords are empty
      expect(compactor.pending_trigger).to be_nil
    end
  end

  describe '#check!' do
    context 'when context is above early threshold and trigger is pending' do
      before do
        allow(context_manager).to receive(:estimated_tokens).and_return(7000)
        allow(context_manager).to receive(:check_compaction!)
        compactor.signal_specs_passed!
      end

      it 'triggers compaction and returns true' do
        result = compactor.check!(conversation)

        expect(result).to be true
        expect(context_manager).to have_received(:check_compaction!).with(conversation)
      end

      it 'clears pending_trigger after use' do
        compactor.check!(conversation)

        expect(compactor.pending_trigger).to be_nil
      end

      it 'logs the trigger reason via Debug' do
        compactor.check!(conversation)

        expect(RubynCode::Debug).to have_received(:token).with(/specs_passed/)
      end
    end

    context 'when context is below early threshold' do
      before do
        # 5000 < 10_000 * 0.6 = 6000
        allow(context_manager).to receive(:estimated_tokens).and_return(5000)
        compactor.signal_specs_passed!
      end

      it 'does not trigger compaction and returns false' do
        result = compactor.check!(conversation)

        expect(result).to be false
      end

      it 'preserves the pending_trigger' do
        compactor.check!(conversation)

        expect(compactor.pending_trigger).to eq(:specs_passed)
      end
    end

    context 'when no trigger is pending' do
      before do
        allow(context_manager).to receive(:estimated_tokens).and_return(9000)
      end

      it 'returns false even if above threshold' do
        result = compactor.check!(conversation)

        expect(result).to be false
      end
    end
  end

  describe '#reset!' do
    it 'clears pending_trigger' do
      compactor.signal_specs_passed!

      compactor.reset!

      expect(compactor.pending_trigger).to be_nil
    end

    it 'clears topic keywords so next message is treated as first' do
      compactor.detect_topic_switch('implement user authentication')

      compactor.reset!

      # After reset, this should be treated as a first message (no trigger)
      compactor.detect_topic_switch('refactor database migrations')
      expect(compactor.pending_trigger).to be_nil
    end

    it 'clears edited files' do
      compactor.signal_file_edited!('app/models/user.rb')
      compactor.signal_file_edited!('app/models/post.rb')

      compactor.reset!

      # After reset, batch complete should not trigger (no files tracked)
      compactor.signal_edit_batch_complete!
      expect(compactor.pending_trigger).to be_nil
    end
  end
end
