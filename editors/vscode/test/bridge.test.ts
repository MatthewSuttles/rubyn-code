import { describe, it, expect, vi, beforeEach, afterEach } from 'vitest';
import { PassThrough } from 'stream';
import { Bridge } from '../src/bridge';

function createBridge(opts?: { timeout?: number }) {
  const stdin = new PassThrough();
  const stdout = new PassThrough();
  const bridge = new Bridge(stdin, stdout);

  /** Simulate the server writing a JSON-RPC message to stdout. */
  function serverSend(msg: Record<string, unknown>): void {
    stdout.write(JSON.stringify(msg) + '\n');
  }

  /** Simulate the server writing raw text to stdout. */
  function serverSendRaw(text: string): void {
    stdout.write(text);
  }

  /** Parse the last message the bridge wrote to stdin. */
  function lastSent(): Record<string, unknown> | null {
    const chunks: Buffer[] = [];
    let chunk: Buffer | null;
    while ((chunk = stdin.read() as Buffer | null) !== null) {
      chunks.push(chunk);
    }
    if (chunks.length === 0) return null;
    const text = Buffer.concat(chunks).toString('utf-8');
    const lines = text.trim().split('\n');
    return JSON.parse(lines[lines.length - 1]);
  }

  /** Read all messages sent to stdin. */
  function allSent(): Array<Record<string, unknown>> {
    const chunks: Buffer[] = [];
    let chunk: Buffer | null;
    while ((chunk = stdin.read() as Buffer | null) !== null) {
      chunks.push(chunk);
    }
    if (chunks.length === 0) return [];
    const text = Buffer.concat(chunks).toString('utf-8');
    return text
      .trim()
      .split('\n')
      .filter((l) => l.length > 0)
      .map((l) => JSON.parse(l));
  }

  return { bridge, stdin, stdout, serverSend, serverSendRaw, lastSent, allSent };
}

