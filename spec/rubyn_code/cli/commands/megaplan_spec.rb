  # frozen_string_literal: true

RSpec.describe RubynCode::CLI::Commands::Megaplan do
  subject(:command) { described_class.new }

  let(:conversation) { instance_double('Conversation', add_user_message: nil) }
  let(:skill_loader) { instance_double('SkillLoader', load: '<megaplan skill body>') }
  let(:renderer) { instance_double('Renderer', info: nil, error: nil) }
  let(:ctx) do
    instance_double(
      RubynCode::CLI::Commands::Context,
      conversation: conversation,
      skill_loader: skill_loader,
      renderer: renderer,
      send_message: nil
    )
  end

  describe '.command_name' do
    it { expect(described_class.command_name).to eq('/megaplan') }
  end

  describe '.aliases' do
    it { expect(described_class.aliases).to include('/mega-plan') }
  end

  describe '#execute' do
    it 'loads the megaplan skill and adds it to the conversation' do
      command.execute([], ctx)
      expect(skill_loader).to have_received(:load).with('megaplan')
      expect(conversation).to have_received(:add_user_message).with(/<skill>/)
    end

    it 'sends a read-only interview kickoff prompt with no feature args' do
      command.execute([], ctx)
      expect(ctx).to have_received(:send_message)
        .with(/megaplan interview/i)
      expect(ctx).to have_received(:send_message)
        .with(/read-only/i)
      expect(ctx).to have_received(:send_message)
        .with(/ask one question at a time/i)
    end

    it 'includes the user-supplied feature in the prompt when provided' do
      command.execute(%w[add soft delete to posts], ctx)
      expect(ctx).to have_received(:send_message)
        .with(/add soft delete to posts/i)
    end

    it 'returns the set_plan_mode action so the REPL flips into read-only mode' do
      result = command.execute([], ctx)
      expect(result).to eq(action: :set_plan_mode, enabled: true)
    end

    it 'surfaces errors via the renderer instead of crashing the REPL' do
      allow(skill_loader).to receive(:load).and_raise(StandardError, 'skill missing')
      result = command.execute([], ctx)
      expect(renderer).to have_received(:error).with(/skill missing/)
      expect(result).to be_nil
    end
  end
end
