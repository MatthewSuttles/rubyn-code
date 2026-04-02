# frozen_string_literal: true

require "spec_helper"

RSpec.describe RubynCode::Tools::ReadFile do
  describe "#execute" do
    it "reads a file with line numbers" do
      with_temp_project do |dir|
        create_test_file(dir, "hello.txt", "line one\nline two\nline three\n")
        tool = described_class.new(project_root: dir)
        result = tool.execute(path: "hello.txt")
        expect(result).to include("1\tline one")
        expect(result).to include("2\tline two")
        expect(result).to include("3\tline three")
      end
    end

    it "respects offset and limit" do
      with_temp_project do |dir|
        content = (1..10).map { |i| "line #{i}\n" }.join
        create_test_file(dir, "numbers.txt", content)
        tool = described_class.new(project_root: dir)
        result = tool.execute(path: "numbers.txt", offset: 3, limit: 2)
        expect(result).to include("3\tline 3")
        expect(result).to include("4\tline 4")
        expect(result).not_to include("5\tline 5")
        expect(result).not_to include("2\tline 2")
      end
    end

    it "blocks path traversal" do
      with_temp_project do |dir|
        tool = described_class.new(project_root: dir)
        expect { tool.execute(path: "../../etc/passwd") }
          .to raise_error(RubynCode::PermissionDeniedError)
      end
    end

    it "handles missing files" do
      with_temp_project do |dir|
        tool = described_class.new(project_root: dir)
        expect { tool.execute(path: "nope.txt") }
          .to raise_error(RubynCode::Error, /not found/i)
      end
    end
  end
end
