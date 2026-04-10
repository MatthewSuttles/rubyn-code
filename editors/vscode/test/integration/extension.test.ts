/**
 * Integration tests for the Rubyn Code VS Code extension.
 *
 * These tests exercise the full extension lifecycle by using a MockRubynProcess
 * that simulates the Rubyn Code CLI server's JSON-RPC behavior.
 *
 * Instead of mocking child_process, we directly create Bridge instances
 * connected to mock streams — testing the real Bridge, ContextProvider, and
 * StatusBar wired together.
 */

import { describe, it, expect, vi, beforeEach, afterEach } from 'vitest';
import { PassThrough } from 'stream';
import * as vscode from 'vscode';
import {
  __resetAll,
  __setConfig,
  Uri,
  Selection,
  Position,
} from '../helpers/mock-vscode';

import { Bridge } from '../../src/bridge';
import { ContextProvider } from '../../src/context-provider';
import { createStatusBar } from '../../src/status-bar';

// ---------------------------------------------------------------------------
// MockRubynProcess — simulates the CLI server
// ---------------------------------------------------------------------------

class MockRubynProcess {
  /** Extension writes requests here (bridge -> server). */
  readonly bridgeStdin = new PassThrough();
  /** Server writes responses/notifications here (server -> bridge). */
  readonly bridgeStdout = new PassThrough();

  private receivedMessages: Array<Record<string, unknown>> = [];

  constructor() {
    // Collect messages the bridge writes to us (via bridgeStdin)
    this.bridgeStdin.on('data', (chunk: Buffer | string) => {
      const text = typeof chunk === 'string' ? chunk : chunk.toString('utf-8');
      for (const line of text.split('\n')) {
        if (line.trim().length > 0) {
          try {
            this.receivedMessages.push(JSON.parse(line));
          } catch {
            // Ignore unparseable
          }
        }
      }
    });
  }

  /** Respond to a specific request ID. */
  respondTo(id: number, result: unknown): void {
    this.bridgeStdout.write(
      JSON.stringify({ jsonrpc: '2.0', id, result }) + '\n',
    );
  }

  /** Send a notification from the "server" to the extension. */
  sendNotification(method: string, params: Record<string, unknown>): void {
    this.bridgeStdout.write(
      JSON.stringify({ jsonrpc: '2.0', method, params }) + '\n',
    );
  }

  /** Send an error response for a specific request ID. */
  respondWithError(id: number, code: number, message: string): void {
    this.bridgeStdout.write(
      JSON.stringify({ jsonrpc: '2.0', id, error: { code, message } }) + '\n',
    );
  }

  /** Get all messages received from the extension (bridge). */
  getReceivedMessages(): Array<Record<string, unknown>> {
    return [...this.receivedMessages];
  }

  /** Find a received request by method name. */
  findRequest(method: string): Record<string, unknown> | undefined {
    return this.receivedMessages.find((m) => m.method === method);
  }

  /** Wait for a request with the given method to arrive. */
  async waitForRequest(method: string, timeoutMs = 1000): Promise<Record<string, unknown>> {
    const start = Date.now();
    while (Date.now() - start < timeoutMs) {
      const found = this.findRequest(method);
      if (found) return found;
      await new Promise((r) => setTimeout(r, 10));
    }
    throw new Error(`Timed out waiting for request: ${method}`);
  }

  /** Clear received messages (useful between sub-tests). */
  clearReceived(): void {
    this.receivedMessages = [];
  }
}

// ---------------------------------------------------------------------------
// Test suite
// ---------------------------------------------------------------------------

