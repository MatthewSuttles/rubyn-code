/**
 * Rubyn Code — Main chat component.
 *
 * Renders the sidebar chat UI with message list, input area, slash commands,
 * and tool approval cards. Communicates with the extension host via
 * window.vscodeApi.postMessage / window.addEventListener('message').
 */

import React, { useCallback, useEffect, useRef, useState } from 'react';
import { createRoot } from 'react-dom/client';
import { Message, MessageData } from './message';
import { ToolApproval } from './tool-approval';
import './styles.css';

// ---------------------------------------------------------------------------
// VS Code API typing
// ---------------------------------------------------------------------------

declare global {
  interface Window {
    vscodeApi: {
      postMessage(message: unknown): void;
      getState(): unknown;
      setState(state: unknown): void;
    };
  }
}

const vscode = window.vscodeApi;

// ---------------------------------------------------------------------------
// Types
// ---------------------------------------------------------------------------

interface ToolUseEntry {
  requestId: string;
  tool: string;
  args: Record<string, unknown>;
  requiresApproval: boolean;
  result?: { success: boolean; summary: string } | null;
}

interface SessionInfo {
  id: string | null;
  cost: number;
}

interface AgentStatus {
  state: 'idle' | 'thinking' | 'tool_use' | 'streaming' | 'reviewing' | 'learning';
  detail?: string;
}

/** Items rendered in the message list: either a message or a tool card. */
type ChatItem =
  | { kind: 'message'; data: MessageData }
  | { kind: 'tool'; data: ToolUseEntry };

// ---------------------------------------------------------------------------
// Slash commands
// ---------------------------------------------------------------------------

interface SlashCommand {
  name: string;
  description: string;
}

const SLASH_COMMANDS: SlashCommand[] = [
  { name: '/review', description: 'Review current PR or diff' },
  { name: '/compact', description: 'Summarize the conversation' },
  { name: '/cost', description: 'Show session token usage and cost' },
  { name: '/help', description: 'Show available commands' },
];

// ---------------------------------------------------------------------------
// Chat component
// ---------------------------------------------------------------------------

