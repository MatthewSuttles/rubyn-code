# 02 Image Input — Design

## Overview

`@chart.png` (and `.jpg`, `.jpeg`, `.gif`, `.webp`) typed in a prompt
becomes a true image content block attached to the user turn — not just
inline text. Plumbed through the Anthropic and OpenAI adapters in their
respective content-block shapes.

## Architecture

```
User types:    "What is in @chart.png?"
  │
  ▼
CLI::REPL#handle_message
  ├── image_blocks = MentionExpander#expand_images(input)
  │     └── reads @path files, encodes base64, returns ImageBlock list
  ├── input       = MentionExpander#expand(input)   ← text only
  └── agent_loop.send_message(input, blocks: image_blocks)
        │
        ▼
agent_loop#append_user_message
  └── conversation.add_user_message([{type: 'text', text: input}, *image_blocks])
        │
        ▼
agent_loop#build_llm_opts  ──►  llm_client.chat(messages:)
                                  │
                                  ▼
                          MessageBuilder#format_messages
                                  │ branch on ImageBlock →
                                  │   Anthropic: {type: 'image', source: {type: 'base64', ...}}
                                  │
                                  ▼
                          Adapters::Anthropic  ← sends through unchanged
                          Adapters::OpenAI    ← translated by OpenAIMessageTranslator
                                                   image → {type: 'image_url', image_url: {url: 'data:...;base64,...'}}
```

## Pieces

### `LLM::ImageBlock` (message_builder.rb)

```ruby
ImageBlock = Data.define(:media_type, :data) do
  def type = 'image'
end
```

### `LLM::ImageReader`

```ruby
MEDIA_TYPES = {
  '.png' => 'image/png', '.jpg' => 'image/jpeg',
  '.jpeg' => 'image/jpeg', '.gif' => 'image/gif', '.webp' => 'image/webp'
}.freeze

MAX_BYTES = 8 * 1024 * 1024  # 8 MB cap

def for_path(path)         # → ImageBlock, nil on missing/non-image/oversize
def data_uri(path)         # → "data:<media>;base64,..." string
def image_extension?(path) # → Boolean
```

### `MentionExpander#expand_images`

Filters `@path/image.ext` mentions to image extensions via
`ImageReader.image_extension?`, returns `Array<LLM::ImageBlock>`.

### `Agent::Loop#send_message(user_input, blocks: nil)`

When `blocks:` is non-empty, the user message is stored as a mixed
content array starting with a text block, followed by the image blocks.

### `OpenAIMessageTranslator#translate_message`

New branch: when any block in the content array is type `image`, emits
multipart `content: [...]` where image blocks become:

```ruby
{ type: 'image_url', image_url: { url: "data:#{media};base64,#{data}" } }
```

### REPL wiring

```ruby
image_blocks = expand_image_mentions(input)
input = expand_mentions(input)
@agent_loop.send_message(input, blocks: image_blocks.empty? ? nil : image_blocks)
```

`@renderer.info` adds `🖼  Attached images: N` so users see how many
images the agent received.

## Out-of-scope

- PDF / document attachments
- URL-fetched images
- Image preprocessing (resize / compress) before send
- Tool-result image returns
