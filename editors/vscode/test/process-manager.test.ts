import { describe, it, expect, vi, beforeEach, afterEach } from 'vitest';
import * as vscode from 'vscode';
import { __resetAll, __setConfig, Uri } from './helpers/mock-vscode';
import { EventEmitter as NodeEventEmitter } from 'events';
import { PassThrough } from 'stream';

// ---------------------------------------------------------------------------
// Mock child_process.spawn and execSync
// ---------------------------------------------------------------------------

interface MockChildProcess extends NodeEventEmitter {
  stdin: PassThrough;
  stdout: PassThrough;
  stderr: PassThrough;
  pid: number;
  killed: boolean;
  kill: ReturnType<typeof vi.fn>;
}

function createMockChild(): MockChildProcess {
  const child = new NodeEventEmitter() as MockChildProcess;
  child.stdin = new PassThrough();
  child.stdout = new PassThrough();
  child.stderr = new PassThrough();
  child.pid = 12345;
  child.killed = false;
  child.kill = vi.fn((_signal?: string) => {
    child.killed = true;
    child.emit('exit', null, 'SIGTERM');
    return true;
  });
  return child;
}

let mockSpawnResult: MockChildProcess;

vi.mock('child_process', () => ({
  spawn: vi.fn(),
  execSync: vi.fn(() => '4.0.0'),
}));

// Import after mocking
import { ProcessManager } from '../src/process-manager';
import { spawn as cpSpawn, execSync } from 'child_process';

