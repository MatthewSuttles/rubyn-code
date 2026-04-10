/**
 * Rubyn Code process manager.
 *
 * Spawns and manages the `rubyn-code --ide` child process, handling lifecycle,
 * crash recovery, and clean shutdown.
 */

import * as vscode from 'vscode';
import { ChildProcess, spawn as cpSpawn } from 'child_process';
import { Bridge } from './bridge';

/** Backoff delays (ms) for auto-restart after crash. */
const RESTART_BACKOFFS = [1_000, 3_000, 10_000];

/** Maximum number of auto-restart attempts. */
const MAX_RETRIES = 3;

/** Timeout (ms) to wait for graceful shutdown before sending SIGTERM. */
const SHUTDOWN_GRACE_MS = 5_000;

export class ProcessManager implements vscode.Disposable {
  private readonly outputChannel: vscode.OutputChannel;
  private process: ChildProcess | null = null;
  private bridge: Bridge | null = null;
  private restartCount = 0;
  private disposed = false;
  private restartTimer: ReturnType<typeof setTimeout> | null = null;

  constructor(outputChannel: vscode.OutputChannel) {
    this.outputChannel = outputChannel;
  }

  // ---------------------------------------------------------------------------
  // Public API
  // ---------------------------------------------------------------------------

  /**
   * Spawn the `rubyn-code --ide` child process.
   * Returns the ChildProcess so the caller can wire up the Bridge.
   */
  spawn(): ChildProcess {
    if (this.disposed) {
      throw new Error('ProcessManager has been disposed');
    }

    const config = vscode.workspace.getConfiguration('rubyn-code');
    const executablePath = config.get<string>('executablePath', 'rubyn-code');
    const yoloMode = config.get<boolean>('yoloMode', false);

    const args = ['--ide'];

    if (yoloMode) {
      args.push('--yolo');
    }

    const workspaceRoot = vscode.workspace.workspaceFolders?.[0]?.uri.fsPath;
    if (workspaceRoot) {
      args.push('--dir', workspaceRoot);
    }

    this.checkRubyVersion();

    this.outputChannel.appendLine(
      `Starting: ${executablePath} ${args.join(' ')}`,
    );

    let child: ChildProcess;
    try {
      child = cpSpawn(executablePath, args, {
        stdio: ['pipe', 'pipe', 'pipe'],
        env: { ...process.env },
      });
    } catch (err) {
      const message =
        'Rubyn Code not found. Install with: `gem install rubyn-code`';
      this.outputChannel.appendLine(`ERROR: ${message}`);
      vscode.window.showErrorMessage(message);
      throw new Error(message);
    }

    // Pipe stderr to the output channel.
    child.stderr?.on('data', (chunk: Buffer | string) => {
      const text = typeof chunk === 'string' ? chunk : chunk.toString('utf-8');
      for (const line of text.split('\n')) {
        if (line.length > 0) {
          this.outputChannel.appendLine(`[stderr] ${line}`);

          // Detect auth failures.
          if (
            line.includes('not authenticated') ||
            line.includes('authentication failed') ||
            line.includes('NotAuthenticated')
          ) {
            vscode.window.showErrorMessage(
              'Not authenticated. Run `rubyn-code` in terminal first.',
            );
          }
        }
      }
    });

    // Handle spawn errors (e.g. executable not found).
    child.on('error', (err: Error) => {
      const isNotFound =
        (err as NodeJS.ErrnoException).code === 'ENOENT';
      const message = isNotFound
        ? 'Rubyn Code not found. Install with: `gem install rubyn-code`'
        : `Failed to start Rubyn Code: ${err.message}`;
      this.outputChannel.appendLine(`ERROR: ${message}`);
      vscode.window.showErrorMessage(message);
    });

    // Handle unexpected exit — auto-restart with backoff.
    child.on('exit', (code, signal) => {
      this.outputChannel.appendLine(
        `Process exited (code=${code}, signal=${signal})`,
      );
      this.process = null;

      if (this.disposed) {
        return;
      }

      if (this.restartCount < MAX_RETRIES) {
        const delay = RESTART_BACKOFFS[this.restartCount] ?? 10_000;
        this.restartCount++;
        this.outputChannel.appendLine(
          `Auto-restarting in ${delay}ms (attempt ${this.restartCount}/${MAX_RETRIES})...`,
        );
        this.restartTimer = setTimeout(() => {
          this.restartTimer = null;
          if (!this.disposed) {
            try {
              this.spawn();
            } catch {
              // Error already surfaced to user in spawn().
            }
          }
        }, delay);
      } else {
        this.outputChannel.appendLine(
          `Max restart attempts (${MAX_RETRIES}) reached. Not restarting.`,
        );
        vscode.window.showErrorMessage(
          'Rubyn Code process crashed repeatedly. Check the "Rubyn Code" output channel for details.',
        );
      }
    });

    this.process = child;
    return child;
  }

