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
  let(:renderer) { instance_double('Renderer', info: nil, error: nil, warning: nil) }
  let(:conversation) { instance_double('Conversation', add_user_message: nil) }
  let(:catalog) do
    instance_double('Catalog',
                    list: %w[rspec factory-bot],
                    available: [
                      { name: 'rspec', description: 'Testing with RSpec' },
                      { name: 'factory-bot', description: 'Factory Bot patterns' }
                    ],
                    search: [],
                    by_category: [],
                    categories: %w[rails rspec])
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

    context 'with search sub-command' do
      it 'searches for matching skills' do
        allow(catalog).to receive(:search).with('test').and_return(
          [{ name: 'rspec', description: 'Testing with RSpec', relevance: 3 }]
        )

        expect { command.execute(%w[search test], ctx) }.to output(/rspec/).to_stdout
        expect(catalog).to have_received(:search).with('test')
      end

      it 'shows no results message when nothing matches' do
        allow(catalog).to receive(:search).with('zzzz').and_return([])
        command.execute(%w[search zzzz], ctx)
        expect(renderer).to have_received(:info).with(/No skills found/)
      end

      it 'shows usage when no search term provided' do
        command.execute(%w[search], ctx)
        expect(renderer).to have_received(:warning).with(/Usage/)
      end
    end

    context 'with list sub-command' do
      it 'lists categories when no category given' do
        expect { command.execute(%w[list], ctx) }.to output(/rails/).to_stdout
      end

      it 'lists skills in the specified category' do
        allow(catalog).to receive(:by_category).with('rails').and_return(
          [{ name: 'service-objects', description: 'Rails: Service Objects' }]
        )

        expect { command.execute(%w[list rails], ctx) }.to output(/service-objects/).to_stdout
        expect(catalog).to have_received(:by_category).with('rails')
      end

      it 'shows no results for empty category' do
        allow(catalog).to receive(:by_category).with('nonexistent').and_return([])
        command.execute(%w[list nonexistent], ctx)
        expect(renderer).to have_received(:info).with(/No skills found in category/)
      end
    end
  end
end
