/**
 * Rubyn Code — Message component.
 *
 * Renders user and assistant messages with simple Markdown support
 * and embedded code blocks.
 */

import React from 'react';
import { CodeBlock } from './code-block';

export interface MessageData {
  id: string;
  role: 'user' | 'assistant';
  content: string;
  isStreaming?: boolean;
}

export interface MessageProps {
  message: MessageData;
}

// ---------------------------------------------------------------------------
// Simple Markdown renderer
// ---------------------------------------------------------------------------

interface RenderedBlock {
  type: 'text' | 'code';
  content: string;
  language?: string;
  filePath?: string;
}

/**
 * Split raw content into text and code blocks.
 * Code blocks are fenced with triple backticks.
 */
function splitBlocks(content: string): RenderedBlock[] {
  const blocks: RenderedBlock[] = [];
  const codeBlockRegex = /```(\w+)?(?:\s+([^\n]*))?\n([\s\S]*?)```/g;
  let lastIndex = 0;
  let match: RegExpExecArray | null;

  while ((match = codeBlockRegex.exec(content)) !== null) {
    // Text before this code block
    if (match.index > lastIndex) {
      const text = content.slice(lastIndex, match.index);
      if (text.trim()) {
        blocks.push({ type: 'text', content: text });
      }
    }

    const language = match[1] || 'text';
    const meta = match[2] || '';
    const code = match[3];

    // Check if meta looks like a file path
    const filePath = meta && (meta.includes('/') || meta.includes('.')) ? meta.trim() : undefined;

    blocks.push({ type: 'code', content: code, language, filePath });
    lastIndex = match.index + match[0].length;
  }

  // Remaining text after last code block
  if (lastIndex < content.length) {
    const text = content.slice(lastIndex);
    if (text.trim()) {
      blocks.push({ type: 'text', content: text });
    }
  }

  // If no blocks at all, the whole thing is text
  if (blocks.length === 0 && content.trim()) {
    blocks.push({ type: 'text', content });
  }

  return blocks;
}

/**
 * Render a text block with simple Markdown transformations.
 * Handles: headers, bold, italic, inline code, links, lists.
 */
function renderMarkdownText(text: string): React.ReactNode[] {
  const lines = text.split('\n');
  const elements: React.ReactNode[] = [];
  let listItems: string[] = [];
  let listType: 'ul' | 'ol' | null = null;
  let keyCounter = 0;

  const flushList = () => {
    if (listItems.length > 0 && listType) {
      const Tag = listType;
      elements.push(
        <Tag key={`list-${keyCounter++}`}>
          {listItems.map((item, i) => (
            <li key={i}>{renderInline(item)}</li>
          ))}
        </Tag>,
      );
      listItems = [];
      listType = null;
    }
  };

  for (const line of lines) {
    // Headers
    const headerMatch = line.match(/^(#{1,4})\s+(.+)$/);
    if (headerMatch) {
      flushList();
      const level = headerMatch[1].length as 1 | 2 | 3 | 4;
      const Tag = `h${level}` as keyof JSX.IntrinsicElements;
      elements.push(<Tag key={`h-${keyCounter++}`}>{renderInline(headerMatch[2])}</Tag>);
      continue;
    }

    // Unordered list items
    const ulMatch = line.match(/^[\s]*[-*]\s+(.+)$/);
    if (ulMatch) {
      if (listType === 'ol') { flushList(); }
      listType = 'ul';
      listItems.push(ulMatch[1]);
      continue;
    }

    // Ordered list items
    const olMatch = line.match(/^[\s]*\d+[.)]\s+(.+)$/);
    if (olMatch) {
      if (listType === 'ul') { flushList(); }
      listType = 'ol';
      listItems.push(olMatch[1]);
      continue;
    }

    // Regular line
    flushList();

    if (line.trim() === '') {
      // Skip empty lines between paragraphs (the CSS margins handle spacing)
      continue;
    }

    elements.push(<p key={`p-${keyCounter++}`}>{renderInline(line)}</p>);
  }

  flushList();
  return elements;
}

/**
 * Render inline Markdown: bold, italic, inline code, links.
 */
function renderInline(text: string): React.ReactNode {
  // Order matters: process in a single pass to avoid nesting issues.
  const parts: React.ReactNode[] = [];
  // Regex: inline code, bold, italic, links
  const inlineRegex = /(`[^`]+`)|(\*\*[^*]+\*\*)|(\*[^*]+\*)|(_[^_]+_)|(\[([^\]]+)\]\(([^)]+)\))/g;
  let lastIdx = 0;
  let match: RegExpExecArray | null;
  let key = 0;

  while ((match = inlineRegex.exec(text)) !== null) {
    // Plain text before match
    if (match.index > lastIdx) {
      parts.push(text.slice(lastIdx, match.index));
    }

    if (match[1]) {
      // Inline code
      const code = match[1].slice(1, -1);
      parts.push(<code key={key++} className="inline-code">{code}</code>);
    } else if (match[2]) {
      // Bold **text**
      const bold = match[2].slice(2, -2);
      parts.push(<strong key={key++}>{bold}</strong>);
    } else if (match[3]) {
      // Italic *text*
      const italic = match[3].slice(1, -1);
      parts.push(<em key={key++}>{italic}</em>);
    } else if (match[4]) {
      // Italic _text_
      const italic = match[4].slice(1, -1);
      parts.push(<em key={key++}>{italic}</em>);
    } else if (match[5]) {
      // Link [text](url)
      parts.push(
        <a key={key++} href={match[7]} title={match[7]}>
          {match[6]}
        </a>,
      );
    }

    lastIdx = match.index + match[0].length;
  }

  // Trailing text
  if (lastIdx < text.length) {
    parts.push(text.slice(lastIdx));
  }

  return parts.length === 1 ? parts[0] : <>{parts}</>;
}

// ---------------------------------------------------------------------------
// Message component
// ---------------------------------------------------------------------------

export const Message: React.FC<MessageProps> = ({ message }) => {
  if (message.role === 'user') {
    return (
      <div className="message message-user">
        <div className="message-bubble">{message.content}</div>
      </div>
    );
  }

  // Assistant message: render with markdown + code blocks
  const blocks = splitBlocks(message.content);

  return (
    <div className="message message-assistant">
      <div className={`message-content${message.isStreaming ? ' streaming-cursor' : ''}`}>
        {blocks.map((block, idx) =>
          block.type === 'code' ? (
            <CodeBlock
              key={`cb-${idx}`}
              code={block.content}
              language={block.language || 'text'}
              filePath={block.filePath}
            />
          ) : (
            <div key={`md-${idx}`}>{renderMarkdownText(block.content)}</div>
          ),
        )}
      </div>
    </div>
  );
};
