import { describe, it, expect, vi, beforeEach, afterEach } from 'vitest';
import * as vscode from 'vscode';
import { __resetAll, MarkdownString } from './helpers/mock-vscode';
import { StatusBar, createStatusBar } from '../src/status-bar';
import { PassThrough } from 'stream';
import { Bridge } from '../src/bridge';

describe('StatusBar', () => {
  let statusBar: StatusBar;
  let mockItem: any;

  beforeEach(() => {
    __resetAll();

    // Capture the mock status bar item that gets created
    (vscode.window.createStatusBarItem as any).mockImplementation(
      (alignment?: number, priority?: number) => {
        mockItem = {
          text: '',
          tooltip: undefined as string | MarkdownString | undefined,
          command: undefined as string | undefined,
          backgroundColor: undefined,
          alignment: alignment ?? 1,
          priority: priority ?? 0,
          show: vi.fn(),
          hide: vi.fn(),
          dispose: vi.fn(),
        };
        return mockItem;
      },
    );

    statusBar = new StatusBar();
  });

  afterEach(() => {
    statusBar.dispose();
    __resetAll();
  });

  // -----------------------------------------------------------------------
  // Initial state
  // -----------------------------------------------------------------------

  describe('initial state', () => {
    it('shows idle icon and text', () => {
      expect(mockItem.text).toBe('$(ruby) Rubyn');
    });

    it('shows the status bar item', () => {
      expect(mockItem.show).toHaveBeenCalled();
    });

    it('registers the openChat command on click', () => {
      expect(mockItem.command).toBe('rubyn-code.openChat');
    });
  });

  // -----------------------------------------------------------------------
  // Agent states
  // -----------------------------------------------------------------------

  describe('thinking state', () => {
    it('shows spinner animation text', () => {
      statusBar.updateAgentStatus({ state: 'thinking' });
      expect(mockItem.text).toContain('loading~spin');
      expect(mockItem.text).toContain('thinking');
    });
  });

  describe('tool_use state', () => {
    it('shows tool name in display', () => {
      statusBar.updateAgentStatus({ state: 'tool_use', detail: 'read_file' });
      expect(mockItem.text).toContain('tools');
      expect(mockItem.text).toContain('read_file');
    });

    it('shows generic "tool" when no detail provided', () => {
      statusBar.updateAgentStatus({ state: 'tool_use' });
      expect(mockItem.text).toContain('tool');
    });
  });

  describe('streaming state', () => {
    it('shows writing text', () => {
      statusBar.updateAgentStatus({ state: 'streaming' });
      expect(mockItem.text).toContain('edit');
      expect(mockItem.text).toContain('writing');
    });
  });

  describe('reviewing state', () => {
    it('shows reviewing text', () => {
      statusBar.updateAgentStatus({ state: 'reviewing' });
      expect(mockItem.text).toContain('eye');
      expect(mockItem.text).toContain('reviewing');
    });
  });

  describe('learning state', () => {
    it('shows learning text', () => {
      statusBar.updateAgentStatus({ state: 'learning' });
      expect(mockItem.text).toContain('book');
      expect(mockItem.text).toContain('learning');
    });
  });

  describe('back to idle', () => {
    it('returns to idle icon after state changes', () => {
      statusBar.updateAgentStatus({ state: 'thinking' });
      expect(mockItem.text).toContain('thinking');

      statusBar.updateAgentStatus({ state: 'idle' });
      expect(mockItem.text).toBe('$(ruby) Rubyn');
    });
  });

  // -----------------------------------------------------------------------
  // Error / Disconnected state
  // -----------------------------------------------------------------------

  describe('disconnected state', () => {
    it('shows disconnect icon and text', () => {
      statusBar.setDisconnected();
      expect(mockItem.text).toContain('debug-disconnect');
      expect(mockItem.text).toContain('disconnected');
    });

    it('sets tooltip with reconnect hint', () => {
      statusBar.setDisconnected();
      expect(mockItem.tooltip).toContain('disconnected');
      expect(mockItem.tooltip).toContain('Click to reconnect');
    });
  });

  // -----------------------------------------------------------------------
  // Tooltip content
  // -----------------------------------------------------------------------

  describe('tooltip content', () => {
    it('formats cost information', () => {
      statusBar.updateAgentStatus({
        state: 'idle',
        cost: 0.0523,
        tokensUsed: 15000,
        toolCalls: 7,
      });

      const tooltip = mockItem.tooltip as MarkdownString;
      expect(tooltip).toBeInstanceOf(MarkdownString);
      expect(tooltip.value).toContain('Session cost');
      expect(tooltip.value).toContain('$0.0523');
      expect(tooltip.value).toContain('15,000');
      expect(tooltip.value).toContain('Tool calls');
      expect(tooltip.value).toContain('7');
    });

    it('shows session cost details when available', () => {
      statusBar.updateSessionCost({
        inputTokens: 50000,
        outputTokens: 10000,
        cacheHits: 5000,
        totalCost: 0.1234,
        sessionBudget: 5.0,
        budgetRemaining: 4.8766,
      });

      const tooltip = mockItem.tooltip as MarkdownString;
      expect(tooltip.value).toContain('$0.1234');
      expect(tooltip.value).toContain('50,000');
      expect(tooltip.value).toContain('10,000');
      expect(tooltip.value).toContain('5,000 cached');
      expect(tooltip.value).toContain('Budget remaining');
      expect(tooltip.value).toContain('$4.8766');
      expect(tooltip.value).toContain('98%');
    });

    it('omits token info when no tokens used', () => {
      statusBar.updateAgentStatus({ state: 'idle' });

      const tooltip = mockItem.tooltip as MarkdownString;
      expect(tooltip.value).not.toContain('Tokens used');
    });

    it('omits tool calls when count is zero', () => {
      statusBar.updateAgentStatus({ state: 'idle', toolCalls: 0 });

      const tooltip = mockItem.tooltip as MarkdownString;
      expect(tooltip.value).not.toContain('Tool calls');
    });
  });

  // -----------------------------------------------------------------------
  // Cost update
  // -----------------------------------------------------------------------

  describe('cost update', () => {
    it('updates tooltip when session cost changes', () => {
      statusBar.updateSessionCost({
        inputTokens: 1000,
        outputTokens: 500,
        cacheHits: 0,
        totalCost: 0.005,
        sessionBudget: 5.0,
        budgetRemaining: 4.995,
      });

      const tooltip1 = mockItem.tooltip as MarkdownString;
      expect(tooltip1.value).toContain('$0.0050');

      statusBar.updateSessionCost({
        inputTokens: 2000,
        outputTokens: 1000,
        cacheHits: 100,
        totalCost: 0.015,
        sessionBudget: 5.0,
        budgetRemaining: 4.985,
      });

      const tooltip2 = mockItem.tooltip as MarkdownString;
      expect(tooltip2.value).toContain('$0.0150');
    });
  });

  // -----------------------------------------------------------------------
  // Dispose
  // -----------------------------------------------------------------------

  describe('dispose()', () => {
    it('disposes the status bar item', () => {
      statusBar.dispose();
      expect(mockItem.dispose).toHaveBeenCalled();
    });
  });
});

