/**
 * Rubyn Code inline diff provider.
 *
 * Intercepts `file/edit` and `file/create` notifications from the Bridge,
 * shows VS Code's native diff editor for modifications, preview tabs for
 * new files, and confirmation dialogs for deletions.  The user can accept
 * or reject each proposed change; in yolo mode every edit is auto-accepted.
 */

import * as vscode from 'vscode';
import { Bridge } from './bridge';
import { AcceptEditParams, FileEditParams, FileCreateParams, Hunk } from './types';

// ---------------------------------------------------------------------------
// URI scheme for virtual "proposed" documents
// ---------------------------------------------------------------------------

const PROPOSED_SCHEME = 'rubyn-proposed';

// ---------------------------------------------------------------------------
// Pending-edit bookkeeping
// ---------------------------------------------------------------------------

interface PendingModify {
  kind: 'modify';
  editId: string;
  filePath: string;
  hunks: Hunk[];
  proposedContent: string;
  originalUri: vscode.Uri;
  proposedUri: vscode.Uri;
  sessionId?: string;
}

interface PendingCreate {
  kind: 'create';
  editId: string;
  filePath: string;
  content: string;
  sessionId?: string;
}

interface PendingDelete {
  kind: 'delete';
  editId: string;
  filePath: string;
  sessionId?: string;
}

type PendingEdit = PendingModify | PendingCreate | PendingDelete;

// ---------------------------------------------------------------------------
// ProposedContentProvider — serves virtual documents for the diff view
// ---------------------------------------------------------------------------

class ProposedContentProvider implements vscode.TextDocumentContentProvider {
  private contents = new Map<string, string>();
  private onDidChangeEmitter = new vscode.EventEmitter<vscode.Uri>();

  readonly onDidChange = this.onDidChangeEmitter.event;

  set(uri: vscode.Uri, content: string): void {
    this.contents.set(uri.toString(), content);
    this.onDidChangeEmitter.fire(uri);
  }

  remove(uri: vscode.Uri): void {
    this.contents.delete(uri.toString());
  }

  provideTextDocumentContent(uri: vscode.Uri): string {
    return this.contents.get(uri.toString()) ?? '';
  }

  clear(): void {
    this.contents.clear();
  }

  dispose(): void {
    this.onDidChangeEmitter.dispose();
    this.contents.clear();
  }
}

// ---------------------------------------------------------------------------
// DiffProvider
// ---------------------------------------------------------------------------

export class DiffProvider implements vscode.Disposable {
  private readonly bridge: Bridge;
  private readonly contentProvider: ProposedContentProvider;
  private readonly pending = new Map<string, PendingEdit>();
  private readonly disposables: vscode.Disposable[] = [];

  /** Counter used to generate unique proposed-document URIs. */
  private seq = 0;

  constructor(bridge: Bridge) {
    this.bridge = bridge;
    this.contentProvider = new ProposedContentProvider();

    // Register the virtual-document scheme.
    this.disposables.push(
      vscode.workspace.registerTextDocumentContentProvider(
        PROPOSED_SCHEME,
        this.contentProvider,
      ),
    );

    // Subscribe to bridge notifications.
    this.bridge.on('file/edit', (params) => this.onFileEdit(params));
    this.bridge.on('file/create', (params) => this.onFileCreate(params));
  }

  // -----------------------------------------------------------------------
  // Notification handlers
  // -----------------------------------------------------------------------

  private async onFileEdit(
    params: Record<string, unknown> | undefined,
  ): Promise<void> {
    if (!params) {
      return;
    }

    const edit = params as unknown as FileEditParams;

    switch (edit.type) {
      case 'modify':
        await this.handleModify(edit);
        break;
      case 'create':
        await this.handleCreate(edit);
        break;
      case 'delete':
        await this.handleDelete(edit);
        break;
    }
  }

  private async onFileCreate(
    params: Record<string, unknown> | undefined,
  ): Promise<void> {
    if (!params) {
      return;
    }

    const create = params as unknown as FileCreateParams;
    await this.handleCreate({
      editId: create.editId,
      path: create.path,
      type: 'create',
      content: create.content,
    });
  }

  // -----------------------------------------------------------------------
  // Modify — inline diff
  // -----------------------------------------------------------------------

