import { describe, it, expect, vi, beforeEach, afterEach } from 'vitest';
import { PassThrough } from 'stream';
import * as vscode from 'vscode';
import {
  __resetAll,
  __setConfig,
  Uri,
  Range,
  Position,
  WorkspaceEdit,
} from './helpers/mock-vscode';
import { Bridge } from '../src/bridge';
import { DiffProvider } from '../src/diff-provider';

function createTestEnv() {
  const stdin = new PassThrough();
  const stdout = new PassThrough();
  const bridge = new Bridge(stdin, stdout);

  const diffProvider = new DiffProvider(bridge);

  /** Simulate the server sending a notification via stdout. */
  function serverNotify(method: string, params: Record<string, unknown>): void {
    stdout.write(
      JSON.stringify({ jsonrpc: '2.0', method, params }) + '\n',
    );
  }

  /** Read what bridge wrote to stdin (notifications back to server). */
  function readBridgeOutput(): Array<Record<string, unknown>> {
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

  return { bridge, stdin, stdout, diffProvider, serverNotify, readBridgeOutput };
}

describe('DiffProvider', () => {
  let env: ReturnType<typeof createTestEnv>;

  beforeEach(() => {
    __resetAll();
    env = createTestEnv();

    // Default: not yolo mode
    __setConfig('rubyn-code', { yoloMode: false });

    // Default tabGroups for closeDiffEditor
    (vscode.window.tabGroups as any).all = [];
  });

  afterEach(() => {
    env.diffProvider.dispose();
    env.bridge.dispose();
    __resetAll();
  });

  // -----------------------------------------------------------------------
  // Modify edit flow
  // -----------------------------------------------------------------------

  describe('modify edit flow', () => {
    it('opens diff editor and shows accept/reject buttons on file/edit modify', async () => {
      // Mock opening the original document for buildProposedContent
      (vscode.workspace.openTextDocument as any).mockResolvedValue({
        getText: () => 'line1\nline2\nline3\n',
        positionAt: (offset: number) => new Position(0, offset),
        uri: Uri.file('/workspace/app/models/user.rb'),
        save: vi.fn(async () => true),
      });

      // User clicks "Accept"
      (vscode.window.showInformationMessage as any).mockResolvedValue('Accept');

      env.serverNotify('file/edit', {
        editId: 'edit-1',
        path: '/workspace/app/models/user.rb',
        type: 'modify',
        content: 'line1\nmodified_line2\nline3\n',
      });

      await new Promise((r) => setTimeout(r, 50));

      // Should have called vscode.diff
      expect(vscode.commands.executeCommand).toHaveBeenCalledWith(
        'vscode.diff',
        expect.any(Object),
        expect.any(Object),
        expect.stringContaining('user.rb'),
      );

      // Should have asked user
      expect(vscode.window.showInformationMessage).toHaveBeenCalledWith(
        expect.stringContaining('user.rb'),
        { modal: false },
        'Accept',
        'Reject',
      );
    });
  });

  // -----------------------------------------------------------------------
  // Create edit flow
  // -----------------------------------------------------------------------

  describe('create edit flow', () => {
    it('shows preview and accept/reject buttons on file/create', async () => {
      (vscode.workspace.openTextDocument as any).mockResolvedValue({
        getText: () => 'new file content',
        uri: Uri.parse('rubyn-proposed://rubyn/new'),
      });

      (vscode.window.showInformationMessage as any).mockResolvedValue('Accept');

      env.serverNotify('file/create', {
        editId: 'create-1',
        path: '/workspace/app/models/post.rb',
        content: 'class Post\nend',
      });

      await new Promise((r) => setTimeout(r, 50));

      // Should have shown the preview
      expect(vscode.window.showTextDocument).toHaveBeenCalled();

      // Should have asked user
      expect(vscode.window.showInformationMessage).toHaveBeenCalledWith(
        expect.stringContaining('post.rb'),
        { modal: false },
        'Accept',
        'Reject',
      );
    });

    it('writes file when user accepts create', async () => {
      (vscode.workspace.openTextDocument as any).mockResolvedValue({
        getText: () => '',
        uri: Uri.parse('rubyn-proposed://rubyn/new'),
      });

      (vscode.window.showInformationMessage as any).mockResolvedValue('Accept');

      env.serverNotify('file/create', {
        editId: 'create-2',
        path: '/workspace/app/models/comment.rb',
        content: 'class Comment\nend',
      });

      await new Promise((r) => setTimeout(r, 50));

      // File should have been written
      expect(vscode.workspace.fs.writeFile).toHaveBeenCalledWith(
        expect.objectContaining({ fsPath: '/workspace/app/models/comment.rb' }),
        expect.any(Uint8Array),
      );

      // Bridge should have been notified of acceptance
      const sent = env.readBridgeOutput();
      const acceptMsg = sent.find(
        (m) => m.method === 'acceptEdit' && (m.params as any)?.editId === 'create-2',
      );
      expect(acceptMsg).toBeDefined();
      expect((acceptMsg!.params as any).accepted).toBe(true);
    });
  });

  // -----------------------------------------------------------------------
  // Accept modify
  // -----------------------------------------------------------------------

  describe('accept modify', () => {
    it('writes proposed content and sends acceptEdit to bridge', async () => {
      const mockDoc = {
        getText: () => 'original content',
        positionAt: (offset: number) => new Position(0, offset),
        uri: Uri.file('/workspace/app/models/user.rb'),
        save: vi.fn(async () => true),
      };

      (vscode.workspace.openTextDocument as any).mockResolvedValue(mockDoc);
      (vscode.window.showInformationMessage as any).mockResolvedValue('Accept');

      env.serverNotify('file/edit', {
        editId: 'mod-1',
        path: '/workspace/app/models/user.rb',
        type: 'modify',
        content: 'new content',
      });

      await new Promise((r) => setTimeout(r, 50));

      // WorkspaceEdit.applyEdit should have been called
      expect(vscode.workspace.applyEdit).toHaveBeenCalled();

      // Document should have been saved
      expect(mockDoc.save).toHaveBeenCalled();

      // Bridge notified
      const sent = env.readBridgeOutput();
      const acceptMsg = sent.find(
        (m) => m.method === 'acceptEdit' && (m.params as any)?.editId === 'mod-1',
      );
      expect(acceptMsg).toBeDefined();
      expect((acceptMsg!.params as any).accepted).toBe(true);

      // Pending should be cleared
      expect(env.diffProvider.hasPending('mod-1')).toBe(false);
    });
  });

  // -----------------------------------------------------------------------
  // Reject modify
  // -----------------------------------------------------------------------

  describe('reject modify', () => {
    it('sends acceptEdit with false and does not write file', async () => {
      (vscode.workspace.openTextDocument as any).mockResolvedValue({
        getText: () => 'original content',
        positionAt: (offset: number) => new Position(0, offset),
        uri: Uri.file('/workspace/app/models/user.rb'),
        save: vi.fn(async () => true),
      });

      (vscode.window.showInformationMessage as any).mockResolvedValue('Reject');

      env.serverNotify('file/edit', {
        editId: 'mod-2',
        path: '/workspace/app/models/user.rb',
        type: 'modify',
        content: 'new content',
      });

      await new Promise((r) => setTimeout(r, 50));

      // applyEdit should NOT have been called (reject = no write)
      expect(vscode.workspace.applyEdit).not.toHaveBeenCalled();

      // Bridge notified with accepted=false
      const sent = env.readBridgeOutput();
      const rejectMsg = sent.find(
        (m) => m.method === 'acceptEdit' && (m.params as any)?.editId === 'mod-2',
      );
      expect(rejectMsg).toBeDefined();
      expect((rejectMsg!.params as any).accepted).toBe(false);
    });
  });

  // -----------------------------------------------------------------------
  // Delete flow
  // -----------------------------------------------------------------------

  describe('delete flow', () => {
    it('shows warning dialog for delete type', async () => {
      (vscode.window.showWarningMessage as any).mockResolvedValue('Accept');

      env.serverNotify('file/edit', {
        editId: 'del-1',
        path: '/workspace/app/models/old.rb',
        type: 'delete',
      });

      await new Promise((r) => setTimeout(r, 50));

      expect(vscode.window.showWarningMessage).toHaveBeenCalledWith(
        expect.stringContaining('old.rb'),
        { modal: false },
        'Accept',
        'Reject',
      );

      // File should have been deleted
      expect(vscode.workspace.fs.delete).toHaveBeenCalledWith(
        expect.objectContaining({ fsPath: '/workspace/app/models/old.rb' }),
      );
    });

    it('sends acceptEdit false when delete is rejected', async () => {
      (vscode.window.showWarningMessage as any).mockResolvedValue('Reject');

      env.serverNotify('file/edit', {
        editId: 'del-2',
        path: '/workspace/app/models/old.rb',
        type: 'delete',
      });

      await new Promise((r) => setTimeout(r, 50));

      expect(vscode.workspace.fs.delete).not.toHaveBeenCalled();

      const sent = env.readBridgeOutput();
      const msg = sent.find(
        (m) => m.method === 'acceptEdit' && (m.params as any)?.editId === 'del-2',
      );
      expect(msg).toBeDefined();
      expect((msg!.params as any).accepted).toBe(false);
    });
  });

  // -----------------------------------------------------------------------
  // Pending tracking
  // -----------------------------------------------------------------------

  describe('pending tracking', () => {
    it('tracks multiple pending edits by editId', async () => {
      // Set up mocks so the edit handlers don't resolve (user hasn't responded)
      (vscode.workspace.openTextDocument as any).mockResolvedValue({
        getText: () => '',
        positionAt: () => new Position(0, 0),
        uri: Uri.file('/test'),
        save: vi.fn(),
      });

      // Never resolve the info message — edit stays pending
      (vscode.window.showInformationMessage as any).mockReturnValue(
        new Promise(() => {}),
      );

      env.serverNotify('file/edit', {
        editId: 'p1',
        path: '/workspace/a.rb',
        type: 'modify',
        content: 'a',
      });

      env.serverNotify('file/edit', {
        editId: 'p2',
        path: '/workspace/b.rb',
        type: 'modify',
        content: 'b',
      });

      await new Promise((r) => setTimeout(r, 50));

      expect(env.diffProvider.hasPending('p1')).toBe(true);
      expect(env.diffProvider.hasPending('p2')).toBe(true);
      expect(env.diffProvider.pendingCount).toBe(2);
    });
  });

  // -----------------------------------------------------------------------
  // Yolo mode
  // -----------------------------------------------------------------------

  describe('yolo mode', () => {
    it('auto-accepts modify without user interaction', async () => {
      __setConfig('rubyn-code', { yoloMode: true });

      const mockDoc = {
        getText: () => 'original',
        positionAt: (offset: number) => new Position(0, offset),
        uri: Uri.file('/workspace/app/models/user.rb'),
        save: vi.fn(async () => true),
      };

      (vscode.workspace.openTextDocument as any).mockResolvedValue(mockDoc);

      env.serverNotify('file/edit', {
        editId: 'yolo-1',
        path: '/workspace/app/models/user.rb',
        type: 'modify',
        content: 'auto-applied',
      });

      await new Promise((r) => setTimeout(r, 50));

      // Should NOT have shown the info message dialog
      // (it uses showInformationMessage for flash notification, but not modal accept/reject)
      // The diff editor should NOT have been opened
      expect(vscode.commands.executeCommand).not.toHaveBeenCalledWith(
        'vscode.diff',
        expect.anything(),
        expect.anything(),
        expect.anything(),
      );

      // Should have applied the edit
      expect(vscode.workspace.applyEdit).toHaveBeenCalled();

      // Bridge notified with accepted=true
      const sent = env.readBridgeOutput();
      const msg = sent.find(
        (m) => m.method === 'acceptEdit' && (m.params as any)?.editId === 'yolo-1',
      );
      expect(msg).toBeDefined();
      expect((msg!.params as any).accepted).toBe(true);
    });

    it('auto-accepts create without user interaction', async () => {
      __setConfig('rubyn-code', { yoloMode: true });

      env.serverNotify('file/create', {
        editId: 'yolo-create-1',
        path: '/workspace/new_file.rb',
        content: 'class NewFile\nend',
      });

      await new Promise((r) => setTimeout(r, 50));

      // File should have been written
      expect(vscode.workspace.fs.writeFile).toHaveBeenCalled();

      const sent = env.readBridgeOutput();
      const msg = sent.find(
        (m) => m.method === 'acceptEdit' && (m.params as any)?.editId === 'yolo-create-1',
      );
      expect(msg).toBeDefined();
      expect((msg!.params as any).accepted).toBe(true);
    });

    it('auto-accepts delete without user interaction', async () => {
      __setConfig('rubyn-code', { yoloMode: true });

      env.serverNotify('file/edit', {
        editId: 'yolo-del-1',
        path: '/workspace/old.rb',
        type: 'delete',
      });

      await new Promise((r) => setTimeout(r, 50));

      expect(vscode.workspace.fs.delete).toHaveBeenCalled();
      expect(vscode.window.showWarningMessage).not.toHaveBeenCalledWith(
        expect.anything(),
        { modal: false },
        'Accept',
        'Reject',
      );
    });
  });

  // -----------------------------------------------------------------------
  // Dispose
  // -----------------------------------------------------------------------

  describe('dispose', () => {
    it('rejects all pending edits and clears them', async () => {
      (vscode.workspace.openTextDocument as any).mockResolvedValue({
        getText: () => '',
        positionAt: () => new Position(0, 0),
        uri: Uri.file('/test'),
        save: vi.fn(),
      });

      (vscode.window.showInformationMessage as any).mockReturnValue(
        new Promise(() => {}),
      );

      env.serverNotify('file/edit', {
        editId: 'disp-1',
        path: '/workspace/a.rb',
        type: 'modify',
        content: 'x',
      });

      await new Promise((r) => setTimeout(r, 50));
      expect(env.diffProvider.hasPending('disp-1')).toBe(true);

      env.diffProvider.dispose();

      // After dispose, pending should be cleared
      expect(env.diffProvider.pendingCount).toBe(0);

      // Bridge should have been notified with accepted=false for each pending
      const sent = env.readBridgeOutput();
      const rejectMsg = sent.find(
        (m) => m.method === 'acceptEdit' && (m.params as any)?.editId === 'disp-1',
      );
      expect(rejectMsg).toBeDefined();
      expect((rejectMsg!.params as any).accepted).toBe(false);
    });
  });

  // -----------------------------------------------------------------------
  // file/edit with null params is ignored
  // -----------------------------------------------------------------------

  describe('edge cases', () => {
    it('ignores file/edit notification with no params', async () => {
      env.serverNotify('file/edit', undefined as any);
      await new Promise((r) => setTimeout(r, 50));
      expect(env.diffProvider.pendingCount).toBe(0);
    });

    it('ignores file/create notification with no params', async () => {
      env.serverNotify('file/create', undefined as any);
      await new Promise((r) => setTimeout(r, 50));
      expect(env.diffProvider.pendingCount).toBe(0);
    });
  });
});