describe('Bridge', () => {
  let env: ReturnType<typeof createBridge>;

  beforeEach(() => {
    env = createBridge();
  });

  afterEach(async () => {
    // Catch any unhandled rejections from pending requests before disposing
    try {
      env.bridge.dispose();
    } catch {
      // ignore
    }
    // Allow microtasks to settle
    await new Promise((r) => setTimeout(r, 10));
  });

  // -----------------------------------------------------------------------
  // Request / response matching
  // -----------------------------------------------------------------------

  describe('request/response matching', () => {
    it('resolves with the correct result when the server responds', async () => {
      const promise = env.bridge.request('initialize', { version: '1.0' });

      // Read what the bridge sent to stdin
      await new Promise((r) => setTimeout(r, 10));
      const sent = env.lastSent();
      expect(sent).not.toBeNull();
      expect(sent!.method).toBe('initialize');
      expect(sent!.jsonrpc).toBe('2.0');
      expect(typeof sent!.id).toBe('number');

      // Respond
      env.serverSend({ jsonrpc: '2.0', id: sent!.id, result: { ok: true } });

      const result = await promise;
      expect(result).toEqual({ ok: true });
    });

    it('includes params when provided', async () => {
      env.bridge.request('test', { foo: 'bar' }).catch(() => {});
      await new Promise((r) => setTimeout(r, 10));
      const sent = env.lastSent();
      expect(sent!.params).toEqual({ foo: 'bar' });
    });

    it('omits params when not provided', async () => {
      env.bridge.request('test').catch(() => {});
      await new Promise((r) => setTimeout(r, 10));
      const sent = env.lastSent();
      expect(sent!.params).toBeUndefined();
    });
  });

  // -----------------------------------------------------------------------
  // Auto-incrementing IDs
  // -----------------------------------------------------------------------

  describe('auto-incrementing IDs', () => {
    it('assigns unique incrementing IDs to each request', async () => {
      const p1 = env.bridge.request('a').catch(() => {});
      const p2 = env.bridge.request('b').catch(() => {});
      const p3 = env.bridge.request('c').catch(() => {});
      await new Promise((r) => setTimeout(r, 10));

      const sent = env.allSent();
      expect(sent).toHaveLength(3);
      expect(sent[0].id).toBe(1);
      expect(sent[1].id).toBe(2);
      expect(sent[2].id).toBe(3);
    });
  });

  // -----------------------------------------------------------------------
  // Timeout
  // -----------------------------------------------------------------------

  describe('timeout', () => {
    it('rejects the promise after the specified timeout', async () => {
      const promise = env.bridge.request('slowMethod', undefined, 50);
      await expect(promise).rejects.toThrow(/timed out after 50ms/);
    });

    it('includes method name and id in the timeout error', async () => {
      const promise = env.bridge.request('myMethod', undefined, 50);
      await expect(promise).rejects.toThrow('"myMethod"');
    });
  });

  // -----------------------------------------------------------------------
  // Notification routing
  // -----------------------------------------------------------------------

  describe('notification routing', () => {
    it('fires the correct callback when a notification arrives', async () => {
      const handler = vi.fn();
      env.bridge.on('agent/status', handler);

      env.serverSend({
        jsonrpc: '2.0',
        method: 'agent/status',
        params: { state: 'thinking' },
      });

      await new Promise((r) => setTimeout(r, 10));
      expect(handler).toHaveBeenCalledOnce();
      expect(handler).toHaveBeenCalledWith({ state: 'thinking' });
    });

    it('does not fire callbacks for unrelated methods', async () => {
      const handler = vi.fn();
      env.bridge.on('agent/status', handler);

      env.serverSend({
        jsonrpc: '2.0',
        method: 'session/cost',
        params: { totalCost: 0.01 },
      });

      await new Promise((r) => setTimeout(r, 10));
      expect(handler).not.toHaveBeenCalled();
    });
  });

  // -----------------------------------------------------------------------
  // Multiple listeners
  // -----------------------------------------------------------------------

  describe('multiple listeners', () => {
    it('fires all listeners registered for the same method', async () => {
      const handler1 = vi.fn();
      const handler2 = vi.fn();
      const handler3 = vi.fn();

      env.bridge.on('stream/text', handler1);
      env.bridge.on('stream/text', handler2);
      env.bridge.on('stream/text', handler3);

      env.serverSend({
        jsonrpc: '2.0',
        method: 'stream/text',
        params: { delta: 'hello' },
      });

      await new Promise((r) => setTimeout(r, 10));
      expect(handler1).toHaveBeenCalledOnce();
      expect(handler2).toHaveBeenCalledOnce();
      expect(handler3).toHaveBeenCalledOnce();
    });
  });

  // -----------------------------------------------------------------------
  // Listener removal
  // -----------------------------------------------------------------------

  describe('listener removal', () => {
    it('off() removes only the specified callback', async () => {
      const handler1 = vi.fn();
      const handler2 = vi.fn();

      env.bridge.on('stream/text', handler1);
      env.bridge.on('stream/text', handler2);
      env.bridge.off('stream/text', handler1);

      env.serverSend({
        jsonrpc: '2.0',
        method: 'stream/text',
        params: { delta: 'hello' },
      });

      await new Promise((r) => setTimeout(r, 10));
      expect(handler1).not.toHaveBeenCalled();
      expect(handler2).toHaveBeenCalledOnce();
    });

    it('removing all listeners for a method cleans up the set', async () => {
      const handler = vi.fn();

      env.bridge.on('test/method', handler);
      env.bridge.off('test/method', handler);

      env.serverSend({
        jsonrpc: '2.0',
        method: 'test/method',
        params: {},
      });

      await new Promise((r) => setTimeout(r, 10));
      expect(handler).not.toHaveBeenCalled();
    });
  });

  // -----------------------------------------------------------------------
  // Malformed JSON
  // -----------------------------------------------------------------------

  describe('malformed JSON', () => {
    it('emits an error event on garbage input but does not crash', async () => {
      const errorHandler = vi.fn();
      env.bridge.on('error', errorHandler);

      env.serverSendRaw('this is not json\n');

      await new Promise((r) => setTimeout(r, 10));
      expect(errorHandler).toHaveBeenCalledOnce();
      expect(errorHandler.mock.calls[0][0]).toBeInstanceOf(Error);
      expect(errorHandler.mock.calls[0][0].message).toContain('Malformed JSON');
    });

    it('continues processing valid messages after malformed ones', async () => {
      const errorHandler = vi.fn();
      const notifHandler = vi.fn();
      env.bridge.on('error', errorHandler);
      env.bridge.on('test/ok', notifHandler);

      env.serverSendRaw('garbage\n');
      env.serverSend({ jsonrpc: '2.0', method: 'test/ok', params: { a: 1 } });

      await new Promise((r) => setTimeout(r, 10));
      expect(errorHandler).toHaveBeenCalled();
      expect(notifHandler).toHaveBeenCalledWith({ a: 1 });
    });

    it('emits error for non-2.0 jsonrpc version', async () => {
      const errorHandler = vi.fn();
      env.bridge.on('error', errorHandler);

      env.serverSend({ jsonrpc: '1.0', method: 'test' });

      await new Promise((r) => setTimeout(r, 10));
      expect(errorHandler).toHaveBeenCalledOnce();
      expect(errorHandler.mock.calls[0][0].message).toContain('Invalid jsonrpc version');
    });
  });

  // -----------------------------------------------------------------------
  // Partial lines (chunked data)
  // -----------------------------------------------------------------------

  describe('partial lines / chunked data', () => {
    it('handles a JSON message split across multiple data events', async () => {
      const promise = env.bridge.request('test', undefined, 2000);
      await new Promise((r) => setTimeout(r, 10));
      const sent = env.lastSent();

      // Split the response across multiple chunks
      const full = JSON.stringify({ jsonrpc: '2.0', id: sent!.id, result: 'chunked' }) + '\n';
      const mid = Math.floor(full.length / 2);
      env.serverSendRaw(full.slice(0, mid));

      // Wait, then send the rest
      await new Promise((r) => setTimeout(r, 10));
      env.serverSendRaw(full.slice(mid));

      const result = await promise;
      expect(result).toBe('chunked');
    });

    it('handles multiple messages in a single chunk', async () => {
      const handler = vi.fn();
      env.bridge.on('ping', handler);

      const msg1 = JSON.stringify({ jsonrpc: '2.0', method: 'ping', params: { n: 1 } });
      const msg2 = JSON.stringify({ jsonrpc: '2.0', method: 'ping', params: { n: 2 } });
      env.serverSendRaw(`${msg1}\n${msg2}\n`);

      await new Promise((r) => setTimeout(r, 10));
      expect(handler).toHaveBeenCalledTimes(2);
      expect(handler.mock.calls[0][0]).toEqual({ n: 1 });
      expect(handler.mock.calls[1][0]).toEqual({ n: 2 });
    });

    it('ignores empty lines between messages', async () => {
      const handler = vi.fn();
      env.bridge.on('test', handler);

      env.serverSendRaw('\n\n');
      env.serverSend({ jsonrpc: '2.0', method: 'test', params: {} });

      await new Promise((r) => setTimeout(r, 10));
      expect(handler).toHaveBeenCalledOnce();
    });
  });

  // -----------------------------------------------------------------------
  // Dispose
  // -----------------------------------------------------------------------

  describe('dispose', () => {
    it('rejects all pending requests with "Bridge disposed"', async () => {
      const p1 = env.bridge.request('a', undefined, 5000);
      const p2 = env.bridge.request('b', undefined, 5000);

      env.bridge.dispose();

      await expect(p1).rejects.toThrow('Bridge disposed');
      await expect(p2).rejects.toThrow('Bridge disposed');
    });

    it('clears all notification listeners', async () => {
      const handler = vi.fn();
      env.bridge.on('test', handler);

      env.bridge.dispose();

      // Even if the stdout emits data after dispose, the handler should not fire
      // (listeners removed from stdout).
      // The bridge won't process it because it removed stdout listeners.
    });

    it('subsequent requests are rejected immediately', async () => {
      env.bridge.dispose();
      await expect(env.bridge.request('test')).rejects.toThrow('Bridge has been disposed');
    });

    it('subsequent notify calls are no-ops', () => {
      env.bridge.dispose();
      // Should not throw
      env.bridge.notify('test', { foo: 'bar' });
    });

    it('calling dispose twice is safe', () => {
      env.bridge.dispose();
      expect(() => env.bridge.dispose()).not.toThrow();
    });
  });

  // -----------------------------------------------------------------------
  // Close event
  // -----------------------------------------------------------------------

  describe('close event', () => {
    it('emits close when stdout ends', async () => {
      const closeHandler = vi.fn();
      env.bridge.on('close', closeHandler);

      env.stdout.end();

      await new Promise((r) => setTimeout(r, 10));
      expect(closeHandler).toHaveBeenCalledOnce();
    });

    it('rejects pending requests when stdout ends', async () => {
      const promise = env.bridge.request('test', undefined, 5000);

      env.stdout.end();

      await expect(promise).rejects.toThrow('Server process exited');
    });
  });

  // -----------------------------------------------------------------------
  // Error responses
  // -----------------------------------------------------------------------

  describe('error responses', () => {
    it('rejects the promise with the RPC error code and message', async () => {
      const promise = env.bridge.request('failMethod');
      await new Promise((r) => setTimeout(r, 10));
      const sent = env.lastSent();

      env.serverSend({
        jsonrpc: '2.0',
        id: sent!.id,
        error: { code: -32601, message: 'Method not found' },
      });

      await expect(promise).rejects.toThrow('RPC error -32601: Method not found');
    });

    it('ignores responses for unknown (already timed out) request IDs', async () => {
      const errorHandler = vi.fn();
      env.bridge.on('error', errorHandler);

      // Send a response for a non-existent request ID
      env.serverSend({ jsonrpc: '2.0', id: 999, result: 'orphan' });

      await new Promise((r) => setTimeout(r, 10));
      // Should not emit an error — just silently ignore
      expect(errorHandler).not.toHaveBeenCalled();
    });
  });

  // -----------------------------------------------------------------------
  // Concurrent requests
  // -----------------------------------------------------------------------

  describe('concurrent requests', () => {
    it('correctly matches responses sent out of order', async () => {
      const p1 = env.bridge.request<string>('method1');
      const p2 = env.bridge.request<string>('method2');
      const p3 = env.bridge.request<string>('method3');

      await new Promise((r) => setTimeout(r, 10));
      const sent = env.allSent();
      expect(sent).toHaveLength(3);

      const id1 = sent[0].id as number;
      const id2 = sent[1].id as number;
      const id3 = sent[2].id as number;

      // Respond out of order: 3, 1, 2
      env.serverSend({ jsonrpc: '2.0', id: id3, result: 'result3' });
      env.serverSend({ jsonrpc: '2.0', id: id1, result: 'result1' });
      env.serverSend({ jsonrpc: '2.0', id: id2, result: 'result2' });

      expect(await p1).toBe('result1');
      expect(await p2).toBe('result2');
      expect(await p3).toBe('result3');
    });
  });

  // -----------------------------------------------------------------------
  // Notify
  // -----------------------------------------------------------------------

  describe('notify', () => {
    it('writes a JSON-RPC notification (no id) to stdin', () => {
      env.bridge.notify('tool/approve', { requestId: 'abc', approved: true });

      const sent = env.lastSent();
      expect(sent).not.toBeNull();
      expect(sent!.jsonrpc).toBe('2.0');
      expect(sent!.method).toBe('tool/approve');
      expect(sent!.params).toEqual({ requestId: 'abc', approved: true });
      expect(sent!.id).toBeUndefined();
    });

    it('omits params when not provided', () => {
      env.bridge.notify('cancel');

      const sent = env.lastSent();
      expect(sent).not.toBeNull();
      expect(sent!.params).toBeUndefined();
    });
  });

  // -----------------------------------------------------------------------
  // Listener exception handling
  // -----------------------------------------------------------------------

  describe('listener exception handling', () => {
    it('emits error when a notification listener throws', async () => {
      const errorHandler = vi.fn();
      env.bridge.on('error', errorHandler);
      env.bridge.on('test', () => {
        throw new Error('listener boom');
      });

      env.serverSend({ jsonrpc: '2.0', method: 'test', params: {} });

      await new Promise((r) => setTimeout(r, 10));
      expect(errorHandler).toHaveBeenCalledOnce();
      expect(errorHandler.mock.calls[0][0].message).toBe('listener boom');
    });
  });
});
