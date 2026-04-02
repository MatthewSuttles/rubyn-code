# frozen_string_literal: true

require "tty-prompt"

RSpec.describe RubynCode::Permissions::Prompter do
  let(:mock_prompt) { instance_double(TTY::Prompt) }

  before do
    allow(TTY::Prompt).to receive(:new).and_return(mock_prompt)
    allow($stdout).to receive(:puts)
  end

  describe ".confirm" do
    it "returns true when the user approves" do
      allow(mock_prompt).to receive(:yes?).and_return(true)

      result = described_class.confirm("read_file", { path: "foo.rb" })
      expect(result).to be true
    end

    it "returns false when the user declines" do
      allow(mock_prompt).to receive(:yes?).and_return(false)

      result = described_class.confirm("read_file", {})
      expect(result).to be false
    end

    it "returns false on interrupt" do
      # Define the constant the source code rescues, matching its namespace
      stub_const("TTY::Prompt::Reader::InputInterrupt", Class.new(StandardError))

      allow(mock_prompt).to receive(:yes?)
        .and_raise(TTY::Prompt::Reader::InputInterrupt)

      expect(described_class.confirm("bash", {})).to be false
    end
  end

  describe ".confirm_destructive" do
    it "returns true when the user types yes" do
      allow(mock_prompt).to receive(:ask).and_return("yes")

      expect(described_class.confirm_destructive("rm_rf", {})).to be true
    end

    it "returns false for any other input" do
      allow(mock_prompt).to receive(:ask).and_return("no")

      expect(described_class.confirm_destructive("rm_rf", {})).to be false
    end
  end
end
