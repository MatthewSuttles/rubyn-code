# frozen_string_literal: true

require "spec_helper"

RSpec.describe RubynCode::Tools::Executor do
  let(:fake_tool) do
    Class.new(RubynCode::Tools::Base) do
      const_set(:TOOL_NAME, "fake_exec_tool")
      const_set(:DESCRIPTION, "Fake")
      const_set(:PARAMETERS, {}.freeze)
      const_set(:RISK_LEVEL, :read)

      def execute(**_params)
        "tool output"
      end
    end
  end

  before do
    RubynCode::Tools::Registry.reset!
    RubynCode::Tools::Registry.register(fake_tool)
  end

  after { RubynCode::Tools::Registry.reset! }

  describe "#execute" do
    it "returns the tool output" do
      with_temp_project do |dir|
        executor = described_class.new(project_root: dir)
        result = executor.execute("fake_exec_tool", {})
        expect(result).to eq("tool output")
      end
    end

    it "handles unknown tools gracefully" do
      with_temp_project do |dir|
        executor = described_class.new(project_root: dir)
        result = executor.execute("nonexistent", {})
        expect(result).to include("Tool error")
      end
    end

    it "handles execution errors gracefully" do
      error_tool = Class.new(RubynCode::Tools::Base) do
        const_set(:TOOL_NAME, "error_tool")
        const_set(:DESCRIPTION, "Errors")
        const_set(:PARAMETERS, {}.freeze)
        const_set(:RISK_LEVEL, :read)

        def execute(**_params)
          raise StandardError, "boom"
        end
      end
      RubynCode::Tools::Registry.register(error_tool)

      with_temp_project do |dir|
        executor = described_class.new(project_root: dir)
        result = executor.execute("error_tool", {})
        expect(result).to include("Unexpected error")
        expect(result).to include("boom")
      end
    end

    it "truncates long output" do
      verbose_tool = Class.new(RubynCode::Tools::Base) do
        const_set(:TOOL_NAME, "verbose_tool")
        const_set(:DESCRIPTION, "Verbose")
        const_set(:PARAMETERS, {}.freeze)
        const_set(:RISK_LEVEL, :read)

        def execute(**_params)
          "x" * 100_000
        end
      end
      RubynCode::Tools::Registry.register(verbose_tool)

      with_temp_project do |dir|
        executor = described_class.new(project_root: dir)
        result = executor.execute("verbose_tool", {})
        expect(result.length).to be < 100_000
        expect(result).to include("truncated")
      end
    end
  end
end