  private async handleModify(edit: FileEditParams): Promise<void> {
    const originalUri = vscode.Uri.file(edit.path);
    const proposedUri = vscode.Uri.parse(
      `${PROPOSED_SCHEME}://rubyn/proposed-${this.seq++}/${encodeURIComponent(
        edit.path,
      )}`,
    );

    // Build the full proposed content by applying hunks to the original.
    const proposedContent = await this.buildProposedContent(
      originalUri,
      edit.hunks ?? [],
      edit.content,
    );

    this.contentProvider.set(proposedUri, proposedContent);

    const pending: PendingModify = {
      kind: 'modify',
      editId: edit.editId,
      filePath: edit.path,
      hunks: edit.hunks ?? [],
      proposedContent,
      originalUri,
      proposedUri,
    };
    this.pending.set(edit.editId, pending);

    // Yolo mode: auto-accept immediately with a brief notification.
    if (this.isYoloMode()) {
      this.flashNotification(`Rubyn auto-applied changes to ${this.basename(edit.path)}`);
      await this.acceptModify(pending);
      return;
    }

    // Open the diff editor.
    const title = `Rubyn: ${this.basename(edit.path)} (proposed changes)`;
    await vscode.commands.executeCommand('vscode.diff', originalUri, proposedUri, title);

    // Show accept / reject buttons.
    const choice = await vscode.window.showInformationMessage(
      `Rubyn wants to modify ${this.basename(edit.path)}`,
      { modal: false },
      'Accept',
      'Reject',
    );

    if (choice === 'Accept') {
      await this.acceptModify(pending);
    } else {
      await this.rejectEdit(pending);
    }
  }

  private async acceptModify(pending: PendingModify): Promise<void> {
    // Apply the proposed content to the real file.
    const document = await vscode.workspace.openTextDocument(pending.originalUri);
    const fullRange = new vscode.Range(
      document.positionAt(0),
      document.positionAt(document.getText().length),
    );

    const workspaceEdit = new vscode.WorkspaceEdit();
    workspaceEdit.replace(pending.originalUri, fullRange, pending.proposedContent);
    await vscode.workspace.applyEdit(workspaceEdit);
    await document.save();

    // Notify the bridge.
    this.sendAcceptEdit(pending.editId, true);

    // Clean up.
    this.cleanupEdit(pending);
  }

  // -----------------------------------------------------------------------
  // Create — preview tab
  // -----------------------------------------------------------------------

  private async handleCreate(edit: FileEditParams): Promise<void> {
    const content = edit.content ?? '';
    const filePath = edit.path;

    const pending: PendingCreate = {
      kind: 'create',
      editId: edit.editId,
      filePath,
      content,
    };
    this.pending.set(edit.editId, pending);

    // Yolo mode: auto-accept.
    if (this.isYoloMode()) {
      this.flashNotification(`Rubyn auto-created ${this.basename(filePath)}`);
      await this.acceptCreate(pending);
      return;
    }

    // Show the proposed content in a virtual document so the user can preview.
    const previewUri = vscode.Uri.parse(
      `${PROPOSED_SCHEME}://rubyn/new-${this.seq++}/${encodeURIComponent(filePath)}`,
    );
    this.contentProvider.set(previewUri, content);

    const doc = await vscode.workspace.openTextDocument(previewUri);
    await vscode.window.showTextDocument(doc, { preview: true });

    const choice = await vscode.window.showInformationMessage(
      `Rubyn wants to create this file: ${this.basename(filePath)}`,
      { modal: false },
      'Accept',
      'Reject',
    );

    if (choice === 'Accept') {
      await this.acceptCreate(pending);
    } else {
      await this.rejectEdit(pending);
    }

    // Close the preview tab.
    this.contentProvider.remove(previewUri);
  }

  private async acceptCreate(pending: PendingCreate): Promise<void> {
    const fileUri = vscode.Uri.file(pending.filePath);
    const encoded = new TextEncoder().encode(pending.content);

    await vscode.workspace.fs.writeFile(fileUri, encoded);

    this.sendAcceptEdit(pending.editId, true);
    this.cleanupEdit(pending);
  }

  // -----------------------------------------------------------------------
  // Delete — confirmation dialog
  // -----------------------------------------------------------------------

  private async handleDelete(edit: FileEditParams): Promise<void> {
    const pending: PendingDelete = {
      kind: 'delete',
      editId: edit.editId,
      filePath: edit.path,
    };
    this.pending.set(edit.editId, pending);

    // Yolo mode: auto-accept.
    if (this.isYoloMode()) {
      this.flashNotification(`Rubyn auto-deleted ${this.basename(edit.path)}`);
      await this.acceptDelete(pending);
      return;
    }

    const choice = await vscode.window.showWarningMessage(
      `Rubyn wants to delete ${this.basename(edit.path)}`,
      { modal: false },
      'Accept',
      'Reject',
    );

    if (choice === 'Accept') {
      await this.acceptDelete(pending);
    } else {
      await this.rejectEdit(pending);
    }
  }

  private async acceptDelete(pending: PendingDelete): Promise<void> {
    const fileUri = vscode.Uri.file(pending.filePath);

    try {
      await vscode.workspace.fs.delete(fileUri);
    } catch {
      // File may already have been removed — that is fine.
    }

    this.sendAcceptEdit(pending.editId, true);
    this.cleanupEdit(pending);
  }

  // -----------------------------------------------------------------------
  // Reject (common for all types)
  // -----------------------------------------------------------------------

  private async rejectEdit(pending: PendingEdit): Promise<void> {
    this.sendAcceptEdit(pending.editId, false);
    this.cleanupEdit(pending);
  }

  // -----------------------------------------------------------------------
  // Grouped / batch edits
  // -----------------------------------------------------------------------

