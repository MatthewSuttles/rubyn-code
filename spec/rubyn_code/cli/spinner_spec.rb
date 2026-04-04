# frozen_string_literal: true

require 'spec_helper'

RSpec.describe RubynCode::CLI::Spinner do
  subject(:spinner) { described_class.new }

  let(:tty_spinner) { instance_double(TTY::Spinner, auto_spin: nil, stop: nil, spinning?: false) }

  before do
    allow(TTY::Spinner).to receive(:new).and_return(tty_spinner)
  end

  after { spinner.stop }

  describe '#start' do
    it 'creates and auto-spins a TTY::Spinner' do
      spinner.start

      expect(TTY::Spinner).to have_received(:new)
      expect(tty_spinner).to have_received(:auto_spin)
    end

    it 'uses a random thinking message when none provided' do
      spinner.start

      expect(TTY::Spinner).to have_received(:new).with(
        a_string_matching(/\[:spinner\] .+/),
        hash_including(format: :dots, clear: true)
      )
    end

    it 'uses the provided message' do
      spinner.start('Processing...')

      expect(TTY::Spinner).to have_received(:new).with(
        a_string_matching(/Processing\.\.\./),
        anything
      )
    end
  end

  describe '#start_sub_agent' do
    it 'starts a spinner' do
      spinner.start_sub_agent

      expect(tty_spinner).to have_received(:auto_spin)
    end

    it 'includes tool count when positive' do
      spinner.start_sub_agent(5)

      expect(TTY::Spinner).to have_received(:new).with(
        a_string_matching(/5 tools/),
        anything
      )
    end

    it 'omits tool count when zero' do
      spinner.start_sub_agent(0)

      expect(TTY::Spinner).to have_received(:new).with(
        a_string_matching(%r{\[:spinner\] [^(]+$}),
        anything
      )
    end
  end

  describe '#update' do
    it 'stops and restarts with new message' do
      allow(tty_spinner).to receive(:spinning?).and_return(true)
      spinner.start('first')

      spinner.update('second')

      expect(tty_spinner).to have_received(:stop)
      expect(TTY::Spinner).to have_received(:new).with(
        a_string_matching(/second/),
        anything
      )
    end

    it 'starts fresh when not spinning' do
      spinner.update('new')

      expect(tty_spinner).to have_received(:auto_spin)
    end
  end

  describe '#success' do
    it 'marks the spinner as successful' do
      allow(tty_spinner).to receive(:success)
      spinner.start
      spinner.success('All good')

      expect(tty_spinner).to have_received(:success).with('(All good)')
    end

    it 'is safe to call with no spinner' do
      expect { spinner.success }.not_to raise_error
    end
  end

  describe '#error' do
    it 'marks the spinner as failed' do
      allow(tty_spinner).to receive(:error)
      spinner.start
      spinner.error('Oops')

      expect(tty_spinner).to have_received(:error).with('(Oops)')
    end

    it 'is safe to call with no spinner' do
      expect { spinner.error }.not_to raise_error
    end
  end

  describe '#stop' do
    it 'stops the spinner and nils it' do
      spinner.start
      spinner.stop

      expect(tty_spinner).to have_received(:stop)
      expect(spinner.spinning?).to be false
    end

    it 'is safe to call with no spinner' do
      expect { spinner.stop }.not_to raise_error
    end
  end

  describe '#spinning?' do
    it 'returns false when no spinner exists' do
      expect(spinner.spinning?).to be false
    end

    it 'delegates to TTY::Spinner#spinning?' do
      allow(tty_spinner).to receive(:spinning?).and_return(true)
      spinner.start

      expect(spinner.spinning?).to be true
    end
  end

  describe 'THINKING_MESSAGES' do
    it 'is a frozen array of strings' do
      expect(described_class::THINKING_MESSAGES).to be_frozen
      expect(described_class::THINKING_MESSAGES).to all(be_a(String))
    end
  end

  describe 'SUB_AGENT_MESSAGES' do
    it 'is a frozen array of strings' do
      expect(described_class::SUB_AGENT_MESSAGES).to be_frozen
      expect(described_class::SUB_AGENT_MESSAGES).to all(be_a(String))
    end
  end
end
