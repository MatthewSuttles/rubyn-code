# frozen_string_literal: true

RSpec.describe RubynCode::CLI::Commands::Skill do
  subject(:command) { described_class.new }

  let(:ctx) do
    instance_double(
      RubynCode::CLI::Commands::Context,
      renderer: renderer,
      skill_loader: skill_loader,
      conversation: conversation
    )
  end
  let(:renderer) { instance_double('Renderer', info: nil, error: nil) }
  let(:conversation) { instance_double('Conversation', add_user_message: nil) }
  let(:catalog) do
    instance_double('Catalog', available: [
      { name: 'rspec', description: 'RSpec testing' },
      { name: 'factory-bot', description: 'FactoryBot gem' }
    ])
  end
  let(:skill_loader) { instance_double('SkillLoader', catalog: catalog, load: '# Skill content') }

  describe '.command_name' do
    it { expect(described_class.command_name).to eq('/skill') }
  end

  describe '#execute' do
    context 'with a skill name' do
      it 'loads the skill' do
        command.execute(['rspec'], ctx)
        expect(skill_loader).to have_received(:load).with('rspec')
      end

      it 'adds skill content to conversation' do
        command.execute(['rspec'], ctx)
        expect(conversation).to have_received(:add_user_message).with(/<skill>/)
      end

      it 'shows success message' do
        command.execute(['rspec'], ctx)
        expect(renderer).to have_received(:info).with(/Loaded skill: rspec/)
      end
    end

    context 'without arguments' do
      it 'lists available skills' do
        expect { command.execute([], ctx) }.to output(/rspec/).to_stdout
      end
    end

    context 'when skill not found' do
      before { allow(skill_loader).to receive(:load).and_raise(StandardError, 'not found') }

      it 'shows error message' do
        command.execute(['nonexistent'], ctx)
        expect(renderer).to have_received(:error).with(/not found/)
      end
    end
  end
end
