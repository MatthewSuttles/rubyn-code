# frozen_string_literal: true

require 'spec_helper'

# Force-load the Loop class which requires the handler module
RubynCode::Agent::Loop

RSpec.describe RubynCode::Agent::FeedbackHandler do
  include DBHelpers

  let(:host_class) do
    Class.new do
      include RubynCode::Agent::FeedbackHandler

      attr_accessor :project_root

      def initialize(project_root:)
        @project_root = project_root
      end

      # Expose private methods for testing
      public :check_user_feedback, :fetch_recent_instincts,
             :reinforce_instincts, :reinforce_top
    end
  end

  let(:project_root) { '/tmp/test-feedback-project' }
  subject(:handler) { host_class.new(project_root: project_root) }

  describe '#check_user_feedback' do
    context 'when project_root is nil' do
      let(:project_root) { nil }

      it 'returns immediately' do
        expect(handler.check_user_feedback('yes that fixed it')).to be_nil
      end
    end

    context 'when there are no recent instincts' do
      it 'returns without reinforcing' do
        db = setup_test_db
        allow(RubynCode::DB::Connection).to receive(:instance).and_return(db)
        db.execute('CREATE TABLE IF NOT EXISTS instincts (id TEXT, project_path TEXT, updated_at TEXT)')

        expect(RubynCode::Learning::InstinctMethods).not_to receive(:reinforce_in_db)
        handler.check_user_feedback('yes that fixed it')
      end
    end

    context 'when there are recent instincts and positive feedback' do
      it 'reinforces with helpful: true' do
        db = setup_test_db
        db.execute('CREATE TABLE IF NOT EXISTS instincts (id TEXT, project_path TEXT, updated_at TEXT, confidence REAL, decay_rate REAL, times_applied INTEGER, times_helpful INTEGER)')
        db.execute(
          'INSERT INTO instincts VALUES (?, ?, ?, ?, ?, ?, ?)',
          ['inst1', project_root, Time.now.utc.strftime('%Y-%m-%dT%H:%M:%SZ'), 0.5, 0.05, 0, 0]
        )
        allow(RubynCode::DB::Connection).to receive(:instance).and_return(db)

        expect(RubynCode::Learning::InstinctMethods).to receive(:reinforce_in_db)
          .with('inst1', db, helpful: true)

        handler.check_user_feedback('yes that fixed it')
      end
    end

    context 'when there are recent instincts and negative feedback' do
      it 'reinforces with helpful: false' do
        db = setup_test_db
        db.execute('CREATE TABLE IF NOT EXISTS instincts (id TEXT, project_path TEXT, updated_at TEXT, confidence REAL, decay_rate REAL, times_applied INTEGER, times_helpful INTEGER)')
        db.execute(
          'INSERT INTO instincts VALUES (?, ?, ?, ?, ?, ?, ?)',
          ['inst2', project_root, Time.now.utc.strftime('%Y-%m-%dT%H:%M:%SZ'), 0.5, 0.05, 0, 0]
        )
        allow(RubynCode::DB::Connection).to receive(:instance).and_return(db)

        expect(RubynCode::Learning::InstinctMethods).to receive(:reinforce_in_db)
          .with('inst2', db, helpful: false)

        handler.check_user_feedback('no, wrong approach')
      end
    end

    context 'when there is neutral feedback' do
      it 'does not reinforce any instincts' do
        db = setup_test_db
        db.execute('CREATE TABLE IF NOT EXISTS instincts (id TEXT, project_path TEXT, updated_at TEXT)')
        db.execute('INSERT INTO instincts VALUES (?, ?, ?)', ['inst3', project_root, Time.now.utc.strftime('%Y-%m-%dT%H:%M:%SZ')])
        allow(RubynCode::DB::Connection).to receive(:instance).and_return(db)

        expect(RubynCode::Learning::InstinctMethods).not_to receive(:reinforce_in_db)
        handler.check_user_feedback('can you also add a test?')
      end
    end

    context 'when DB raises an error' do
      it 'rescues silently' do
        allow(RubynCode::DB::Connection).to receive(:instance).and_raise(StandardError, 'db error')
        expect { handler.check_user_feedback('perfect') }.not_to raise_error
      end
    end
  end

  describe '#reinforce_instincts' do
    let(:recent_instincts) { [{ 'id' => 'i1' }, { 'id' => 'i2' }, { 'id' => 'i3' }] }

    context 'with positive patterns' do
      %w[perfect thanks great exactly correct].each do |word|
        it "recognizes '#{word}' as positive feedback" do
          db = setup_test_db
          allow(RubynCode::DB::Connection).to receive(:instance).and_return(db)
          allow(RubynCode::Learning::InstinctMethods).to receive(:reinforce_in_db)

          handler.reinforce_instincts(word, recent_instincts)

          expect(RubynCode::Learning::InstinctMethods).to have_received(:reinforce_in_db)
            .with('i1', db, helpful: true)
        end
      end
    end

    context 'with negative patterns' do
      ['wrong', "that's not right", 'incorrect'].each do |phrase|
        it "recognizes '#{phrase}' as negative feedback" do
          db = setup_test_db
          allow(RubynCode::DB::Connection).to receive(:instance).and_return(db)
          allow(RubynCode::Learning::InstinctMethods).to receive(:reinforce_in_db)

          handler.reinforce_instincts(phrase, recent_instincts)

          expect(RubynCode::Learning::InstinctMethods).to have_received(:reinforce_in_db)
            .with('i1', db, helpful: false)
        end
      end
    end

    context 'with neutral input' do
      it 'does not call reinforce_in_db' do
        expect(RubynCode::Learning::InstinctMethods).not_to receive(:reinforce_in_db)
        handler.reinforce_instincts('what about the database?', recent_instincts)
      end
    end
  end

  describe '#reinforce_top' do
    it 'reinforces only the first 2 instincts' do
      db = setup_test_db
      allow(RubynCode::DB::Connection).to receive(:instance).and_return(db)
      allow(RubynCode::Learning::InstinctMethods).to receive(:reinforce_in_db)

      instincts = [{ 'id' => 'a' }, { 'id' => 'b' }, { 'id' => 'c' }]
      handler.reinforce_top(instincts, helpful: true)

      expect(RubynCode::Learning::InstinctMethods).to have_received(:reinforce_in_db).exactly(2).times
      expect(RubynCode::Learning::InstinctMethods).to have_received(:reinforce_in_db).with('a', db, helpful: true)
      expect(RubynCode::Learning::InstinctMethods).to have_received(:reinforce_in_db).with('b', db, helpful: true)
    end

    it 'works with fewer than 2 instincts' do
      db = setup_test_db
      allow(RubynCode::DB::Connection).to receive(:instance).and_return(db)
      allow(RubynCode::Learning::InstinctMethods).to receive(:reinforce_in_db)

      instincts = [{ 'id' => 'only_one' }]
      handler.reinforce_top(instincts, helpful: false)

      expect(RubynCode::Learning::InstinctMethods).to have_received(:reinforce_in_db).once
      expect(RubynCode::Learning::InstinctMethods).to have_received(:reinforce_in_db).with('only_one', db, helpful: false)
    end
  end
end
