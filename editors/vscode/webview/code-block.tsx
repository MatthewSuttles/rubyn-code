/**
 * Rubyn Code — Code block component with syntax highlighting and copy/apply actions.
 */

import React, { useCallback, useState } from 'react';

// ---------------------------------------------------------------------------
// Tokenizer — simple keyword-based highlighting
// ---------------------------------------------------------------------------

interface Token {
  type: string;
  value: string;
}

const LANGUAGE_KEYWORDS: Record<string, { keywords: string[]; builtins?: string[]; types?: string[] }> = {
  ruby: {
    keywords: [
      'def', 'end', 'class', 'module', 'if', 'else', 'elsif', 'unless', 'while', 'until',
      'for', 'do', 'begin', 'rescue', 'ensure', 'raise', 'return', 'yield', 'require',
      'require_relative', 'include', 'extend', 'prepend', 'attr_reader', 'attr_writer',
      'attr_accessor', 'private', 'protected', 'public', 'self', 'super', 'nil', 'true',
      'false', 'and', 'or', 'not', 'in', 'then', 'when', 'case', 'lambda', 'proc',
      'block_given?', 'defined?', 'alias', 'retry', 'redo', 'next', 'break',
    ],
    builtins: ['puts', 'print', 'p', 'gets', 'chomp', 'freeze', 'frozen?', 'inspect', 'to_s', 'to_i', 'to_f', 'map', 'each', 'select', 'reject', 'reduce', 'flat_map'],
    types: ['String', 'Integer', 'Float', 'Array', 'Hash', 'Symbol', 'Proc', 'Method', 'Object', 'Class', 'Module', 'Struct', 'Enumerable'],
  },
  javascript: {
    keywords: [
      'const', 'let', 'var', 'function', 'return', 'if', 'else', 'for', 'while', 'do',
      'switch', 'case', 'break', 'continue', 'new', 'this', 'class', 'extends', 'super',
      'import', 'export', 'from', 'default', 'try', 'catch', 'finally', 'throw', 'async',
      'await', 'yield', 'typeof', 'instanceof', 'in', 'of', 'true', 'false', 'null',
      'undefined', 'void', 'delete',
    ],
    builtins: ['console', 'Math', 'JSON', 'Promise', 'setTimeout', 'setInterval', 'fetch', 'require'],
    types: ['Array', 'Object', 'String', 'Number', 'Boolean', 'Map', 'Set', 'RegExp', 'Date', 'Error'],
  },
  typescript: {
    keywords: [
      'const', 'let', 'var', 'function', 'return', 'if', 'else', 'for', 'while', 'do',
      'switch', 'case', 'break', 'continue', 'new', 'this', 'class', 'extends', 'super',
      'import', 'export', 'from', 'default', 'try', 'catch', 'finally', 'throw', 'async',
      'await', 'yield', 'typeof', 'instanceof', 'in', 'of', 'true', 'false', 'null',
      'undefined', 'void', 'delete', 'type', 'interface', 'enum', 'namespace', 'declare',
      'as', 'is', 'keyof', 'readonly', 'abstract', 'implements', 'private', 'protected',
      'public', 'static', 'override',
    ],
    builtins: ['console', 'Math', 'JSON', 'Promise', 'setTimeout', 'setInterval', 'fetch', 'require'],
    types: ['Array', 'Object', 'String', 'Number', 'Boolean', 'Map', 'Set', 'RegExp', 'Date', 'Error', 'Record', 'Partial', 'Required', 'Readonly', 'Pick', 'Omit'],
  },
  html: {
    keywords: ['DOCTYPE', 'html', 'head', 'body', 'div', 'span', 'p', 'a', 'img', 'script', 'style', 'link', 'meta', 'title', 'h1', 'h2', 'h3', 'h4', 'h5', 'h6', 'ul', 'ol', 'li', 'table', 'tr', 'td', 'th', 'form', 'input', 'button', 'select', 'option', 'textarea', 'nav', 'header', 'footer', 'main', 'section', 'article'],
    builtins: [],
  },
  css: {
    keywords: ['important', 'media', 'keyframes', 'import', 'charset', 'font-face', 'supports', 'layer'],
    builtins: ['none', 'auto', 'inherit', 'initial', 'unset', 'flex', 'grid', 'block', 'inline', 'relative', 'absolute', 'fixed', 'sticky', 'hidden', 'visible', 'solid', 'dashed', 'dotted', 'transparent'],
  },
  yaml: {
    keywords: ['true', 'false', 'null', 'yes', 'no', 'on', 'off'],
    builtins: [],
  },
  sql: {
    keywords: [
      'SELECT', 'FROM', 'WHERE', 'AND', 'OR', 'NOT', 'INSERT', 'INTO', 'VALUES', 'UPDATE',
      'SET', 'DELETE', 'CREATE', 'TABLE', 'ALTER', 'DROP', 'INDEX', 'JOIN', 'LEFT', 'RIGHT',
      'INNER', 'OUTER', 'ON', 'GROUP', 'BY', 'ORDER', 'ASC', 'DESC', 'HAVING', 'LIMIT',
      'OFFSET', 'AS', 'DISTINCT', 'COUNT', 'SUM', 'AVG', 'MIN', 'MAX', 'NULL', 'IS',
      'LIKE', 'IN', 'BETWEEN', 'EXISTS', 'CASE', 'WHEN', 'THEN', 'ELSE', 'END', 'PRIMARY',
      'KEY', 'FOREIGN', 'REFERENCES', 'UNIQUE', 'DEFAULT', 'NOT', 'CONSTRAINT',
      'select', 'from', 'where', 'and', 'or', 'not', 'insert', 'into', 'values', 'update',
      'set', 'delete', 'create', 'table', 'alter', 'drop', 'index', 'join', 'left', 'right',
      'inner', 'outer', 'on', 'group', 'by', 'order', 'asc', 'desc', 'having', 'limit',
      'offset', 'as', 'distinct', 'null', 'is', 'like', 'in', 'between', 'exists',
      'case', 'when', 'then', 'else', 'end', 'primary', 'key',
    ],
    builtins: [],
    types: ['INTEGER', 'VARCHAR', 'TEXT', 'BOOLEAN', 'FLOAT', 'DECIMAL', 'DATE', 'TIMESTAMP', 'BIGINT', 'SERIAL', 'UUID', 'JSONB', 'integer', 'varchar', 'text', 'boolean', 'float', 'decimal', 'date', 'timestamp', 'bigint', 'serial', 'uuid', 'jsonb'],
  },
  shell: {
    keywords: ['if', 'then', 'else', 'elif', 'fi', 'for', 'while', 'do', 'done', 'case', 'esac', 'in', 'function', 'return', 'exit', 'export', 'source', 'local', 'readonly'],
    builtins: ['echo', 'cd', 'ls', 'rm', 'cp', 'mv', 'mkdir', 'cat', 'grep', 'sed', 'awk', 'find', 'xargs', 'curl', 'wget', 'git', 'docker', 'npm', 'yarn', 'bundle', 'rails', 'rake', 'ruby', 'node', 'python', 'pip', 'chmod', 'chown', 'sudo', 'apt', 'brew'],
  },
};

