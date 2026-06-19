# frozen_string_literal: true

require 'spec_helper'

RSpec.describe RubynCode::CLI::Commands::Goal do
  subject(:command) { described_class.new }

  let(:hook_registry) { RubynCode::Hooks::Registry.new }
  let(:renderer)      { instance_double('Renderer', info: nil, error: nil) }
  let(:llm_client)    { instance_double(RubynCode::LLM::Client) }
  let(:ctx) do
    instance_double(
      RubynCode::CLI::Commands::Context,
      hook_registry: hook_registry,
      renderer: renderer,
      llm_client: llm_client,
      send_message: nil
    )
  end

  def goal_hooks
    hook_registry.hooks_for(:stop).select { |h| h.is_a?(RubynCode::Hooks::GoalHook) }
  end

  describe '.command_name' do
    it { expect(described_class.command_name).to eq('/goal') }
  end

  describe '#execute' do
    it 'registers an active goal hook on the :stop event' do
      command.execute(%w[make the build green], ctx)

      expect(goal_hooks.size).to eq(1)
      expect(goal_hooks.first).to be_active
      expect(goal_hooks.first.condition).to eq('make the build green')
    end

    it 'kicks off work toward the goal' do
      command.execute(%w[make the build green], ctx)
      expect(ctx).to have_received(:send_message).with(/make the build green/i)
    end

    it 'clears the active goal with /goal clear' do
      command.execute(%w[do the thing], ctx)
      command.execute(['clear'], ctx)

      expect(goal_hooks).to all(satisfy { |h| !h.active? })
      expect(renderer).to have_received(:info).with(/cleared/i)
    end

    it 'reports when there is no goal to clear' do
      command.execute(['clear'], ctx)
      expect(renderer).to have_received(:info).with(/no active goal/i)
    end

    it 'replaces an existing goal rather than stacking active ones' do
      command.execute(['first goal'], ctx)
      command.execute(['second goal'], ctx)

      active = goal_hooks.select(&:active?)
      expect(active.size).to eq(1)
      expect(active.first.condition).to eq('second goal')
    end

    it 'shows the active goal when called with no args' do
      command.execute(['ship the feature'], ctx)
      command.execute([], ctx)

      expect(renderer).to have_received(:info).with(/Active goal: ship the feature/)
    end

    it 'shows guidance when called with no args and no goal' do
      command.execute([], ctx)
      expect(renderer).to have_received(:info).with(/no active goal/i)
    end
  end
end
