# frozen_string_literal: true

RSpec.describe RubynCode::CLI::Commands::Tasks do
  subject(:command) { described_class.new }

  let(:ctx) do
    instance_double(
      RubynCode::CLI::Commands::Context,
      renderer: renderer,
      db: db
    )
  end
  let(:renderer) { instance_double('Renderer', info: nil) }
  let(:db) { double('DB') }

  describe '.command_name' do
    it { expect(described_class.command_name).to eq('/tasks') }
  end

  describe '#execute' do
    context 'when tasks exist' do
      let(:tasks) do
        [{ id: 'abc12345-6789', status: 'in_progress', title: 'Build feature' }]
      end

      before do
        task_manager = instance_double(RubynCode::Tasks::Manager, list: tasks)
        allow(RubynCode::Tasks::Manager).to receive(:new).with(db).and_return(task_manager)
      end

      it 'prints task list' do
        expect { command.execute([], ctx) }.to output(/Build feature/).to_stdout
      end
    end

    context 'when no tasks exist' do
      before do
        task_manager = instance_double(RubynCode::Tasks::Manager, list: [])
        allow(RubynCode::Tasks::Manager).to receive(:new).with(db).and_return(task_manager)
      end

      it 'shows info message' do
        command.execute([], ctx)
        expect(renderer).to have_received(:info).with('No tasks.')
      end
    end
  end
end
