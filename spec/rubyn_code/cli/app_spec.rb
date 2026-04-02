# frozen_string_literal: true

require "spec_helper"

RSpec.describe RubynCode::CLI::App do
  describe "parse_options (via #run)" do
    it "handles --version" do
      app = described_class.new(["--version"])
      expect { app.run }.to output(/rubyn-code #{RubynCode::VERSION}/).to_stdout
    end

    it "handles -v" do
      app = described_class.new(["-v"])
      expect { app.run }.to output(/rubyn-code/).to_stdout
    end

    it "handles --help" do
      app = described_class.new(["--help"])
      expect { app.run }.to output(/Usage/).to_stdout
    end

    it "handles -h" do
      app = described_class.new(["-h"])
      expect { app.run }.to output(/Usage/).to_stdout
    end

    it "handles --auth" do
      app = described_class.new(["--auth"])
      # Stub the auth flow to avoid real OAuth
      allow_any_instance_of(described_class).to receive(:run_auth)
      expect { app.run }.not_to raise_error
    end

    it "handles -p with a prompt" do
      app = described_class.new(["-p", "hello world"])
      options = app.instance_variable_get(:@options)
      expect(options[:command]).to eq(:run)
      expect(options[:prompt]).to eq("hello world")
    end

    it "defaults to :repl when no flags given" do
      app = described_class.new([])
      options = app.instance_variable_get(:@options)
      expect(options[:command]).to eq(:repl)
    end
  end
end
