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

    it 'handles --auth by triggering the auth flow' do
      app = described_class.new(['--auth'])
      allow(app).to receive(:run_auth)
      app.run
      expect(app).to have_received(:run_auth).once
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

    context 'daemon subcommand' do
      it 'parses the daemon command' do
        app = described_class.new(['daemon'])
        options = app.instance_variable_get(:@options)
        expect(options[:command]).to eq(:daemon)
      end

      it 'parses daemon with --name' do
        app = described_class.new(['daemon', '--name', 'my-agent'])
        options = app.instance_variable_get(:@options)
        expect(options[:daemon][:agent_name]).to eq('my-agent')
      end

      it 'parses daemon with --max-runs' do
        app = described_class.new(['daemon', '--max-runs', '50'])
        options = app.instance_variable_get(:@options)
        expect(options[:daemon][:max_runs]).to eq(50)
      end

      it 'parses daemon with --max-cost' do
        app = described_class.new(['daemon', '--max-cost', '2.5'])
        options = app.instance_variable_get(:@options)
        expect(options[:daemon][:max_cost]).to eq(2.5)
      end

      it 'parses daemon with --idle-timeout' do
        app = described_class.new(['daemon', '--idle-timeout', '120'])
        options = app.instance_variable_get(:@options)
        expect(options[:daemon][:idle_timeout]).to eq(120)
      end

      it 'parses daemon with --role' do
        app = described_class.new(['daemon', '--role', 'code reviewer'])
        options = app.instance_variable_get(:@options)
        expect(options[:daemon][:role]).to eq('code reviewer')
      end

      it 'sets sensible defaults' do
        app = described_class.new(['daemon'])
        opts = app.instance_variable_get(:@options)[:daemon]
        expect(opts[:max_runs]).to eq(100)
        expect(opts[:max_cost]).to eq(10.0)
        expect(opts[:idle_timeout]).to eq(60)
        expect(opts[:poll_interval]).to eq(5)
        expect(opts[:role]).to eq('autonomous coding agent')
        expect(opts[:agent_name]).to match(/\Agolem-\h{8}\z/)
      end
    end
  end
end
