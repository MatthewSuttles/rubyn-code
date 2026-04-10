/**
 * Rubyn Code JSON-RPC bridge.
 *
 * Communicates with the Rubyn Code CLI process over stdin (Writable) and
 * stdout (Readable) using newline-delimited JSON-RPC 2.0 messages.
 */

import { Readable, Writable } from 'stream';
import { EventEmitter } from 'events';
import {
  RpcRequest,
  RpcResponse,
  RpcNotification,
  RpcError,
} from './types';

/** Default timeout for request() calls (30 seconds). */
const REQUEST_TIMEOUT_MS = 30_000;

/** Callback shape for notification listeners. */
type NotificationListener = (params: Record<string, unknown> | undefined) => void;

interface PendingRequest {
  resolve: (result: unknown) => void;
  reject: (error: Error) => void;
  timer: ReturnType<typeof setTimeout>;
}

/**
 * Bidirectional JSON-RPC 2.0 bridge over stdio streams.
 *
 * Events:
 *   - `error`  — emitted on protocol-level errors (malformed JSON, etc.)
 *   - `close`  — emitted when the stdout stream ends
 */
export class Bridge extends EventEmitter {
  private readonly stdin: Writable;
  private readonly stdout: Readable;

  /** Auto-incrementing request id counter. */
  private nextId = 1;

  /** Pending request promises keyed by request id. */
  private pending = new Map<number, PendingRequest>();

  /** Notification listeners keyed by method name. */
  private notificationListeners = new Map<string, Set<NotificationListener>>();

  /** Partial line buffer for stdout parsing. */
  private buffer = '';

  /** Whether dispose() has been called. */
  private disposed = false;

  constructor(stdin: Writable, stdout: Readable) {
    super();
    this.stdin = stdin;
    this.stdout = stdout;

    this.stdout.on('data', (chunk: Buffer | string) => this.onData(chunk));
    this.stdout.on('end', () => this.onClose());
    this.stdout.on('error', (err: Error) => this.emit('error', err));
  }

  // -------------------------------------------------------------------------
  // Public API
  // -------------------------------------------------------------------------

  /**
   * Send a JSON-RPC request and wait for the matching response.
   *
   * Rejects if no response arrives within `timeoutMs` (default 30 s) or if
   * the server returns an RPC error.
   */
  request<T = unknown>(
    method: string,
    params?: Record<string, unknown>,
    timeoutMs: number = REQUEST_TIMEOUT_MS,
  ): Promise<T> {
    if (this.disposed) {
      return Promise.reject(new Error('Bridge has been disposed'));
    }

    const id = this.nextId++;
    const msg: RpcRequest = { jsonrpc: '2.0', id, method };
    if (params !== undefined) {
      msg.params = params;
    }

    return new Promise<T>((resolve, reject) => {
      const timer = setTimeout(() => {
        this.pending.delete(id);
        reject(new Error(`RPC request "${method}" (id=${id}) timed out after ${timeoutMs}ms`));
      }, timeoutMs);

      this.pending.set(id, {
        resolve: resolve as (v: unknown) => void,
        reject,
        timer,
      });

      this.send(msg);
    });
  }

  /**
   * Send a JSON-RPC notification (fire-and-forget, no response expected).
   */
  notify(method: string, params?: Record<string, unknown>): void {
    if (this.disposed) {
      return;
    }

    const msg: RpcNotification = { jsonrpc: '2.0', method };
    if (params !== undefined) {
      msg.params = params;
    }
    this.send(msg);
  }

  /**
   * Register a listener for incoming notifications with the given method.
   * Multiple listeners per method are supported.
   */
  on(event: 'error', callback: (err: Error) => void): this;
  on(event: 'close', callback: () => void): this;
  on(method: string, callback: NotificationListener): this;
  on(event: string, callback: (...args: any[]) => void): this {
    // 'error' and 'close' are EventEmitter events — delegate to super.
    if (event === 'error' || event === 'close') {
      return super.on(event, callback);
    }

    let set = this.notificationListeners.get(event);
    if (!set) {
      set = new Set();
      this.notificationListeners.set(event, set);
    }
    set.add(callback as NotificationListener);
    return this;
  }

