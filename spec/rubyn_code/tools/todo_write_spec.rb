# frozen_string_literal: true

require 'spec_helper'

RSpec.describe RubynCode::Tools::TodoWrite do
  subject(:tool) { described_class.new(project_root: Dir.pwd) }

  let(:store) { RubynCode::Tools::TodoStore.new }

  describe 'preamble' do
    it 'is registered under the name "TodoWrite"' do
      expect(RubynCode::Tools::Registry.get('TodoWrite')).to eq(described_class)
    end

    it 'declares a todos parameter' do
      params = described_class.const_get(:PARAMETERS)
      expect(params[:todos][:type]).to eq(:array)
      expect(params[:todos][:required]).to be(true)
    end

    it 'uses the canonical tool name' do
      expect(described_class.const_get(:TOOL_NAME)).to eq('TodoWrite')
    end
  end

  describe '#execute' do
    let(:todos) do
      [
        { 'content' => 'Add spec', 'status' => 'completed', 'active_form' => 'Adding spec' },
        { 'content' => 'Implement', 'status' => 'in_progress', 'active_form' => 'Implementing' },
        { 'content' => 'Write PR', 'status' => 'pending', 'active_form' => 'Writing PR' }
      ]
    end

    it 'returns a formatted checklist with markdown marks' do
      tool_with_store = described_class.new(project_root: Dir.pwd, store: store)
      out = tool_with_store.execute(todos: todos)
      expect(out).to include('[x] Add spec')
      expect(out).to include('[~] Implement')
      expect(out).to include('[ ] Write PR')
    end

    it 'persists the checklist to the shared store' do
      tool_with_store = described_class.new(project_root: Dir.pwd, store: store)
      tool_with_store.execute(todos: todos)
      expect(store.current.size).to eq(3)
      expect(store.current.last[:status]).to eq('pending')
    end

    it 'accepts symbol-keyed items with symbol status' do
      tool_with_store = described_class.new(project_root: Dir.pwd, store: store)
      out = tool_with_store.execute(todos: [{ content: 'thing', status: 'in_progress', active_form: 'doing thing' }])
      expect(out).to include('[~] thing')
      expect(store.current.first[:status]).to eq('in_progress')
    end

    it 'reports invalid status gracefully' do
      tool_with_store = described_class.new(project_root: Dir.pwd, store: store)
      out = tool_with_store.execute(todos: [{ 'content' => 'x', 'status' => 'bogus' }])
      expect(out).to start_with('TodoWrite:')
      expect(store.current).to be_empty
    end

    it 'reports missing content gracefully' do
      tool_with_store = described_class.new(project_root: Dir.pwd, store: store)
      out = tool_with_store.execute(todos: [{ 'status' => 'pending' }])
      expect(out).to start_with('TodoWrite:')
    end

    it 'returns "cleared" for an empty list and empties the store' do
      tool_with_store = described_class.new(project_root: Dir.pwd, store: store)
      tool_with_store.execute(todos: todos)
      out = tool_with_store.execute(todos: [])
      expect(out).to include('cleared')
      expect(store).to be_empty
    end

    it 'falls back to content for active_form when blank' do
      tool_with_store = described_class.new(project_root: Dir.pwd, store: store)
      tool_with_store.execute(todos: [{ 'content' => 'do it', 'status' => 'pending', 'active_form' => '' }])
      expect(store.current.first[:active_form]).to eq('do it')
    end
  end

  describe '.summarize' do
    it 'reports the item count' do
      expect(described_class.summarize('', { todos: [{ content: 'x' }, { content: 'y' }] }))
        .to eq('checklist: 2 items')
    end

    it 'reports "cleared" for zero items' do
      expect(described_class.summarize('', { todos: [] })).to eq('cleared checklist')
    end
  end
end

RSpec.describe RubynCode::Tools::TodoStore do
  subject(:store) { described_class.new }

  it 'starts empty' do
    expect(store).to be_empty
  end

  it 'stores items set by #replace' do
    store.replace([{ 'content' => 'a', 'status' => 'pending', 'active_form' => 'A' }])
    expect(store.current.first).to eq(content: 'a', status: 'pending', active_form: 'A')
  end

  it 'renders marks' do
    store.replace([{ 'content' => 'a', 'status' => 'completed', 'active_form' => 'A' }])
    expect(store.render).to include('☑ a')
    store.replace([{ 'content' => 'b', 'status' => 'in_progress', 'active_form' => 'B' }])
    expect(store.render).to include('[~] b')
    store.replace([{ 'content' => 'c', 'status' => 'pending', 'active_form' => 'C' }])
    expect(store.render).to include('[ ] c')
  end

  it 'clears' do
    store.replace([{ 'content' => 'a', 'status' => 'pending', 'active_form' => 'A' }])
    store.clear
    expect(store).to be_empty
  end

  it 'is thread-safe under concurrent replace' do
    threads = 10.times.map do |i|
      Thread.new do
        50.times { store.replace([{ 'content' => "t#{i}", 'status' => 'pending', 'active_form' => "T#{i}" }]) }
      end
    end
    threads.each(&:join)
    expect(store.current.size).to eq(1)
  end
end
