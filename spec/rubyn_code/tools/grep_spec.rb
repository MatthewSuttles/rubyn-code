# frozen_string_literal: true

require "spec_helper"

RSpec.describe RubynCode::Tools::Grep do
  describe "#execute" do
    it "finds matching content with file and line info" do
      with_temp_project do |dir|
        create_test_file(dir, "app.rb", "def hello\n  puts 'world'\nend\n")
        tool = described_class.new(project_root: dir)
        result = tool.execute(pattern: "hello")
        expect(result).to include("app.rb")
        expect(result).to include("1:")
        expect(result).to include("def hello")
      end
    end

    it "respects glob_filter" do
      with_temp_project do |dir|
        create_test_file(dir, "lib/foo.rb", "# match here")
        create_test_file(dir, "lib/foo.txt", "# match here too")
        tool = described_class.new(project_root: dir)
        result = tool.execute(pattern: "match", glob_filter: "**/*.rb")
        expect(result).to include("foo.rb")
        expect(result).not_to include("foo.txt")
      end
    end

    it "limits results to max_results" do
      with_temp_project do |dir|
        lines = (1..20).map { |i| "match line #{i}" }.join("\n")
        create_test_file(dir, "big.txt", lines)
        tool = described_class.new(project_root: dir)
        result = tool.execute(pattern: "match", max_results: 5)
        expect(result.lines.count).to eq(5)
      end
    end

    it "returns a no-matches message when nothing is found" do
      with_temp_project do |dir|
        create_test_file(dir, "empty.rb", "nothing relevant")
        tool = described_class.new(project_root: dir)
        result = tool.execute(pattern: "zzzzzzz")
        expect(result).to include("No matches found")
      end
    end
  end
end
