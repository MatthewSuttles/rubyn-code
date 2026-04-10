# frozen_string_literal: true

RSpec.describe RubynCode::Agent::DynamicToolSchema do
  describe '.active_tools' do
    it 'always includes BASE_TOOLS' do
      tools = described_class.active_tools
      described_class::BASE_TOOLS.each do |base_tool|
        expect(tools).to include(base_tool)
      end
    end

    it 'always includes interaction and memory tools' do
      tools = described_class.active_tools
      expect(tools).to include('ask_user', 'compact')
      expect(tools).to include('memory_search', 'memory_write')
    end

    it 'adds testing tools for :testing context' do
      tools = described_class.active_tools(task_context: :testing)
      expect(tools).to include('run_specs')
    end

    it 'adds git tools for :git context' do
      tools = described_class.active_tools(task_context: :git)
      expect(tools).to include('git_status', 'git_diff', 'git_log', 'git_commit')
    end

    it 'adds rails tools for :rails context' do
      tools = described_class.active_tools(task_context: :rails)
      expect(tools).to include('rails_generate', 'db_migrate')
    end

    it 'includes discovered tools' do
      discovered = Set.new(%w[custom_tool another_tool])
      tools = described_class.active_tools(discovered_tools: discovered)
      expect(tools).to include('custom_tool', 'another_tool')
    end

    it 'does not duplicate tools' do
      tools = described_class.active_tools(
        task_context: :testing,
        discovered_tools: Set.new(['read_file'])
      )
      expect(tools.count('read_file')).to eq(1)
    end

    it 'returns empty array extras for unknown context' do
      tools = described_class.active_tools(task_context: :nonexistent)
      expect(tools).to include(*described_class::BASE_TOOLS)
    end

    context 'with codebase_index' do
      let(:index) do
        idx = instance_double(RubynCode::Index::CodebaseIndex)
        allow(idx).to receive(:nodes).and_return([
                                                   { 'type' => 'model', 'name' => 'User',
                                                     'file' => 'app/models/user.rb' }
                                                 ])
        allow(idx).to receive(:edges).and_return([
                                                   { 'from' => 'spec/models/user_spec.rb',
                                                     'to' => 'app/models/user.rb', 'relationship' => 'tests' }
                                                 ])
        idx
      end

      it 'adds rails tools when message mentions a model name' do
        tools = described_class.active_tools(codebase_index: index, message: 'update the User model')
        expect(tools).to include('rails_generate', 'db_migrate')
      end

      it 'adds testing tools when message mentions a specced file' do
        tools = described_class.active_tools(codebase_index: index, message: 'fix the user module')
        expect(tools).to include('run_specs')
      end

      it 'works without an index' do
        tools = described_class.active_tools(codebase_index: nil, message: 'update the User model')
        expect(tools).not_to include('rails_generate')
      end

      it 'works without a message' do
        tools = described_class.active_tools(codebase_index: index, message: nil)
        expect(tools).to include(*described_class::BASE_TOOLS)
      end
    end
  end

  describe '.detect_context' do
    it 'returns :testing for test-related messages' do
      expect(described_class.detect_context('run the rspec suite')).to eq(:testing)
    end

    it 'returns :git for git-related messages' do
      expect(described_class.detect_context('commit these changes')).to eq(:git)
    end

    it 'returns :review for review-related messages' do
      expect(described_class.detect_context('review this PR')).to eq(:review)
    end

    it 'returns :rails for rails-related messages' do
      expect(described_class.detect_context('generate a scaffold')).to eq(:rails)
    end

    it 'returns :web for web-related messages' do
      expect(described_class.detect_context('search the web for docs')).to eq(:web)
    end

    it 'returns :explore for architecture-related messages' do
      expect(described_class.detect_context('explore the architecture')).to eq(:explore)
    end

    it 'returns :teams for team-related messages' do
      expect(described_class.detect_context('spawn a teammate')).to eq(:teams)
    end

    it 'returns nil for generic messages' do
      expect(described_class.detect_context('hello world')).to be_nil
    end

    context 'with codebase_index' do
      let(:index) do
        idx = instance_double(RubynCode::Index::CodebaseIndex)
        allow(idx).to receive(:nodes).and_return([
                                                   { 'type' => 'model', 'name' => 'User',
                                                     'file' => 'app/models/user.rb' },
                                                   { 'type' => 'model', 'name' => 'Post',
                                                     'file' => 'app/models/post.rb' }
                                                 ])
        allow(idx).to receive(:edges).and_return([
                                                   { 'from' => 'spec/models/user_spec.rb',
                                                     'to' => 'app/models/user.rb', 'relationship' => 'tests' }
                                                 ])
        idx
      end

      it 'returns :rails when message mentions a model name' do
        result = described_class.detect_context('update the User model', codebase_index: index)
        expect(result).to eq(:rails)
      end

      it 'returns :testing when message mentions a specced file' do
        idx = instance_double(RubynCode::Index::CodebaseIndex)
        allow(idx).to receive(:nodes).and_return([])
        allow(idx).to receive(:edges).and_return([
                                                   { 'from' => 'spec/models/user_spec.rb',
                                                     'to' => 'app/models/user.rb', 'relationship' => 'tests' }
                                                 ])
        result = described_class.detect_context('fix the user module', codebase_index: idx)
        expect(result).to eq(:testing)
      end

      it 'still prefers keyword detection over index' do
        result = described_class.detect_context('commit the User changes', codebase_index: index)
        expect(result).to eq(:git)
      end

      it 'returns nil when index has no matches' do
        result = described_class.detect_context('hello world', codebase_index: index)
        expect(result).to be_nil
      end
    end
  end

  describe '.detect_index_contexts' do
    let(:index) do
      idx = instance_double(RubynCode::Index::CodebaseIndex)
      allow(idx).to receive(:nodes).and_return([
                                                 { 'type' => 'model', 'name' => 'User',
                                                   'file' => 'app/models/user.rb' },
                                                 { 'type' => 'controller', 'name' => 'PostsController',
                                                   'file' => 'app/controllers/posts_controller.rb' }
                                               ])
      allow(idx).to receive(:edges).and_return([
                                                 { 'from' => 'spec/models/user_spec.rb', 'to' => 'app/models/user.rb',
                                                   'relationship' => 'tests' }
                                               ])
      idx
    end

    it 'returns :rails when message mentions a model' do
      result = described_class.detect_index_contexts('refactor User validation', index)
      expect(result).to include(:rails)
    end

    it 'returns :testing when message mentions a specced file' do
      result = described_class.detect_index_contexts('fix the user bug', index)
      expect(result).to include(:testing)
    end

    it 'returns both :rails and :testing when both match' do
      result = described_class.detect_index_contexts('User model has a user bug', index)
      expect(result).to include(:rails, :testing)
    end

    it 'returns empty array when nothing matches' do
      result = described_class.detect_index_contexts('hello world', index)
      expect(result).to be_empty
    end

    it 'returns empty array when index is nil' do
      result = described_class.detect_index_contexts('hello', nil)
      expect(result).to be_empty
    end

    it 'returns empty array on error' do
      bad_index = instance_double(RubynCode::Index::CodebaseIndex)
      allow(bad_index).to receive(:nodes).and_raise(StandardError, 'boom')
      result = described_class.detect_index_contexts('User', bad_index)
      expect(result).to be_empty
    end
  end

  describe '.filter' do
    let(:all_definitions) do
      [
        { name: 'read_file', description: 'Read a file' },
        { name: 'write_file', description: 'Write a file' },
        { name: 'run_specs', description: 'Run specs' },
        { name: 'git_commit', description: 'Commit' }
      ]
    end

    it 'removes non-active tools from definitions' do
      result = described_class.filter(all_definitions, active_names: %w[read_file run_specs])
      expect(result.size).to eq(2)
      expect(result.map { |d| d[:name] }).to contain_exactly('read_file', 'run_specs')
    end

    it 'returns empty array when no tools match' do
      result = described_class.filter(all_definitions, active_names: %w[nonexistent])
      expect(result).to be_empty
    end

    it 'handles string-keyed definitions' do
      defs = [{ 'name' => 'read_file', 'description' => 'Read' }]
      result = described_class.filter(defs, active_names: %w[read_file])
      expect(result.size).to eq(1)
    end
  end
end
