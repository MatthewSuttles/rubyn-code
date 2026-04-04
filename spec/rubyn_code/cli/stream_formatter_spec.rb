# frozen_string_literal: true

require 'spec_helper'

RSpec.describe RubynCode::CLI::StreamFormatter do
  subject(:formatter) { described_class.new }

  let(:output) { StringIO.new }

  before { $stdout = output }
  after { $stdout = STDOUT }

  def printed
    output.string
  end

  describe '#feed' do
    context 'with plain text ending in newline' do
      it 'outputs the line immediately' do
        formatter.feed("Hello world\n")

        expect(printed).to include('Hello world')
      end
    end

    context 'with plain text without newline (partial)' do
      it 'outputs partial text immediately' do
        formatter.feed('Hello partial')

        expect(printed).to include('Hello partial')
      end
    end

    context 'with multiple chunks forming a complete line' do
      it 'outputs all chunks as a complete line when newline arrives' do
        formatter.feed('Hello ')

        expect(printed).to include('Hello ')

        formatter.feed("world\n")

        expect(printed).to include('world')
      end
    end

    context 'with header lines' do
      it 'formats H1 with bold underline' do
        formatter.feed("# Main Title\n")

        expect(printed).to include('Main Title')
        expect(printed).not_to include('# ')
      end

      it 'formats H2 with bold' do
        formatter.feed("## Sub Title\n")

        expect(printed).to include('Sub Title')
        expect(printed).not_to include('## ')
      end

      it 'formats H3 with bold' do
        formatter.feed("### Third Level\n")

        expect(printed).to include('Third Level')
        expect(printed).not_to include('### ')
      end
    end

    context 'with bullet list items' do
      it 'formats dash bullet with •' do
        formatter.feed("- first item\n")

        expect(printed).to include('•')
        expect(printed).to include('first item')
      end

      it 'formats asterisk bullet with •' do
        formatter.feed("* second item\n")

        expect(printed).to include('•')
        expect(printed).to include('second item')
      end
    end

    context 'with numbered list items' do
      it 'formats the number and content' do
        formatter.feed("1. first step\n")

        expect(printed).to include('1.')
        expect(printed).to include('first step')
      end
    end

    context 'with horizontal rules' do
      it 'outputs a dim line of dashes' do
        formatter.feed("---\n")

        expect(printed).to include('─')
      end
    end

    context 'with inline bold' do
      it 'applies bold formatting to **text**' do
        formatter.feed("This is **bold** text\n")

        expect(printed).to include('bold')
        expect(printed).not_to include('**')
      end
    end

    context 'with inline code' do
      it 'applies cyan formatting to `code`' do
        formatter.feed("Use `puts` here\n")

        expect(printed).to include('puts')
        expect(printed).not_to include('`')
      end
    end

    context 'with code block opening' do
      it 'prints a header and does not output content yet' do
        formatter.feed("```ruby\n")

        expect(printed).to include('ruby')
        expect(printed).to include('┌─')
      end
    end

    context 'with code block content' do
      it 'buffers content without printing it' do
        formatter.feed("```ruby\n")
        output.truncate(0)
        output.rewind

        formatter.feed("x = 1\n")

        expect(printed).to eq('')
      end
    end

    context 'with code block closing' do
      it 'renders the highlighted block with borders' do
        formatter.feed("```ruby\n")
        formatter.feed("x = 1\n")
        output.truncate(0)
        output.rewind

        formatter.feed("```\n")

        expect(printed).to include('│')
        expect(printed).to include('└─')
      end
    end
  end

  describe '#flush' do
    context 'with remaining plain text in buffer' do
      it 'outputs the buffered text' do
        formatter.feed("some complete line\n")

        expect(printed).to include('some complete line')
      end
    end

    context 'with partial text inside a code block' do
      it 'renders the partial text as part of the code block' do
        formatter.feed("```ruby\n")
        formatter.feed('x = 42')
        output.truncate(0)
        output.rewind

        formatter.flush

        expect(printed).to include('└─')
      end
    end

    context 'with an unclosed code block' do
      it 'renders the buffered code block' do
        formatter.feed("```ruby\n")
        formatter.feed("y = 2\n")
        output.truncate(0)
        output.rewind

        formatter.flush

        expect(printed).to include('└─')
      end
    end

    context 'when buffer is empty' do
      it 'does not output anything' do
        formatter.flush

        expect(printed).to eq('')
      end
    end
  end

  describe 'streaming behavior' do
    context 'with interleaved text and code blocks' do
      it 'renders text then code then text correctly' do
        formatter.feed("Before code\n")
        formatter.feed("```ruby\n")
        formatter.feed("puts 'hi'\n")
        formatter.feed("```\n")
        formatter.feed("After code\n")

        expect(printed).to include('Before code')
        expect(printed).to include('┌─')
        expect(printed).to include('└─')
        expect(printed).to include('After code')
      end
    end

    context 'with multiple code blocks in sequence' do
      it 'renders each code block independently' do
        formatter.feed("```ruby\n")
        formatter.feed("a = 1\n")
        formatter.feed("```\n")
        formatter.feed("```python\n")
        formatter.feed("b = 2\n")
        formatter.feed("```\n")

        occurrences_open = printed.scan('┌─').length
        occurrences_close = printed.scan('└─').length

        expect(occurrences_open).to eq(2)
        expect(occurrences_close).to eq(2)
        expect(printed).to include('ruby')
        expect(printed).to include('python')
      end
    end
  end
end
