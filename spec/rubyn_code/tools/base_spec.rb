# frozen_string_literal: true

require "spec_helper"

RSpec.describe RubynCode::Tools::Base do
  let(:test_tool_class) do
    Class.new(described_class) do
      const_set(:TOOL_NAME, "test_tool")
      const_set(:DESCRIPTION, "A test tool")
      const_set(:PARAMETERS, {
        name: { type: :string, required: true, description: "A name" }
      }.freeze)
      const_set(:RISK_LEVEL, :read)
    end
  end

  describe "#safe_path" do
    it "allows a valid relative path within the project root" do
      with_temp_project do |dir|
        tool = test_tool_class.new(project_root: dir)
        result = tool.safe_path("lib/foo.rb")
        expect(result).to eq(File.join(dir, "lib/foo.rb"))
      end
    end

    it "blocks path traversal attempts" do
      with_temp_project do |dir|
        tool = test_tool_class.new(project_root: dir)
        expect { tool.safe_path("../../etc/passwd") }
          .to raise_error(RubynCode::PermissionDeniedError, /traversal denied/)
      end
    end

    it "allows absolute paths within the project root" do
      with_temp_project do |dir|
        tool = test_tool_class.new(project_root: dir)
        abs = File.join(dir, "src", "main.rb")
        expect(tool.safe_path(abs)).to eq(abs)
      end
    end

    it "blocks absolute paths outside the project root" do
      with_temp_project do |dir|
        tool = test_tool_class.new(project_root: dir)
        expect { tool.safe_path("/etc/passwd") }
          .to raise_error(RubynCode::PermissionDeniedError)
      end
    end
  end

  describe "#truncate" do
    it "returns short output unchanged" do
      with_temp_project do |dir|
        tool = test_tool_class.new(project_root: dir)
        expect(tool.truncate("short")).to eq("short")
      end
    end

    it "truncates output exceeding the max length" do
      with_temp_project do |dir|
        tool = test_tool_class.new(project_root: dir)
        long = "x" * 200
        result = tool.truncate(long, max: 100)
        expect(result.length).to be < 200
        expect(result).to include("truncated")
      end
    end
  end

  describe ".to_schema" do
    it "returns a hash with name, description, and input_schema" do
      schema = test_tool_class.to_schema
      expect(schema[:name]).to eq("test_tool")
      expect(schema[:description]).to eq("A test tool")
      expect(schema[:input_schema][:type]).to eq("object")
      expect(schema[:input_schema][:properties]).to have_key("name")
    end
  end
end
