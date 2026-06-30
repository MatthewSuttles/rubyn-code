# 02 Image Input — Tasks

## Phase 0 — Scaffolding

- [x] Branch: `phase-04-image-input`

## Phase 1 — Message builder / adapter layer

- [x] `LLM::ImageBlock` (`Data.define(:media_type, :data)`)
- [x] `MessageBuilder#format_content_blocks` branch → Anthropic `image` shape
- [x] `LLM::ImageReader` (`for_path`, `data_uri`, `image_extension?`)
- [x] Autoload in `lib/rubyn_code.rb`

## Phase 2 — Conversation / Loop plumbing

- [x] `Conversation#add_user_message` accepts String OR Array (already did)
- [x] Add `blocks:` kwarg to `Agent::Loop#send_message`
- [x] `append_user_message` builds the mixed-content array when blocks are present

## Phase 3 — CLI surface

- [x] `MentionExpander#expand_images`
- [x] `CLI::REPL#expand_image_mentions`
- [x] `CLI::REPL#handle_message` builds both expansions and passes both
      to `agent_loop.send_message`

## Phase 4 — OpenAI translation

- [x] `OpenAIMessageTranslator#translate_message` branch on `image` blocks
- [x] `translate_user_content_with_images` helper
- [x] `block_type` accessor extracted

## Phase 5 — Tests

- [x] `ImageBlock` Data API
- [x] `ImageReader` happy-path (PNG round-trip)
- [x] `ImageReader` rejection (non-image / missing / oversized)
- [x] `MessageBuilder` Anthropic mapping (Hash + Data input)
- [x] `OpenAIMessageTranslator` multipart content with images
- [x] `MentionExpander` image separation from text expansion
- [x] `repl_spec.rb` mocks updated

## Phase 6 — Lint & Ship

- [x] `bundle exec rubocop -A`
- [x] `bundle exec rspec` (80 examples, 0 failures)
- [x] Conventional commit
- [x] Push branch & open PR (#133)
- [x] PR squash-merged into main

## Phase 7 — Audit-discovered sub-gaps

- [x] **PR #140** — `ImageReader` autoloads `ImageBlock`
- [x] **PR #141** — `ImageReader` self-requires `base64`; content blocks
      autoloaded in `lib/rubyn_code.rb`
