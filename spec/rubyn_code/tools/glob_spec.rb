# frozen_string_literal: true

require "spec_helper"

RSpec.describe RubynCode::Tools::Glob do
  describe "#execute" do
    it "finds files matching a pattern" do
      with_temp_project do |dir|
        create_test_file(dir, "lib/foo.rb", "# foo")
        create_test_file(dir, "lib/bar.rb", "# bar")
        create_test_file(dir, "README.md", "# readme")

        tool = described_class.new(project_root: dir)
        result = tool.execute(pattern: "**/*.rb")
        expect(result).to include("lib/foo.rb")
        expect(result).to include("lib/bar.rb")
        expect(result).not_to include("README.md")
      end
    end

    it "returns relative paths" do
      with_temp_project do |dir|
        create_test_file(dir, "src/main.rb", "# main")
        tool = described_class.new(project_root: dir)
        result = tool.execute(pattern: "**/*.rb")
        expect(result).not_to include(dir)
        expect(result).to include("src/main.rb")
      end
    end

    it "returns empty string when no files match" do
      with_temp_project do |dir|
        tool = described_class.new(project_root: dir)
        result = tool.execute(pattern: "**/*.xyz")
        expect(result).to eq("")
      end
    end

    it "scopes search to a subdirectory when path is given" do
      with_temp_project do |dir|
        create_test_file(dir, "lib/a.rb", "a")
        create_test_file(dir, "spec/b.rb", "b")
        tool = described_class.new(project_root: dir)
        result = tool.execute(pattern: "*.rb", path: "lib")
        expect(result).to include("lib/a.rb")
        expect(result).not_to include("spec/b.rb")
      end
    end
  end
end
