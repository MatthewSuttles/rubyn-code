# frozen_string_literal: true

require "spec_helper"

RSpec.describe RubynCode::Tools::EditFile do
  describe "#execute" do
    it "replaces text in a file" do
      with_temp_project do |dir|
        create_test_file(dir, "app.rb", "def hello\n  puts 'hi'\nend\n")
        tool = described_class.new(project_root: dir)
        result = tool.execute(path: "app.rb", old_text: "puts 'hi'", new_text: "puts 'bye'")
        expect(result).to include("Successfully replaced 1 occurrence")
        expect(File.read(File.join(dir, "app.rb"))).to include("puts 'bye'")
      end
    end

    it "fails if old_text is not found" do
      with_temp_project do |dir|
        create_test_file(dir, "app.rb", "unchanged content")
        tool = described_class.new(project_root: dir)
        expect { tool.execute(path: "app.rb", old_text: "nonexistent", new_text: "x") }
          .to raise_error(RubynCode::Error, /not found/)
      end
    end

    it "fails if old_text is not unique without replace_all" do
      with_temp_project do |dir|
        create_test_file(dir, "dup.rb", "foo\nfoo\nbar\n")
        tool = described_class.new(project_root: dir)
        expect { tool.execute(path: "dup.rb", old_text: "foo", new_text: "baz") }
          .to raise_error(RubynCode::Error, /found 2 times/)
      end
    end

    it "replaces all occurrences with replace_all: true" do
      with_temp_project do |dir|
        create_test_file(dir, "multi.rb", "aaa bbb aaa ccc aaa\n")
        tool = described_class.new(project_root: dir)
        result = tool.execute(path: "multi.rb", old_text: "aaa", new_text: "zzz", replace_all: true)
        expect(result).to include("3 occurrences")
        expect(File.read(File.join(dir, "multi.rb"))).to eq("zzz bbb zzz ccc zzz\n")
      end
    end
  end
end