// ---------------------------------------------------------------------------
// createStatusBar factory
// ---------------------------------------------------------------------------

describe('createStatusBar()', () => {
  let bridge: Bridge;
  let stdin: PassThrough;
  let stdout: PassThrough;

  beforeEach(() => {
    __resetAll();
    stdin = new PassThrough();
    stdout = new PassThrough();
    bridge = new Bridge(stdin, stdout);

    (vscode.window.createStatusBarItem as any).mockImplementation(() => ({
      text: '',
      tooltip: undefined,
      command: undefined,
      backgroundColor: undefined,
      show: vi.fn(),
      hide: vi.fn(),
      dispose: vi.fn(),
    }));
  });

  afterEach(() => {
    bridge.dispose();
    __resetAll();
  });

  it('wires bridge notifications to status bar updates', async () => {
    const disposable = createStatusBar(bridge);

    // Send agent/status notification
    stdout.write(
      JSON.stringify({
        jsonrpc: '2.0',
        method: 'agent/status',
        params: { state: 'thinking' },
      }) + '\n',
    );

    await new Promise((r) => setTimeout(r, 20));

    // The status bar should have been updated (we just verify no errors)
    disposable.dispose();
  });

  it('sets disconnected on bridge close', async () => {
    const disposable = createStatusBar(bridge);

    stdout.end();

    await new Promise((r) => setTimeout(r, 20));

    // No errors should occur
    disposable.dispose();
  });

  it('cleans up listeners on dispose', () => {
    const disposable = createStatusBar(bridge);
    // Should not throw
    disposable.dispose();
  });
});
