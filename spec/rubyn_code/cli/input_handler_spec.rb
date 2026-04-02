# frozen_string_literal: true

require "spec_helper"

RSpec.describe RubynCode::CLI::InputHandler do
  subject(:handler) { described_class.new }

  describe "#parse" do
    it "returns quit for /quit" do
      cmd = handler.parse("/quit")
      expect(cmd.action).to eq(:quit)
    end

    it "returns quit for /exit" do
      expect(handler.parse("/exit").action).to eq(:quit)
    end

    it "returns compact for /compact" do
      expect(handler.parse("/compact").action).to eq(:compact)
    end

    it "returns unknown_command for unrecognized slash commands" do
      cmd = handler.parse("/foobar")
      expect(cmd.action).to eq(:unknown_command)
      expect(cmd.args).to include("/foobar")
    end

    it "returns quit for nil input (EOF)" do
      expect(handler.parse(nil).action).to eq(:quit)
    end

    it "returns empty for blank input" do
      expect(handler.parse("   ").action).to eq(:empty)
    end

    it "returns message for regular text" do
      cmd = handler.parse("tell me about Ruby")
      expect(cmd.action).to eq(:message)
    end

    it "expands file references with @path" do
      with_temp_project do |dir|
        path = create_test_file(dir, "sample.rb", "puts 'hi'")
        cmd = handler.parse("Read @#{path}")
        expect(cmd.args.first).to include("<file")
        expect(cmd.args.first).to include("puts 'hi'")
      end
    end
  end

  describe "#multiline?" do
    it "returns true for lines ending with backslash" do
      expect(handler.multiline?("hello\\")).to be true
    end

    it "returns false for normal lines" do
      expect(handler.multiline?("hello")).to be false
    end
  end
end
