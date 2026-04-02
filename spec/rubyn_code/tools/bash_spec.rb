# frozen_string_literal: true

require "spec_helper"

RSpec.describe RubynCode::Tools::Bash do
  describe "#execute" do
    it "runs a command and captures output" do
      with_temp_project do |dir|
        tool = described_class.new(project_root: dir)
        result = tool.execute(command: "echo hello")
        expect(result).to include("hello")
      end
    end

    it "captures stderr" do
      with_temp_project do |dir|
        tool = described_class.new(project_root: dir)
        result = tool.execute(command: "echo oops >&2")
        expect(result).to include("STDERR")
        expect(result).to include("oops")
      end
    end

    it "reports non-zero exit codes" do
      with_temp_project do |dir|
        tool = described_class.new(project_root: dir)
        result = tool.execute(command: "exit 42")
        expect(result).to include("Exit code: 42")
      end
    end

    it "blocks dangerous commands" do
      with_temp_project do |dir|
        tool = described_class.new(project_root: dir)
        expect { tool.execute(command: "rm -rf / --no-preserve") }
          .to raise_error(RubynCode::PermissionDeniedError, /Blocked dangerous/)
      end
    end

    it "times out long-running commands" do
      with_temp_project do |dir|
        tool = described_class.new(project_root: dir)
        expect { tool.execute(command: "sleep 60", timeout: 1) }
          .to raise_error(RubynCode::Error, /timed out/)
      end
    end

    it "returns (no output) for silent commands" do
      with_temp_project do |dir|
        tool = described_class.new(project_root: dir)
        result = tool.execute(command: "true")
        expect(result).to eq("(no output)")
      end
    end
  end
end