  /**
   * Accept all pending edits that share the given session id.
   * Useful for "Accept All" UX on grouped edits.
   */
  async acceptSession(sessionId: string): Promise<void> {
    const related = [...this.pending.values()].filter(
      (e) => e.sessionId === sessionId,
    );

    for (const edit of related) {
      switch (edit.kind) {
        case 'modify':
          await this.acceptModify(edit);
          break;
        case 'create':
          await this.acceptCreate(edit);
          break;
        case 'delete':
          await this.acceptDelete(edit);
          break;
      }
    }
  }

  /**
   * Reject all pending edits that share the given session id.
   */
  async rejectSession(sessionId: string): Promise<void> {
    const related = [...this.pending.values()].filter(
      (e) => e.sessionId === sessionId,
    );

    for (const edit of related) {
      await this.rejectEdit(edit);
    }
  }

  // -----------------------------------------------------------------------
  // Helpers
  // -----------------------------------------------------------------------

  /**
   * Build the full proposed file content by applying hunks over the original
   * text.  If `fullContent` is supplied (some edits send the whole file) it
   * takes precedence.
   */
  private async buildProposedContent(
    originalUri: vscode.Uri,
    hunks: Hunk[],
    fullContent?: string,
  ): Promise<string> {
    if (fullContent !== undefined) {
      return fullContent;
    }

    let originalText: string;
    try {
      const doc = await vscode.workspace.openTextDocument(originalUri);
      originalText = doc.getText();
    } catch {
      // File might not be open yet — read from disk.
      const bytes = await vscode.workspace.fs.readFile(originalUri);
      originalText = new TextDecoder().decode(bytes);
    }

    if (hunks.length === 0) {
      return originalText;
    }

    const lines = originalText.split('\n');

    // Apply hunks in reverse order so earlier line numbers stay valid.
    const sorted = [...hunks].sort((a, b) => b.startLine - a.startLine);

    for (const hunk of sorted) {
      const newLines = hunk.newContent.split('\n');
      // startLine and endLine are 1-based inclusive.
      const deleteCount = hunk.endLine - hunk.startLine + 1;
      lines.splice(hunk.startLine - 1, deleteCount, ...newLines);
    }

    return lines.join('\n');
  }

  /** Send the acceptEdit response back to the CLI process. */
  private sendAcceptEdit(editId: string, accepted: boolean): void {
    const params: AcceptEditParams = { editId, accepted };
    this.bridge.notify('acceptEdit', params as unknown as Record<string, unknown>);
  }

  /** Remove a pending edit and clean up its virtual documents. */
  private cleanupEdit(pending: PendingEdit): void {
    this.pending.delete(pending.editId);

    if (pending.kind === 'modify') {
      this.contentProvider.remove(pending.proposedUri);
      this.closeDiffEditor(pending.proposedUri);
    }
  }

  /** Best-effort close of a tab showing the given URI. */
  private closeDiffEditor(uri: vscode.Uri): void {
    const uriStr = uri.toString();

    for (const group of vscode.window.tabGroups.all) {
      for (const tab of group.tabs) {
        // Diff tabs expose two URIs via TabInputTextDiff.
        const input = tab.input;
        if (
          input &&
          typeof input === 'object' &&
          'modified' in input &&
          (input as { modified: vscode.Uri }).modified.toString() === uriStr
        ) {
          vscode.window.tabGroups.close(tab).then(undefined, () => {});
          return;
        }

        // Plain preview tabs (create flow).
        if (
          input &&
          typeof input === 'object' &&
          'uri' in input &&
          (input as { uri: vscode.Uri }).uri.toString() === uriStr
        ) {
          vscode.window.tabGroups.close(tab).then(undefined, () => {});
          return;
        }
      }
    }
  }

  /** Check the user's yolo-mode setting. */
  private isYoloMode(): boolean {
    return (
      vscode.workspace
        .getConfiguration('rubyn-code')
        .get<boolean>('yoloMode', false)
    );
  }

  /** Show a brief auto-dismiss notification (for yolo mode). */
  private flashNotification(message: string): void {
    // VS Code info messages auto-dismiss after a few seconds when not modal.
    vscode.window.showInformationMessage(message);
  }

  /** Extract the basename from a full file path. */
  private basename(filePath: string): string {
    const parts = filePath.split('/');
    return parts[parts.length - 1] || filePath;
  }

  // -----------------------------------------------------------------------
  // Public accessors
  // -----------------------------------------------------------------------

  /** Number of edits waiting for user decision. */
  get pendingCount(): number {
    return this.pending.size;
  }

  /** Whether a specific editId is still pending. */
  hasPending(editId: string): boolean {
    return this.pending.has(editId);
  }

  // -----------------------------------------------------------------------
  // Disposable
  // -----------------------------------------------------------------------

  dispose(): void {
    // Reject everything that is still pending so the CLI does not hang.
    for (const edit of this.pending.values()) {
      this.sendAcceptEdit(edit.editId, false);
    }
    this.pending.clear();

    this.contentProvider.dispose();

    for (const d of this.disposables) {
      d.dispose();
    }
    this.disposables.length = 0;
  }
}