  /**
   * Unregister a previously registered notification listener.
   */
  off(event: 'error', callback: (err: Error) => void): this;
  off(event: 'close', callback: () => void): this;
  off(method: string, callback: NotificationListener): this;
  off(event: string, callback: (...args: any[]) => void): this {
    if (event === 'error' || event === 'close') {
      return super.off(event, callback);
    }

    const set = this.notificationListeners.get(event);
    if (set) {
      set.delete(callback as NotificationListener);
      if (set.size === 0) {
        this.notificationListeners.delete(event);
      }
    }
    return this;
  }

  /**
   * Tear down the bridge: reject all pending requests, remove all listeners,
   * and stop reading from stdout.
   */
  dispose(): void {
    if (this.disposed) {
      return;
    }
    this.disposed = true;

    // Reject every pending request.
    for (const [id, entry] of this.pending) {
      clearTimeout(entry.timer);
      entry.reject(new Error('Bridge disposed'));
      this.pending.delete(id);
    }

    // Clear notification listeners.
    this.notificationListeners.clear();

    // Remove our data/end listeners from stdout.
    this.stdout.removeAllListeners('data');
    this.stdout.removeAllListeners('end');
    this.stdout.removeAllListeners('error');

    this.removeAllListeners();
  }

  // -------------------------------------------------------------------------
  // Internal helpers
  // -------------------------------------------------------------------------

  /** Write a JSON-RPC message as a single newline-terminated line to stdin. */
  private send(msg: RpcRequest | RpcNotification): void {
    const line = JSON.stringify(msg) + '\n';
    this.stdin.write(line);
  }

  /** Handle raw data from stdout, buffering partial lines. */
  private onData(chunk: Buffer | string): void {
    this.buffer += typeof chunk === 'string' ? chunk : chunk.toString('utf-8');

    let newlineIdx: number;
    while ((newlineIdx = this.buffer.indexOf('\n')) !== -1) {
      const line = this.buffer.slice(0, newlineIdx).trim();
      this.buffer = this.buffer.slice(newlineIdx + 1);

      if (line.length === 0) {
        continue;
      }
      this.handleLine(line);
    }
  }

  /** Parse and route a single complete JSON line. */
  private handleLine(line: string): void {
    let msg: Record<string, unknown>;
    try {
      msg = JSON.parse(line) as Record<string, unknown>;
    } catch {
      this.emit('error', new Error(`Malformed JSON from server: ${line.slice(0, 200)}`));
      return;
    }

    // Sanity-check: must be JSON-RPC 2.0
    if (msg.jsonrpc !== '2.0') {
      this.emit('error', new Error(`Invalid jsonrpc version: ${String(msg.jsonrpc)}`));
      return;
    }

    // Response (has numeric id)
    if (typeof msg.id === 'number') {
      this.handleResponse(msg as unknown as RpcResponse);
      return;
    }

    // Notification (has method, no id)
    if (typeof msg.method === 'string') {
      this.handleNotification(msg as unknown as RpcNotification);
      return;
    }

    this.emit('error', new Error(`Unrecognised JSON-RPC message: ${line.slice(0, 200)}`));
  }

  /** Resolve or reject a pending request based on the server's response. */
  private handleResponse(res: RpcResponse): void {
    const entry = this.pending.get(res.id);
    if (!entry) {
      // Response for an unknown / already-timed-out request — ignore.
      return;
    }

    clearTimeout(entry.timer);
    this.pending.delete(res.id);

    if (res.error) {
      const rpcErr = res.error as RpcError;
      entry.reject(new Error(`RPC error ${rpcErr.code}: ${rpcErr.message}`));
    } else {
      entry.resolve(res.result);
    }
  }

  /** Dispatch an incoming notification to all registered listeners. */
  private handleNotification(notif: RpcNotification): void {
    const set = this.notificationListeners.get(notif.method);
    if (!set || set.size === 0) {
      return;
    }
    for (const listener of set) {
      try {
        listener(notif.params);
      } catch (err) {
        this.emit('error', err instanceof Error ? err : new Error(String(err)));
      }
    }
  }

  /** Handle stdout stream ending. */
  private onClose(): void {
    this.emit('close');
    // Reject anything still pending.
    for (const [id, entry] of this.pending) {
      clearTimeout(entry.timer);
      entry.reject(new Error('Server process exited'));
      this.pending.delete(id);
    }
  }
}