  /**
   * Gracefully shut down the process.
   *
   * Sends a `shutdown` JSON-RPC request via the bridge, waits up to 5s for
   * a clean exit, then sends SIGTERM.
   */
  async kill(): Promise<void> {
    if (this.restartTimer !== null) {
      clearTimeout(this.restartTimer);
      this.restartTimer = null;
    }

    if (!this.process) {
      return;
    }

    // Prevent auto-restart during intentional kill.
    const proc = this.process;
    this.process = null;

    // Try graceful shutdown via bridge.
    if (this.bridge) {
      try {
        await Promise.race([
          this.bridge.request('shutdown', undefined, SHUTDOWN_GRACE_MS),
          new Promise<void>((resolve) => {
            proc.once('exit', () => resolve());
          }),
        ]);
      } catch {
        // Timeout or error — fall through to SIGTERM.
      }
    }

    // If still running, force kill.
    if (!proc.killed) {
      proc.kill('SIGTERM');
    }
  }

  /**
   * Kill the current process and spawn a new one.
   */
  async restart(): Promise<void> {
    this.restartCount = 0; // Reset counter for intentional restart.
    await this.kill();
    this.spawn();
  }

  /**
   * Check whether the child process is currently alive.
   */
  isRunning(): boolean {
    return this.process !== null && !this.process.killed;
  }

  /**
   * Store a reference to the bridge so `kill()` can send a graceful shutdown.
   */
  setBridge(bridge: Bridge): void {
    this.bridge = bridge;
  }

  /**
   * Return the current child process, or null if not running.
   */
  getProcess(): ChildProcess | null {
    return this.process;
  }

  /**
   * Clean up all resources.
   */
  dispose(): void {
    this.disposed = true;
    if (this.restartTimer !== null) {
      clearTimeout(this.restartTimer);
      this.restartTimer = null;
    }
    // Fire-and-forget kill.
    this.kill().catch(() => {});
  }

  // ---------------------------------------------------------------------------
  // Internals
  // ---------------------------------------------------------------------------

  /**
   * Check the system Ruby version and warn if below 4.0.
   */
  private checkRubyVersion(): void {
    try {
      const { execSync } = require('child_process') as typeof import('child_process');
      const output = execSync('ruby -e "puts RUBY_VERSION"', {
        encoding: 'utf-8',
        timeout: 5_000,
      }).trim();

      this.outputChannel.appendLine(`Detected Ruby ${output}`);

      const major = parseInt(output.split('.')[0], 10);
      if (!isNaN(major) && major < 4) {
        vscode.window.showWarningMessage(
          `Ruby ${output} detected. Rubyn Code requires Ruby 4.0 or later.`,
        );
      }
    } catch {
      this.outputChannel.appendLine(
        'Could not detect Ruby version. Ensure Ruby is installed and on your PATH.',
      );
    }
  }
}