const Chat: React.FC = () => {
  const [items, setItems] = useState<ChatItem[]>([]);
  const [inputText, setInputText] = useState('');
  const [isStreaming, setIsStreaming] = useState(false);
  const [session, setSession] = useState<SessionInfo>({ id: null, cost: 0 });
  const [agentStatus, setAgentStatus] = useState<AgentStatus>({ state: 'idle' });
  const [activeFile, setActiveFile] = useState<string | null>(null);
  const [showSlashDropdown, setShowSlashDropdown] = useState(false);
  const [slashFilter, setSlashFilter] = useState('');
  const [selectedSlashIdx, setSelectedSlashIdx] = useState(0);

  const messageListRef = useRef<HTMLDivElement>(null);
  const textareaRef = useRef<HTMLTextAreaElement>(null);
  const currentAssistantIdRef = useRef<string | null>(null);

  // -------------------------------------------------------------------------
  // Auto-scroll to bottom
  // -------------------------------------------------------------------------

  const scrollToBottom = useCallback(() => {
    const el = messageListRef.current;
    if (el) {
      requestAnimationFrame(() => {
        el.scrollTop = el.scrollHeight;
      });
    }
  }, []);

  useEffect(() => {
    scrollToBottom();
  }, [items, scrollToBottom]);

  // -------------------------------------------------------------------------
  // Auto-resize textarea
  // -------------------------------------------------------------------------

  const resizeTextarea = useCallback(() => {
    const ta = textareaRef.current;
    if (ta) {
      ta.style.height = 'auto';
      ta.style.height = `${Math.min(ta.scrollHeight, 160)}px`;
    }
  }, []);

  // -------------------------------------------------------------------------
  // Listen for messages from the extension host
  // -------------------------------------------------------------------------

  useEffect(() => {
    const handler = (event: MessageEvent) => {
      const msg = event.data;
      if (!msg || !msg.type) { return; }

      switch (msg.type) {
        case 'stream/text': {
          const { delta, done, sessionId } = msg.payload as {
            delta: string;
            done: boolean;
            sessionId: string;
          };

          if (sessionId && !session.id) {
            setSession((s) => ({ ...s, id: sessionId }));
          }

          if (!currentAssistantIdRef.current) {
            // Start a new assistant message
            const id = `assistant_${Date.now()}`;
            currentAssistantIdRef.current = id;
            setItems((prev) => [
              ...prev,
              { kind: 'message', data: { id, role: 'assistant', content: delta, isStreaming: true } },
            ]);
          } else {
            // Append delta to current assistant message
            const currentId = currentAssistantIdRef.current;
            setItems((prev) =>
              prev.map((item) => {
                if (item.kind === 'message' && item.data.id === currentId) {
                  return {
                    ...item,
                    data: {
                      ...item.data,
                      content: item.data.content + delta,
                      isStreaming: !done,
                    },
                  };
                }
                return item;
              }),
            );
          }

          if (done) {
            // Finalize: mark not streaming, clear ref
            const currentId = currentAssistantIdRef.current;
            if (currentId) {
              setItems((prev) =>
                prev.map((item) => {
                  if (item.kind === 'message' && item.data.id === currentId) {
                    return { ...item, data: { ...item.data, isStreaming: false } };
                  }
                  return item;
                }),
              );
            }
            currentAssistantIdRef.current = null;
            setIsStreaming(false);
          }
          break;
        }

        case 'tool/use': {
          const payload = msg.payload as {
            requestId: string;
            tool: string;
            args: Record<string, unknown>;
            requiresApproval: boolean;
          };
          setItems((prev) => [
            ...prev,
            {
              kind: 'tool',
              data: {
                requestId: payload.requestId,
                tool: payload.tool,
                args: payload.args,
                requiresApproval: payload.requiresApproval,
                result: null,
              },
            },
          ]);
          break;
        }

        case 'tool/result': {
          const payload = msg.payload as {
            requestId: string;
            tool: string;
            success: boolean;
            summary: string;
          };
          setItems((prev) =>
            prev.map((item) => {
              if (item.kind === 'tool' && item.data.requestId === payload.requestId) {
                return {
                  ...item,
                  data: {
                    ...item.data,
                    result: { success: payload.success, summary: payload.summary },
                  },
                };
              }
              return item;
            }),
          );
          break;
        }

        case 'agent/status': {
          const payload = msg.payload as AgentStatus & { cost?: number };
          setAgentStatus({ state: payload.state, detail: payload.detail });
          if (payload.state === 'streaming' || payload.state === 'thinking') {
            setIsStreaming(true);
          }
          if (payload.state === 'idle') {
            setIsStreaming(false);
          }
          if (payload.cost !== undefined) {
            setSession((s) => ({ ...s, cost: payload.cost! }));
          }
          break;
        }

        case 'session/cost': {
          const payload = msg.payload as { totalCost: number };
          setSession((s) => ({ ...s, cost: payload.totalCost }));
          break;
        }

        case 'webview/restored': {
          // Webview became visible again, nothing special needed
          break;
        }

        case 'context/activeFile': {
          const payload = msg.payload as { file: string | null };
          setActiveFile(payload.file);
          break;
        }

        case 'error': {
          const payload = msg.payload as { message: string };
          setItems((prev) => [
            ...prev,
            {
              kind: 'message',
              data: {
                id: `error_${Date.now()}`,
                role: 'assistant',
                content: `**Error:** ${payload.message}`,
              },
            },
          ]);
          setIsStreaming(false);
          currentAssistantIdRef.current = null;
          break;
        }
      }
    };

    window.addEventListener('message', handler);
    return () => window.removeEventListener('message', handler);
  }, [session.id]);

  // -------------------------------------------------------------------------
  // Send message
  // -------------------------------------------------------------------------

  const sendMessage = useCallback(() => {
    const text = inputText.trim();
    if (!text || isStreaming) { return; }

    // Add user message to items
    const userMsg: MessageData = {
      id: `user_${Date.now()}`,
      role: 'user',
      content: text,
    };
    setItems((prev) => [...prev, { kind: 'message', data: userMsg }]);
    setInputText('');
    setIsStreaming(true);
    currentAssistantIdRef.current = null;

    // Reset textarea height
    if (textareaRef.current) {
      textareaRef.current.style.height = 'auto';
    }

    // Post to extension host
    vscode.postMessage({
      type: 'sendPrompt',
      payload: {
        text,
        sessionId: session.id || undefined,
      },
    });
  }, [inputText, isStreaming, session.id]);

  const cancelStream = useCallback(() => {
    vscode.postMessage({ type: 'cancel' });
    setIsStreaming(false);
  }, []);

  // -------------------------------------------------------------------------
  // Tool approval handlers
  // -------------------------------------------------------------------------

  const handleApprove = useCallback((requestId: string) => {
    vscode.postMessage({
      type: 'approveToolUse',
      payload: { requestId, approved: true },
    });
  }, []);

  const handleDeny = useCallback((requestId: string) => {
    vscode.postMessage({
      type: 'approveToolUse',
      payload: { requestId, approved: false },
    });
  }, []);

  // -------------------------------------------------------------------------
  // Slash command handling
  // -------------------------------------------------------------------------

  const filteredCommands = SLASH_COMMANDS.filter((cmd) =>
    cmd.name.startsWith(slashFilter) || cmd.name.includes(slashFilter),
  );

  const handleInputChange = useCallback(
    (e: React.ChangeEvent<HTMLTextAreaElement>) => {
      const value = e.target.value;
      setInputText(value);

      // Show slash dropdown if input starts with /
      if (value.startsWith('/') && !value.includes(' ')) {
        setShowSlashDropdown(true);
        setSlashFilter(value);
        setSelectedSlashIdx(0);
      } else {
        setShowSlashDropdown(false);
      }
    },
    [],
  );

  const selectSlashCommand = useCallback(
    (cmd: SlashCommand) => {
      setInputText(cmd.name + ' ');
      setShowSlashDropdown(false);
      textareaRef.current?.focus();
    },
    [],
  );

  // -------------------------------------------------------------------------
  // Keyboard handling
  // -------------------------------------------------------------------------

  const handleKeyDown = useCallback(
    (e: React.KeyboardEvent<HTMLTextAreaElement>) => {
      // Slash dropdown navigation
      if (showSlashDropdown && filteredCommands.length > 0) {
        if (e.key === 'ArrowDown') {
          e.preventDefault();
          setSelectedSlashIdx((idx) => Math.min(idx + 1, filteredCommands.length - 1));
          return;
        }
        if (e.key === 'ArrowUp') {
          e.preventDefault();
          setSelectedSlashIdx((idx) => Math.max(idx - 1, 0));
          return;
        }
        if (e.key === 'Tab' || (e.key === 'Enter' && !e.shiftKey)) {
          e.preventDefault();
          selectSlashCommand(filteredCommands[selectedSlashIdx]);
          return;
        }
        if (e.key === 'Escape') {
          setShowSlashDropdown(false);
          return;
        }
      }

      // Enter to send, Shift+Enter for newline
      if (e.key === 'Enter' && !e.shiftKey) {
        e.preventDefault();
        sendMessage();
      }
    },
    [showSlashDropdown, filteredCommands, selectedSlashIdx, selectSlashCommand, sendMessage],
  );

  // -------------------------------------------------------------------------
  // Render
  // -------------------------------------------------------------------------

  const sessionLabel = session.id
    ? `Session: ${session.id.slice(0, 12)}... \u00B7 $${session.cost.toFixed(4)}`
    : 'New session';

  const statusDetail = agentStatus.detail || agentStatus.state;

  const isEmpty = items.length === 0;

  return (
    <div className="chat-container">
      {/* Session header */}
      <div className="session-header">
        <span className="session-info">{sessionLabel}</span>
        <div className="agent-status">
          <span className={`status-dot ${agentStatus.state}`} />
          <span>{statusDetail}</span>
        </div>
      </div>

      {/* Message list */}
      <div className="message-list" ref={messageListRef}>
        {isEmpty ? (
          <div className="empty-state">
            <h2>Rubyn Code</h2>
            <p>
              Ask me to write code, review PRs, refactor, explain, or generate specs.
              Type <code className="inline-code">/</code> for commands.
            </p>
          </div>
        ) : (
          items.map((item) => {
            if (item.kind === 'message') {
              return <Message key={item.data.id} message={item.data} />;
            }
            return (
              <ToolApproval
                key={item.data.requestId}
                requestId={item.data.requestId}
                tool={item.data.tool}
                args={item.data.args}
                requiresApproval={item.data.requiresApproval}
                result={item.data.result}
                onApprove={handleApprove}
                onDeny={handleDeny}
              />
            );
          })
        )}
      </div>

      {/* Input area */}
      <div className="input-area">
        {activeFile && (
          <div className="context-hint">
            Currently editing: {activeFile.split('/').pop()}
          </div>
        )}
        <div className="input-row">
          {/* Slash command dropdown */}
          {showSlashDropdown && filteredCommands.length > 0 && (
            <div className="slash-dropdown">
              {filteredCommands.map((cmd, idx) => (
                <div
                  key={cmd.name}
                  className={`slash-dropdown-item${idx === selectedSlashIdx ? ' selected' : ''}`}
                  onClick={() => selectSlashCommand(cmd)}
                  onMouseEnter={() => setSelectedSlashIdx(idx)}
                >
                  <span className="cmd-name">{cmd.name}</span>
                  <span className="cmd-desc">{cmd.description}</span>
                </div>
              ))}
            </div>
          )}

          <textarea
            ref={textareaRef}
            value={inputText}
            onChange={handleInputChange}
            onKeyDown={handleKeyDown}
            onInput={resizeTextarea}
            placeholder="Ask Rubyn Code..."
            rows={1}
            disabled={false}
          />

          {isStreaming ? (
            <button
              className="send-button cancel"
              onClick={cancelStream}
              title="Cancel"
            >
              &#x25A0;
            </button>
          ) : (
            <button
              className="send-button"
              onClick={sendMessage}
              disabled={!inputText.trim()}
              title="Send message"
            >
              &#x2191;
            </button>
          )}
        </div>
      </div>
    </div>
  );
};

// ---------------------------------------------------------------------------
// Mount
// ---------------------------------------------------------------------------

const container = document.getElementById('root');
if (container) {
  const root = createRoot(container);
  root.render(<Chat />);
}
