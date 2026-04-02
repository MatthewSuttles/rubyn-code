# frozen_string_literal: true

require "spec_helper"

RSpec.describe RubynCode::Tools::WriteFile do
  describe "#execute" do
    it "writes content to a file" do
      with_temp_project do |dir|
        tool = described_class.new(project_root: dir)
        tool.execute(path: "output.txt", content: "hello world")
        expect(File.read(File.join(dir, "output.txt"))).to eq("hello world")
      end
    end

    it "creates parent directories" do
      with_temp_project do |dir|
        tool = described_class.new(project_root: dir)
        tool.execute(path: "deep/nested/dir/file.txt", content: "nested")
        expect(File.exist?(File.join(dir, "deep/nested/dir/file.txt"))).to be true
      end
    end

    it "returns the byte count in the result message" do
      with_temp_project do |dir|
        tool = described_class.new(project_root: dir)
        result = tool.execute(path: "f.txt", content: "12345")
        expect(result).to include("5 bytes")
      end
    end

    it "blocks path traversal" do
      with_temp_project do |dir|
        tool = described_class.new(project_root: dir)
        expect { tool.execute(path: "../../../tmp/evil.txt", content: "bad") }
          .to raise_error(RubynCode::PermissionDeniedError)
      end
    end
  end
end
