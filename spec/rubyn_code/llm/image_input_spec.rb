# frozen_string_literal: true

require 'spec_helper'
require 'rubyn_code/llm/message_builder'
require 'rubyn_code/llm/image_reader'
require 'rubyn_code/llm/adapters/openai_message_translator'
require 'tmpdir'

RSpec.describe 'Image input plumbing' do
  describe RubynCode::LLM::ImageBlock do
    it 'reports type "image"' do
      expect(described_class.new(media_type: 'image/png', data: 'AAA').type).to eq('image')
    end
  end

  describe RubynCode::LLM::ImageReader do
    around do |ex|
      Dir.mktmpdir do |dir|
        @dir = dir
        ex.run
      end
    end

    it 'reads a PNG and base64-encodes it' do
      png_path = File.join(@dir, 'pixel.png')
      # 1x1 transparent PNG (89 bytes) - canonical test fixture.
      bytes = %w[89504e470d0a1a0a0000000d49484452000000010000000108060000001f15c489
                 0000000d49444154789c6300010000000500010d0a2db40000000049454e44ae426082].pack('H*')
      File.binwrite(png_path, bytes)

      block = described_class.for_path(png_path)
      expect(block).to be_a(RubynCode::LLM::ImageBlock)
      expect(block.media_type).to eq('image/png')
      expect(block.data).to eq(Base64.strict_encode64(bytes))
    end

    it 'returns nil for non-image extensions' do
      txt = File.join(@dir, 'note.txt')
      File.write(txt, 'hi')
      expect(described_class.for_path(txt)).to be_nil
    end

    it 'returns nil for missing files' do
      expect(described_class.for_path(File.join(@dir, 'missing.png'))).to be_nil
    end

    it 'detects image extensions' do
      expect(described_class.image_extension?('a.png')).to be true
      expect(described_class.image_extension?('a.JPEG')).to be true
      expect(described_class.image_extension?('a.gif')).to be true
      expect(described_class.image_extension?('a.webp')).to be true
      expect(described_class.image_extension?('a.txt')).to be false
    end

    it 'returns a data URI for valid images' do
      path = File.join(@dir, 'a.png')
      File.binwrite(path, "\x89PNG\r\n\x1a\n".dup)
      uri = described_class.data_uri(path)
      expect(uri).to start_with('data:image/png;base64,')
    end
  end

  describe RubynCode::LLM::MessageBuilder do
    it 'maps ImageBlock to Anthropic image content block' do
      blocks = [{ type: 'image', source: { type: 'base64', media_type: 'image/png', data: 'XYZ' } }]
      out = described_class.new.format_messages([{ role: 'user', content: blocks }])
      expect(out.first[:content].first).to eq(type: 'image',
                                              source: { type: 'base64',
                                                        media_type: 'image/png', data: 'XYZ' })
    end

    it 'maps LLM::ImageBlock Data object to Anthropic shape' do
      block = RubynCode::LLM::ImageBlock.new(media_type: 'image/jpeg', data: 'ZZZ')
      out = described_class.new.format_messages([{ role: 'user', content: [block] }])
      expect(out.first[:content].first[:type]).to eq('image')
      expect(out.first[:content].first[:source][:media_type]).to eq('image/jpeg')
      expect(out.first[:content].first[:source][:data]).to eq('ZZZ')
    end
  end

  describe RubynCode::LLM::Adapters::OpenAIMessageTranslator do
    let(:translator_class) do
      Class.new { include RubynCode::LLM::Adapters::OpenAIMessageTranslator }
    end
    subject(:translator) { translator_class.new }

    it 'translates user content with images to image_url blocks' do
      msg = {
        role: 'user',
        content: [
          { type: 'text', text: 'What is in this picture?' },
          { type: 'image', source: { type: 'base64', media_type: 'image/png', data: 'BASE64DATA' } }
        ]
      }
      out = translator.send(:translate_message, msg)
      expect(out[:content]).to be_an(Array)
      expect(out[:content].first).to eq(type: 'text', text: 'What is in this picture?')
      expect(out[:content].last[:type]).to eq('image_url')
      expect(out[:content].last[:image_url][:url]).to eq('data:image/png;base64,BASE64DATA')
    end

    it 'leaves string content as a string' do
      msg = { role: 'user', content: 'plain text' }
      out = translator.send(:translate_message, msg)
      expect(out[:content]).to eq('plain text')
    end
  end

  describe RubynCode::CLI::MentionExpander do
    around do |ex|
      Dir.mktmpdir do |dir|
        @dir = dir
        File.write(File.join(dir, 'note.txt'), 'hi')
        File.binwrite(File.join(dir, 'pixel.png'), "\x89PNG\r\n\x1a\n".dup)
        ex.run
      end
    end

    let(:expander) { described_class.new(project_root: @dir) }

    it 'expands image mentions to image blocks' do
      blocks = expander.expand_images('look at @pixel.png')
      expect(blocks.size).to eq(1)
      expect(blocks.first).to be_a(RubynCode::LLM::ImageBlock)
    end

    it 'skips non-image mentions in image expansion' do
      blocks = expander.expand_images('compare @note.txt and @pixel.png')
      expect(blocks.size).to eq(1)
      expect(blocks.first.media_type).to eq('image/png')
    end

    it 'returns empty array when no image mentions' do
      expect(expander.expand_images('no mentions here')).to eq([])
    end

    it 'still expands non-image mentions through #expand' do
      expanded, paths = expander.expand('read @note.txt')
      expect(paths).to eq(['note.txt'])
      expect(expanded).to include('@note.txt')
      expect(expanded).to include('hi')
    end
  end
end