// Aliases
LANGUAGE_KEYWORDS['js'] = LANGUAGE_KEYWORDS['javascript'];
LANGUAGE_KEYWORDS['ts'] = LANGUAGE_KEYWORDS['typescript'];
LANGUAGE_KEYWORDS['rb'] = LANGUAGE_KEYWORDS['ruby'];
LANGUAGE_KEYWORDS['sh'] = LANGUAGE_KEYWORDS['shell'];
LANGUAGE_KEYWORDS['bash'] = LANGUAGE_KEYWORDS['shell'];
LANGUAGE_KEYWORDS['zsh'] = LANGUAGE_KEYWORDS['shell'];
LANGUAGE_KEYWORDS['yml'] = LANGUAGE_KEYWORDS['yaml'];
LANGUAGE_KEYWORDS['jsx'] = LANGUAGE_KEYWORDS['javascript'];
LANGUAGE_KEYWORDS['tsx'] = LANGUAGE_KEYWORDS['typescript'];
LANGUAGE_KEYWORDS['erb'] = LANGUAGE_KEYWORDS['ruby'];

function tokenize(code: string, language: string): Token[] {
  const langDef = LANGUAGE_KEYWORDS[language.toLowerCase()];
  if (!langDef) {
    return [{ type: 'plain', value: code }];
  }

  const tokens: Token[] = [];
  const keywords = new Set(langDef.keywords);
  const builtins = new Set(langDef.builtins ?? []);
  const types = new Set(langDef.types ?? []);
  let i = 0;

  while (i < code.length) {
    // Comments: # (ruby/shell/yaml) or // (js/ts)
    if (
      (code[i] === '#' && ['ruby', 'rb', 'shell', 'sh', 'bash', 'zsh', 'yaml', 'yml', 'erb'].includes(language.toLowerCase())) ||
      (code[i] === '/' && code[i + 1] === '/')
    ) {
      const start = i;
      const inc = code[i] === '/' ? 2 : 1;
      i += inc;
      while (i < code.length && code[i] !== '\n') { i++; }
      tokens.push({ type: 'comment', value: code.slice(start, i) });
      continue;
    }

    // Multi-line comments /* */
    if (code[i] === '/' && code[i + 1] === '*') {
      const start = i;
      i += 2;
      while (i < code.length && !(code[i - 1] === '*' && code[i] === '/')) { i++; }
      if (i < code.length) { i++; }
      tokens.push({ type: 'comment', value: code.slice(start, i) });
      continue;
    }

    // SQL single-line comments --
    if (code[i] === '-' && code[i + 1] === '-' && ['sql'].includes(language.toLowerCase())) {
      const start = i;
      i += 2;
      while (i < code.length && code[i] !== '\n') { i++; }
      tokens.push({ type: 'comment', value: code.slice(start, i) });
      continue;
    }

    // Strings: single, double, backtick
    if (code[i] === '"' || code[i] === "'" || code[i] === '`') {
      const quote = code[i];
      const start = i;
      i++;
      while (i < code.length && code[i] !== quote) {
        if (code[i] === '\\') { i++; }
        i++;
      }
      if (i < code.length) { i++; }
      tokens.push({ type: 'string', value: code.slice(start, i) });
      continue;
    }

    // Ruby symbols :word
    if (code[i] === ':' && language.toLowerCase() === 'ruby' || language.toLowerCase() === 'rb' || language.toLowerCase() === 'erb') {
      if (code[i] === ':' && i + 1 < code.length && /[a-zA-Z_]/.test(code[i + 1])) {
        const start = i;
        i++;
        while (i < code.length && /\w/.test(code[i])) { i++; }
        tokens.push({ type: 'symbol', value: code.slice(start, i) });
        continue;
      }
    }

    // Numbers
    if (/\d/.test(code[i])) {
      const start = i;
      while (i < code.length && /[\d._xXa-fA-F]/.test(code[i])) { i++; }
      tokens.push({ type: 'number', value: code.slice(start, i) });
      continue;
    }

    // Words (identifiers / keywords)
    if (/[a-zA-Z_$@]/.test(code[i])) {
      const start = i;
      while (i < code.length && /[\w$?!]/.test(code[i])) { i++; }
      const word = code.slice(start, i);
      if (keywords.has(word)) {
        tokens.push({ type: 'keyword', value: word });
      } else if (types.has(word)) {
        tokens.push({ type: 'type', value: word });
      } else if (builtins.has(word)) {
        tokens.push({ type: 'builtin', value: word });
      } else if (i < code.length && code[i] === '(') {
        tokens.push({ type: 'function', value: word });
      } else if (word.startsWith('@') || word.startsWith('$')) {
        tokens.push({ type: 'variable', value: word });
      } else {
        tokens.push({ type: 'plain', value: word });
      }
      continue;
    }

    // HTML/CSS: selectors, tags in angle brackets
    if (code[i] === '<' && ['html', 'erb'].includes(language.toLowerCase())) {
      const start = i;
      i++;
      if (i < code.length && code[i] === '/') { i++; }
      while (i < code.length && code[i] !== '>' && code[i] !== ' ') { i++; }
      const tagContent = code.slice(start, i);
      tokens.push({ type: 'tag', value: tagContent });
      continue;
    }

    // Operators and punctuation
    if (/[+\-*/%=<>!&|^~?:;.,{}()\[\]]/.test(code[i])) {
      tokens.push({ type: 'punctuation', value: code[i] });
      i++;
      continue;
    }

    // Whitespace and everything else
    const start = i;
    while (i < code.length && !/[a-zA-Z_$@\d"'`#/\-+*%=<>!&|^~?:;.,{}()\[\]\\]/.test(code[i])) {
      i++;
    }
    if (i > start) {
      tokens.push({ type: 'plain', value: code.slice(start, i) });
    }

    // Safety: advance if stuck
    if (i === start) {
      tokens.push({ type: 'plain', value: code[i] });
      i++;
    }
  }

  return tokens;
}

// ---------------------------------------------------------------------------
// CodeBlock component
// ---------------------------------------------------------------------------

export interface CodeBlockProps {
  code: string;
  language: string;
  filePath?: string;
  showLineNumbers?: boolean;
}

export const CodeBlock: React.FC<CodeBlockProps> = ({
  code,
  language,
  filePath,
  showLineNumbers = false,
}) => {
  const [copied, setCopied] = useState(false);

  const handleCopy = useCallback(() => {
    navigator.clipboard.writeText(code).then(() => {
      setCopied(true);
      setTimeout(() => setCopied(false), 2000);
    }).catch(() => {
      // Fallback for environments without clipboard API
      const vscodeApi = (window as any).vscodeApi;
      if (vscodeApi) {
        vscodeApi.postMessage({ type: 'copyToClipboard', payload: { text: code } });
        setCopied(true);
        setTimeout(() => setCopied(false), 2000);
      }
    });
  }, [code]);

  const handleApply = useCallback(() => {
    const vscodeApi = (window as any).vscodeApi;
    if (vscodeApi) {
      vscodeApi.postMessage({
        type: 'applyCode',
        payload: { code, language, filePath },
      });
    }
  }, [code, language, filePath]);

  const tokens = tokenize(code, language);
  const lines = code.split('\n');

  const displayLang = language || 'text';

  return (
    <div className="code-block-wrapper">
      <div className="code-block-header">
        <span className="language-label">{displayLang}{filePath ? ` — ${filePath}` : ''}</span>
        <div className="code-actions">
          {filePath && (
            <button onClick={handleApply} title="Apply to file">
              Apply
            </button>
          )}
          <button onClick={handleCopy} title="Copy code">
            {copied ? 'Copied' : 'Copy'}
          </button>
        </div>
      </div>
      <div className={`code-block-body${showLineNumbers ? ' with-line-numbers' : ''}`}>
        {showLineNumbers && (
          <div className="line-numbers">
            {lines.map((_, idx) => (
              <div key={idx}>{idx + 1}</div>
            ))}
          </div>
        )}
        <code>
          {tokens.map((token, idx) => (
            token.type === 'plain' ? (
              <span key={idx}>{token.value}</span>
            ) : (
              <span key={idx} className={`token-${token.type}`}>{token.value}</span>
            )
          ))}
        </code>
      </div>
    </div>
  );
};
