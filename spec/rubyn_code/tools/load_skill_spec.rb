# frozen_string_literal: true

require 'spec_helper'

RSpec.describe RubynCode::Tools::LoadSkill do
  let(:project_root) { '/tmp/test_project' }

  def build_tool(skill_loader:)
    described_class.new(project_root: project_root, skill_loader: skill_loader)
  end

  describe '#execute' do
    context 'with an injected skill_loader' do
      let(:loader) do
        obj = Object.new
        obj.define_singleton_method(:load) do |name|
          "Loaded skill: #{name}"
        end
        obj
      end

      it 'delegates to skill_loader.load' do
        tool = build_tool(skill_loader: loader)
        result = tool.execute(name: 'rails-testing')

        expect(result).to eq('Loaded skill: rails-testing')
      end

      it 'passes name through to the loader' do
        received_name = nil
        tracking_loader = Object.new
        tracking_loader.define_singleton_method(:load) do |name|
          received_name = name
          'ok'
        end

        tool = build_tool(skill_loader: tracking_loader)
        tool.execute(name: 'deploy-checklist')

        expect(received_name).to eq('deploy-checklist')
      end
    end
  end

  describe '.tool_name' do
    it 'returns load_skill' do
      expect(described_class.tool_name).to eq('load_skill')
    end
  end
end