describe('Extension integration tests', () => {
  let mockServer: MockRubynProcess;
  let bridge: Bridge;
  let contextProvider: ContextProvider;
  let disposables: Array<{ dispose: () => void }>;

  /**
   * Simulate extension activation:
   * create bridge -> send initialize -> get response.
   */
  async function activateExtension() {
    mockServer = new MockRubynProcess();
    bridge = new Bridge(mockServer.bridgeStdin, mockServer.bridgeStdout);

    // Send initialize request (like the extension would)
    const initPromise = bridge.request('initialize', {
      workspacePath: '/workspace/my-app',
      extensionVersion: '0.1.0',
      capabilities: { inlineDiff: true, streaming: true },
    });

    // Wait for the request to arrive at the mock server, then respond
    const initReq = await mockServer.waitForRequest('initialize');
    mockServer.respondTo(initReq.id as number, {
      serverVersion: '1.0.0',
      capabilities: { tools: 10, skills: 5, memory: true, teams: false, review: true },
    });

    const initResult = await initPromise;
    expect(initResult).toEqual({
      serverVersion: '1.0.0',
      capabilities: { tools: 10, skills: 5, memory: true, teams: false, review: true },
    });

    contextProvider = new ContextProvider();

    disposables = [contextProvider, { dispose: () => bridge.dispose() }];
  }

  beforeEach(() => {
    __resetAll();

    __setConfig('rubyn-code', {
      executablePath: 'rubyn-code',
      yoloMode: false,
    });

    (vscode.workspace as any).workspaceFolders = [
      { uri: Uri.file('/workspace/my-app'), name: 'my-app', index: 0 },
    ];

    (vscode.workspace.fs.readFile as any).mockImplementation(async () => {
      throw new Error('ENOENT');
    });
    (vscode.workspace.fs.stat as any).mockImplementation(async () => {
      throw new Error('ENOENT');
    });

    disposables = [];
  });

  afterEach(() => {
    for (const d of disposables) {
      d.dispose();
    }
    __resetAll();
  });

  // -----------------------------------------------------------------------
  // Activation
  // -----------------------------------------------------------------------

  describe('activation', () => {
    it('initializes bridge with correct handshake', async () => {
      await activateExtension();
      // activateExtension already asserts the init result
    });

    it('sends initialize request with correct params', async () => {
      mockServer = new MockRubynProcess();
      bridge = new Bridge(mockServer.bridgeStdin, mockServer.bridgeStdout);
      disposables.push({ dispose: () => bridge.dispose() });

      bridge.request('initialize', {
        workspacePath: '/workspace/my-app',
        extensionVersion: '0.1.0',
        capabilities: { inlineDiff: true, streaming: true },
      }).catch(() => {});

      const initReq = await mockServer.waitForRequest('initialize');
      expect(initReq.method).toBe('initialize');
      expect((initReq.params as any).workspacePath).toBe('/workspace/my-app');
      expect((initReq.params as any).capabilities.inlineDiff).toBe(true);
      expect((initReq.params as any).capabilities.streaming).toBe(true);

      mockServer.respondTo(initReq.id as number, {
        serverVersion: '1.0.0',
        capabilities: { tools: 10, skills: 5, memory: true, teams: false, review: true },
      });
    });
  });

  // -----------------------------------------------------------------------
  // Prompt flow end-to-end
  // -----------------------------------------------------------------------

  describe('prompt flow end-to-end', () => {
    it('sends prompt and receives streaming notifications', async () => {
      await activateExtension();
      mockServer.clearReceived();

      const streamTexts: string[] = [];
      bridge.on('stream/text', (params: any) => {
        streamTexts.push(params?.delta ?? '');
      });

      const promptPromise = bridge.request('prompt', {
        text: 'Refactor this code',
        sessionId: 'test-session',
        context: { workspacePath: '/workspace/my-app' },
      });

      const promptReq = await mockServer.waitForRequest('prompt');
      expect(promptReq.method).toBe('prompt');
      expect((promptReq.params as any).text).toBe('Refactor this code');

      // Simulate streaming response
      mockServer.sendNotification('stream/text', {
        sessionId: 'test-session',
        delta: 'Here is ',
        done: false,
      });
      mockServer.sendNotification('stream/text', {
        sessionId: 'test-session',
        delta: 'the refactored code.',
        done: true,
      });

      // Respond to the prompt request
      mockServer.respondTo(promptReq.id as number, { success: true });

      const result = await promptPromise;
      expect(result).toEqual({ success: true });

      await new Promise((r) => setTimeout(r, 30));
      expect(streamTexts).toContain('Here is ');
      expect(streamTexts).toContain('the refactored code.');
    });
  });

  // -----------------------------------------------------------------------
  // Review flow
  // -----------------------------------------------------------------------

  describe('review flow', () => {
    it('sends review request and receives findings', async () => {
      await activateExtension();
      mockServer.clearReceived();

      const findings: Array<Record<string, unknown>> = [];
      bridge.on('review/finding', (params: any) => {
        findings.push(params);
      });

      const reviewPromise = bridge.request('review', {
        baseBranch: 'main',
        focus: 'all',
      });

      const reviewReq = await mockServer.waitForRequest('review');
      expect((reviewReq.params as any).baseBranch).toBe('main');

      mockServer.sendNotification('review/finding', {
        severity: 'warning',
        file: 'app/models/user.rb',
        line: 15,
        message: 'N+1 query detected',
        suggestion: 'Use includes(:posts)',
      });

      mockServer.sendNotification('review/finding', {
        severity: 'error',
        file: 'app/controllers/users_controller.rb',
        line: 42,
        message: 'Missing authorization check',
      });

      mockServer.respondTo(reviewReq.id as number, { findingsCount: 2 });

      const result = await reviewPromise;
      expect(result).toEqual({ findingsCount: 2 });

      await new Promise((r) => setTimeout(r, 30));
      expect(findings).toHaveLength(2);
      expect(findings[0].severity).toBe('warning');
      expect(findings[1].severity).toBe('error');
    });
  });

  // -----------------------------------------------------------------------
  // Tool approval flow
  // -----------------------------------------------------------------------

  describe('tool approval flow', () => {
    it('receives tool/use and sends approval notification', async () => {
      await activateExtension();
      mockServer.clearReceived();

      const toolUses: Array<Record<string, unknown>> = [];
      bridge.on('tool/use', (params: any) => {
        toolUses.push(params);
      });

      mockServer.sendNotification('tool/use', {
        requestId: 'tool-req-1',
        tool: 'write_file',
        args: { path: '/workspace/app/models/user.rb', content: '...' },
        requiresApproval: true,
      });

      await new Promise((r) => setTimeout(r, 30));
      expect(toolUses).toHaveLength(1);
      expect(toolUses[0].tool).toBe('write_file');

      // Extension approves the tool use
      bridge.notify('tool/approve', {
        requestId: 'tool-req-1',
        approved: true,
      });

      await new Promise((r) => setTimeout(r, 20));

      const allMsgs = mockServer.getReceivedMessages();
      const approval = allMsgs.find(
        (m) => m.method === 'tool/approve' && (m.params as any)?.requestId === 'tool-req-1',
      );
      expect(approval).toBeDefined();
      expect((approval!.params as any).approved).toBe(true);
    });

    it('receives tool/result after tool execution', async () => {
      await activateExtension();

      const results: Array<Record<string, unknown>> = [];
      bridge.on('tool/result', (params: any) => {
        results.push(params);
      });

      mockServer.sendNotification('tool/result', {
        requestId: 'tool-req-1',
        tool: 'write_file',
        success: true,
        summary: 'File written successfully',
      });

      await new Promise((r) => setTimeout(r, 30));
      expect(results).toHaveLength(1);
      expect(results[0].success).toBe(true);
      expect(results[0].summary).toBe('File written successfully');
    });
  });

  // -----------------------------------------------------------------------
  // Shutdown
  // -----------------------------------------------------------------------

  describe('shutdown', () => {
    it('sends shutdown request during graceful shutdown', async () => {
      await activateExtension();
      mockServer.clearReceived();

      const shutdownPromise = bridge.request('shutdown', undefined, 3000);

      const shutdownReq = await mockServer.waitForRequest('shutdown');
      mockServer.respondTo(shutdownReq.id as number, null);

      await shutdownPromise;
    });
  });

  // -----------------------------------------------------------------------
  // Bridge close
  // -----------------------------------------------------------------------

  describe('bridge close / process crash', () => {
    it('emits close event when stdout ends', async () => {
      await activateExtension();

      const closeHandler = vi.fn();
      bridge.on('close', closeHandler);

      mockServer.bridgeStdout.end();

      await new Promise((r) => setTimeout(r, 30));
      expect(closeHandler).toHaveBeenCalledOnce();
    });

    it('rejects pending requests when connection closes', async () => {
      await activateExtension();
      mockServer.clearReceived();

      const pendingPromise = bridge.request('prompt', {
        text: 'test',
        sessionId: 's1',
        context: { workspacePath: '/workspace/my-app' },
      }, 5000);

      // Close the connection before responding
      mockServer.bridgeStdout.end();

      await expect(pendingPromise).rejects.toThrow('Server process exited');
    });
  });

  // -----------------------------------------------------------------------
  // Context enrichment
  // -----------------------------------------------------------------------

  describe('context enrichment in command flow', () => {
    it('enriches prompt with active file and project context', async () => {
      await activateExtension();

      (vscode.window as any).activeTextEditor = {
        document: {
          uri: Uri.file('/workspace/my-app/app/models/user.rb'),
          languageId: 'ruby',
          getText: vi.fn(() => 'class User\nend'),
        },
        selection: new Selection(
          new Position(0, 0),
          new Position(1, 3),
        ),
      };

      const { prompt, context, project } = await contextProvider.enrichPrompt(
        'refactorSelection',
        'Improve this code',
      );

      expect(context.activeFile).toBe('app/models/user.rb');
      expect(context.language).toBe('ruby');
      expect(prompt).toContain('[File] app/models/user.rb');
      expect(prompt).toContain('Improve this code');
    });
  });

  // -----------------------------------------------------------------------
  // Multiple notification types in sequence
  // -----------------------------------------------------------------------

  describe('mixed notification flow', () => {
    it('handles interleaved agent/status and stream/text notifications', async () => {
      await activateExtension();

      const statuses: string[] = [];
      const texts: string[] = [];

      bridge.on('agent/status', (params: any) => {
        statuses.push(params?.state);
      });
      bridge.on('stream/text', (params: any) => {
        texts.push(params?.delta);
      });

      mockServer.sendNotification('agent/status', { state: 'thinking' });
      mockServer.sendNotification('agent/status', { state: 'streaming' });
      mockServer.sendNotification('stream/text', { sessionId: 's1', delta: 'Hello', done: false });
      mockServer.sendNotification('stream/text', { sessionId: 's1', delta: ' World', done: true });
      mockServer.sendNotification('agent/status', { state: 'idle' });

      await new Promise((r) => setTimeout(r, 50));

      expect(statuses).toEqual(['thinking', 'streaming', 'idle']);
      expect(texts).toEqual(['Hello', ' World']);
    });
  });

  // -----------------------------------------------------------------------
  // Error handling
  // -----------------------------------------------------------------------

  describe('error handling', () => {
    it('handles RPC error responses gracefully', async () => {
      await activateExtension();
      mockServer.clearReceived();

      const promptPromise = bridge.request('prompt', {
        text: 'test',
        sessionId: 's1',
        context: { workspacePath: '/workspace/my-app' },
      });

      const req = await mockServer.waitForRequest('prompt');
      mockServer.respondWithError(req.id as number, -32000, 'Budget exceeded');

      await expect(promptPromise).rejects.toThrow('Budget exceeded');
    });

    it('handles malformed server responses without crashing', async () => {
      await activateExtension();

      const errorHandler = vi.fn();
      bridge.on('error', errorHandler);

      // Server sends garbage
      mockServer.bridgeStdout.write('not json at all\n');

      await new Promise((r) => setTimeout(r, 20));
      expect(errorHandler).toHaveBeenCalled();

      // Bridge should still work after that
      mockServer.clearReceived();
      const reqPromise = bridge.request('test', { a: 1 });
      const req = await mockServer.waitForRequest('test');
      mockServer.respondTo(req.id as number, 'still works');
      expect(await reqPromise).toBe('still works');
    });
  });

  // -----------------------------------------------------------------------
  // Status bar integration
  // -----------------------------------------------------------------------

  describe('status bar integration', () => {
    it('wires status bar to bridge notifications', async () => {
      await activateExtension();

      // createStatusBar registers listeners and returns a disposable
      const statusDisposable = createStatusBar(bridge);
      disposables.push(statusDisposable);

      // Send agent status notification - should not throw
      mockServer.sendNotification('agent/status', {
        state: 'thinking',
        toolCalls: 5,
        tokensUsed: 10000,
        cost: 0.05,
      });

      mockServer.sendNotification('session/cost', {
        inputTokens: 10000,
        outputTokens: 5000,
        cacheHits: 1000,
        totalCost: 0.05,
        sessionBudget: 5.0,
        budgetRemaining: 4.95,
      });

      await new Promise((r) => setTimeout(r, 30));
      // If we get here without error, the wiring works
    });
  });
});