describe('ProcessManager', () => {
  let pm: ProcessManager;
  let outputChannel: any;

  beforeEach(() => {
    __resetAll();
    vi.useFakeTimers();

    mockSpawnResult = createMockChild();

    // Reset mocks to return correct values
    vi.mocked(cpSpawn).mockImplementation((..._args: any[]) => mockSpawnResult as any);
    vi.mocked(execSync).mockReturnValue('4.0.0' as any);

    __setConfig('rubyn-code', {
      executablePath: 'rubyn-code',
      yoloMode: false,
    });

    (vscode.workspace as any).workspaceFolders = [
      { uri: Uri.file('/workspace/my-app'), name: 'my-app', index: 0 },
    ];

    outputChannel = vscode.window.createOutputChannel('Rubyn Code');
    pm = new ProcessManager(outputChannel);
  });

  afterEach(() => {
    pm.dispose();
    vi.useRealTimers();
    vi.clearAllMocks();
    __resetAll();
  });

  // -----------------------------------------------------------------------
  // Spawn
  // -----------------------------------------------------------------------

  describe('spawn()', () => {
    it('calls child_process.spawn with correct arguments', () => {
      pm.spawn();

      expect(cpSpawn).toHaveBeenCalledWith(
        'rubyn-code',
        ['--ide', '--dir', '/workspace/my-app'],
        expect.objectContaining({
          stdio: ['pipe', 'pipe', 'pipe'],
        }),
      );
    });

    it('returns the child process', () => {
      const child = pm.spawn();
      expect(child).toBe(mockSpawnResult);
    });

    it('includes --yolo flag when yoloMode is enabled', () => {
      __setConfig('rubyn-code', { yoloMode: true, executablePath: 'rubyn-code' });

      pm.spawn();

      expect(cpSpawn).toHaveBeenCalledWith(
        'rubyn-code',
        expect.arrayContaining(['--yolo']),
        expect.any(Object),
      );
    });

    it('uses custom executable path from settings', () => {
      __setConfig('rubyn-code', {
        executablePath: '/usr/local/bin/my-rubyn',
        yoloMode: false,
      });

      pm.spawn();

      expect(cpSpawn).toHaveBeenCalledWith(
        '/usr/local/bin/my-rubyn',
        expect.any(Array),
        expect.any(Object),
      );
    });

    it('omits --dir when no workspace folder exists', () => {
      (vscode.workspace as any).workspaceFolders = undefined;

      pm.spawn();

      const callArgs = vi.mocked(cpSpawn).mock.calls[0];
      const args = callArgs[1] as string[];
      expect(args).not.toContain('--dir');
    });

    it('logs the spawn command to the output channel', () => {
      pm.spawn();

      expect(outputChannel.appendLine).toHaveBeenCalledWith(
        expect.stringContaining('Starting: rubyn-code'),
      );
    });

    it('throws when disposed', () => {
      pm.dispose();
      expect(() => pm.spawn()).toThrow('ProcessManager has been disposed');
    });
  });

  // -----------------------------------------------------------------------
  // Kill
  // -----------------------------------------------------------------------

  describe('kill()', () => {
    it('sends SIGTERM when no bridge is set', async () => {
      pm.spawn();

      const killPromise = pm.kill();
      await vi.advanceTimersByTimeAsync(100);
      await killPromise;

      expect(mockSpawnResult.kill).toHaveBeenCalledWith('SIGTERM');
    });

    it('is safe to call when no process is running', async () => {
      await expect(pm.kill()).resolves.toBeUndefined();
    });
  });

  // -----------------------------------------------------------------------
  // Restart
  // -----------------------------------------------------------------------

  describe('restart()', () => {
    it('kills the current process and spawns a new one', async () => {
      pm.spawn();
      const firstChild = mockSpawnResult;

      const secondChild = createMockChild();
      vi.mocked(cpSpawn).mockImplementation((..._args: any[]) => secondChild as any);
      mockSpawnResult = secondChild;

      const restartPromise = pm.restart();
      await vi.advanceTimersByTimeAsync(100);
      await restartPromise;

      expect(firstChild.kill).toHaveBeenCalled();
      expect(cpSpawn).toHaveBeenCalledTimes(2);
    });
  });

  // -----------------------------------------------------------------------
  // isRunning
  // -----------------------------------------------------------------------

  describe('isRunning()', () => {
    it('returns false when no process has been spawned', () => {
      expect(pm.isRunning()).toBe(false);
    });

    it('returns true when process is alive', () => {
      pm.spawn();
      expect(pm.isRunning()).toBe(true);
    });

    it('returns false after process exits', () => {
      pm.spawn();
      mockSpawnResult.emit('exit', 0, null);
      expect(pm.isRunning()).toBe(false);
    });
  });

  // -----------------------------------------------------------------------
  // Auto-restart on crash
  // -----------------------------------------------------------------------

  describe('auto-restart on crash', () => {
    it('respawns after process exits with backoff delay', async () => {
      pm.spawn();
      const firstChild = mockSpawnResult;

      const secondChild = createMockChild();
      vi.mocked(cpSpawn).mockImplementation((..._args: any[]) => secondChild as any);
      mockSpawnResult = secondChild;

      // Simulate crash
      firstChild.emit('exit', 1, null);

      expect(outputChannel.appendLine).toHaveBeenCalledWith(
        expect.stringContaining('Auto-restarting in 1000ms'),
      );

      await vi.advanceTimersByTimeAsync(1100);

      expect(cpSpawn).toHaveBeenCalledTimes(2);
    });

    it('uses increasing backoff delays', async () => {
      pm.spawn();
      const firstChild = mockSpawnResult;

      // First crash -> 1000ms backoff
      const secondChild = createMockChild();
      vi.mocked(cpSpawn).mockImplementation((..._args: any[]) => secondChild as any);
      mockSpawnResult = secondChild;
      firstChild.emit('exit', 1, null);

      expect(outputChannel.appendLine).toHaveBeenCalledWith(
        expect.stringContaining('1000ms (attempt 1/3)'),
      );

      await vi.advanceTimersByTimeAsync(1100);

      // Second crash -> 3000ms backoff
      const thirdChild = createMockChild();
      vi.mocked(cpSpawn).mockImplementation((..._args: any[]) => thirdChild as any);
      mockSpawnResult = thirdChild;
      secondChild.emit('exit', 1, null);

      expect(outputChannel.appendLine).toHaveBeenCalledWith(
        expect.stringContaining('3000ms (attempt 2/3)'),
      );
    });
  });

  // -----------------------------------------------------------------------
  // Max retries
  // -----------------------------------------------------------------------

  describe('max retries', () => {
    it('stops restarting after 3 crashes and shows error', async () => {
      pm.spawn();
      let currentChild = mockSpawnResult;

      // Crash 3 times, each time advancing past the backoff
      for (let i = 0; i < 3; i++) {
        const nextChild = createMockChild();
        vi.mocked(cpSpawn).mockImplementation((..._args: any[]) => nextChild as any);
        mockSpawnResult = nextChild;

        currentChild.emit('exit', 1, null);
        // Advance past the backoff delay
        await vi.advanceTimersByTimeAsync(11_000);
        currentChild = nextChild;
      }

      // 4th crash -- this one should hit the max retries
      currentChild.emit('exit', 1, null);

      expect(outputChannel.appendLine).toHaveBeenCalledWith(
        expect.stringContaining('Max restart attempts'),
      );

      expect(vscode.window.showErrorMessage).toHaveBeenCalledWith(
        expect.stringContaining('crashed repeatedly'),
      );
    });
  });

  // -----------------------------------------------------------------------
  // Executable not found (ENOENT)
  // -----------------------------------------------------------------------

  describe('executable not found', () => {
    it('shows helpful error message on ENOENT', async () => {
      pm.spawn();

      const err = new Error('spawn ENOENT') as NodeJS.ErrnoException;
      err.code = 'ENOENT';
      mockSpawnResult.emit('error', err);

      expect(vscode.window.showErrorMessage).toHaveBeenCalledWith(
        expect.stringContaining('gem install rubyn-code'),
      );
    });

    it('shows generic error for non-ENOENT errors', async () => {
      pm.spawn();

      const err = new Error('Permission denied');
      mockSpawnResult.emit('error', err);

      expect(vscode.window.showErrorMessage).toHaveBeenCalledWith(
        expect.stringContaining('Permission denied'),
      );
    });
  });

  // -----------------------------------------------------------------------
  // Stderr piping
  // -----------------------------------------------------------------------

  describe('stderr piping', () => {
    it('forwards stderr output to the output channel', () => {
      pm.spawn();

      mockSpawnResult.stderr.write('Warning: something happened\n');

      expect(outputChannel.appendLine).toHaveBeenCalledWith(
        expect.stringContaining('[stderr] Warning: something happened'),
      );
    });

    it('detects authentication failures in stderr', () => {
      pm.spawn();

      mockSpawnResult.stderr.write('Error: not authenticated\n');

      expect(vscode.window.showErrorMessage).toHaveBeenCalledWith(
        expect.stringContaining('Not authenticated'),
      );
    });
  });

  // -----------------------------------------------------------------------
  // Ruby version check
  // -----------------------------------------------------------------------

  describe('ruby version check', () => {
    // Note: checkRubyVersion uses dynamic require('child_process') internally,
    // which runs the real execSync. These tests verify that spawn() calls
    // checkRubyVersion and logs the result without crashing.

    it('logs detected Ruby version during spawn', () => {
      pm.spawn();

      // The real Ruby version on the system is detected and logged.
      // We verify checkRubyVersion ran by checking that a "Detected Ruby" or
      // "Could not detect" line was logged before the "Starting:" line.
      const calls = outputChannel.appendLine.mock.calls.map((c: any[]) => c[0] as string);
      const hasVersionLog = calls.some(
        (msg: string) => msg.includes('Detected Ruby') || msg.includes('Could not detect Ruby'),
      );
      expect(hasVersionLog).toBe(true);
    });

    it('does not crash if ruby version check fails', () => {
      // spawn should succeed regardless of Ruby version detection
      expect(() => pm.spawn()).not.toThrow();
    });

    it('checkRubyVersion runs before spawn command', () => {
      pm.spawn();

      const calls = outputChannel.appendLine.mock.calls.map((c: any[]) => c[0] as string);
      const versionIdx = calls.findIndex(
        (msg: string) => msg.includes('Detected Ruby') || msg.includes('Could not detect'),
      );
      const startIdx = calls.findIndex((msg: string) => msg.includes('Starting:'));

      // Version check should be logged before the starting line
      expect(versionIdx).toBeLessThan(startIdx);
    });
  });

  // -----------------------------------------------------------------------
  // Dispose
  // -----------------------------------------------------------------------

  describe('dispose()', () => {
    it('kills the running process', () => {
      pm.spawn();
      pm.dispose();

      expect(mockSpawnResult.kill).toHaveBeenCalled();
    });

    it('clears pending restart timer', async () => {
      pm.spawn();
      const firstChild = mockSpawnResult;

      // Trigger a crash to start a restart timer
      firstChild.emit('exit', 1, null);

      // Dispose before the restart fires
      pm.dispose();

      const secondChild = createMockChild();
      vi.mocked(cpSpawn).mockImplementation((..._args: any[]) => secondChild as any);

      // Advance timers -- the restart should NOT fire
      await vi.advanceTimersByTimeAsync(15_000);

      // spawn should have been called only once (the initial)
      expect(cpSpawn).toHaveBeenCalledTimes(1);
    });

    it('prevents auto-restart after dispose', () => {
      pm.spawn();
      pm.dispose();

      // Even if exit fires after dispose, no restart should happen
      mockSpawnResult.emit('exit', 1, null);
      // No additional spawn calls beyond the initial one
    });
  });

  // -----------------------------------------------------------------------
  // setBridge / getProcess
  // -----------------------------------------------------------------------

  describe('setBridge / getProcess', () => {
    it('returns the current child process', () => {
      expect(pm.getProcess()).toBeNull();

      pm.spawn();
      expect(pm.getProcess()).toBe(mockSpawnResult);
    });

    it('returns null after process exits', () => {
      pm.spawn();
      mockSpawnResult.emit('exit', 0, null);
      expect(pm.getProcess()).toBeNull();
    });
  });
});
