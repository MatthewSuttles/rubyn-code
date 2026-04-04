# frozen_string_literal: true

require 'spec_helper'

RSpec.describe RubynCode::Output::Formatter do
  subject(:formatter) { described_class.new(enabled: false) }

  describe '#success' do
    it 'includes the message' do
      expect { formatter.success('done') }.to output(/done/).to_stdout
    end
  end

  describe '#error' do
    it 'includes the message' do
      expect { formatter.error('oops') }.to output(/oops/).to_stdout
    end
  end

  describe '#warning' do
    it 'includes the message' do
      expect { formatter.warning('careful') }.to output(/careful/).to_stdout
    end
  end

  describe '#info' do
    it 'includes the message' do
      expect { formatter.info('fyi') }.to output(/fyi/).to_stdout
    end
  end

  describe '#dim' do
    it 'includes the message' do
      expect { formatter.dim('quiet') }.to output(/quiet/).to_stdout
    end
  end

  describe '#bold' do
    it 'includes the message' do
      expect { formatter.bold('loud') }.to output(/loud/).to_stdout
    end
  end

  describe '#code_block' do
    it 'renders code with delimiters' do
      # Rouge inserts ANSI escapes between tokens, so match the raw variable name
      expect { formatter.code_block('x = 1') }.to output(/x/).to_stdout
    end

    it 'includes delimiter lines' do
      expect { formatter.code_block('x = 1') }.to output(/─{40}/).to_stdout
    end

    it 'handles unknown languages gracefully' do
      expect { formatter.code_block('stuff', language: 'nonexistent_lang') }
        .to output(/stuff/).to_stdout
    end
  end

  describe '#diff' do
    it 'renders added lines' do
      expect { formatter.diff("+added\n") }.to output(/added/).to_stdout
    end

    it 'renders removed lines' do
      expect { formatter.diff("-removed\n") }.to output(/removed/).to_stdout
    end

    it 'renders hunk headers' do
      expect { formatter.diff("@@ -1,3 +1,3 @@\n") }.to output(/@@ -1,3/).to_stdout
    end

    it 'renders file headers' do
      text = "+++ b/file.rb\n--- a/file.rb\n"
      expect { formatter.diff(text) }.to output(/file\.rb/).to_stdout
    end
  end

  describe '#tool_call' do
    it 'includes tool name' do
      expect { formatter.tool_call('read_file') }.to output(/read_file/).to_stdout
    end

    it 'includes arguments when provided' do
      expect { formatter.tool_call('read_file', path: 'foo.rb') }
        .to output(/path.*foo\.rb/).to_stdout
    end

    it 'truncates long argument values' do
      long_val = 'x' * 200
      expect { formatter.tool_call('bash', command: long_val) }
        .to output(/truncated/).to_stdout
    end
  end

  describe '#tool_result' do
    it 'includes tool name and result' do
      expect { formatter.tool_result('read_file', 'file contents') }
        .to output(/read_file.*file contents/m).to_stdout
    end

    it 'truncates long results' do
      long_result = 'x' * 600
      expect { formatter.tool_result('bash', long_result) }
        .to output(/truncated/).to_stdout
    end
  end

  describe '#agent_message' do
    it 'includes the message with agent prefix' do
      expect { formatter.agent_message('Hello!') }
        .to output(/Assistant.*Hello!/m).to_stdout
    end
  end
end
