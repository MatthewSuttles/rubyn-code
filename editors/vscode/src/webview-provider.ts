/**
 * Rubyn Code — Webview provider for the sidebar chat panel.
 *
 * Implements VS Code's WebviewViewProvider to render a React-based chat UI
 * inside the `rubyn-code.chat` view. Bridges messages between the webview
 * and the Rubyn Code CLI process via the Bridge instance.
 */

import * as vscode from 'vscode';
import * as path from 'path';
import { Bridge } from './bridge';

/** Messages the webview can send to the extension host. */
interface WebviewToExtension {
  type: 'sendPrompt' | 'approveToolUse' | 'cancel';
  payload?: Record<string, unknown>;
}

/** Notification methods forwarded from bridge to webview. */
const FORWARDED_NOTIFICATIONS = [
  'stream/text',
  'stream/codeBlock',
  'tool/use',
  'tool/result',
  'agent/status',
  'session/cost',
] as const;

export class ChatWebviewProvider implements vscode.WebviewViewProvider {
  public static readonly viewType = 'rubyn-code.chat';

  private view?: vscode.WebviewView;
  private readonly extensionUri: vscode.Uri;
  private readonly bridge: Bridge;
  private readonly disposables: vscode.Disposable[] = [];

  /** Notification handlers registered on the bridge; stored so we can remove them. */
  private readonly bridgeListeners: Array<{
    method: string;
    handler: (params: Record<string, unknown> | undefined) => void;
  }> = [];

  constructor(extensionUri: vscode.Uri, bridge: Bridge) {
    this.extensionUri = extensionUri;
    this.bridge = bridge;
  }

  // ---------------------------------------------------------------------------
  // WebviewViewProvider
  // ---------------------------------------------------------------------------

  resolveWebviewView(
    webviewView: vscode.WebviewView,
    _context: vscode.WebviewViewResolveContext,
    _token: vscode.CancellationToken,
  ): void {
    this.view = webviewView;

    webviewView.webview.options = {
      enableScripts: true,
      localResourceRoots: [
        vscode.Uri.joinPath(this.extensionUri, 'dist'),
        vscode.Uri.joinPath(this.extensionUri, 'webview'),
      ],
    };

    webviewView.webview.html = this.getHtmlForWebview(webviewView.webview);

    // Listen for messages from the webview.
    webviewView.webview.onDidReceiveMessage(
      (message: WebviewToExtension) => this.handleWebviewMessage(message),
      undefined,
      this.disposables,
    );

    // Forward bridge notifications to the webview.
    this.registerBridgeForwarding();

    // Cleanup on dispose.
    webviewView.onDidDispose(() => this.onDispose(), undefined, this.disposables);

    // Re-post current state when the webview becomes visible again.
    webviewView.onDidChangeVisibility(() => {
      if (webviewView.visible) {
        this.postMessage({ type: 'webview/restored' });
      }
    });
  }

  // ---------------------------------------------------------------------------
  // Public helpers
  // ---------------------------------------------------------------------------

  /** Post a message to the webview (if it exists and is visible). */
  postMessage(message: Record<string, unknown>): void {
    this.view?.webview.postMessage(message);
  }

  // ---------------------------------------------------------------------------
  // Webview -> Extension message handling
  // ---------------------------------------------------------------------------

  private handleWebviewMessage(message: WebviewToExtension): void {
    switch (message.type) {
      case 'sendPrompt': {
        const { text, sessionId, context } = (message.payload ?? {}) as Record<string, unknown>;
        this.bridge.request('prompt', {
          text: text as string,
          sessionId: (sessionId as string) || this.generateSessionId(),
          context: context ?? this.gatherPromptContext(),
        }).catch((err: Error) => {
          this.postMessage({
            type: 'error',
            payload: { message: err.message },
          });
        });
        break;
      }

      case 'approveToolUse': {
        const { requestId, approved } = (message.payload ?? {}) as Record<string, unknown>;
        this.bridge.notify('tool/approve', {
          requestId: requestId as string,
          approved: approved as boolean,
        });
        break;
      }

      case 'cancel': {
        this.bridge.notify('cancel', {});
        break;
      }
    }
  }

  // ---------------------------------------------------------------------------
  // Bridge -> Webview notification forwarding
  // ---------------------------------------------------------------------------

  private registerBridgeForwarding(): void {
    for (const method of FORWARDED_NOTIFICATIONS) {
      const handler = (params: Record<string, unknown> | undefined) => {
        this.postMessage({ type: method, payload: params ?? {} });
      };
      this.bridge.on(method, handler);
      this.bridgeListeners.push({ method, handler });
    }
  }

  private unregisterBridgeForwarding(): void {
    for (const { method, handler } of this.bridgeListeners) {
      this.bridge.off(method, handler);
    }
    this.bridgeListeners.length = 0;
  }

  // ---------------------------------------------------------------------------
  // HTML generation
  // ---------------------------------------------------------------------------

  private getHtmlForWebview(webview: vscode.Webview): string {
    const scriptUri = this.getUri(webview, 'dist', 'webview.js');
    const styleUri = this.getUri(webview, 'dist', 'webview.css');
    const nonce = this.getNonce();

    return /* html */ `<!DOCTYPE html>
<html lang="en">
<head>
  <meta charset="UTF-8" />
  <meta name="viewport" content="width=device-width, initial-scale=1.0" />
  <meta
    http-equiv="Content-Security-Policy"
    content="default-src 'none';
             style-src ${webview.cspSource} 'unsafe-inline';
             script-src 'nonce-${nonce}';
             font-src ${webview.cspSource};
             img-src ${webview.cspSource} data:;"
  />
  <link rel="stylesheet" href="${styleUri}" />
  <title>Rubyn Code</title>
</head>
<body>
  <div id="root"></div>
  <script nonce="${nonce}">
    window.vscodeApi = acquireVsCodeApi();
  </script>
  <script nonce="${nonce}" src="${scriptUri}"></script>
</body>
</html>`;
  }

  /** Build a webview-safe URI for a file relative to the extension root. */
  private getUri(webview: vscode.Webview, ...pathSegments: string[]): vscode.Uri {
    return webview.asWebviewUri(
      vscode.Uri.joinPath(this.extensionUri, ...pathSegments),
    );
  }

  /** Generate a cryptographic nonce for the CSP script-src. */
  private getNonce(): string {
    const chars = 'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789';
    let nonce = '';
    for (let i = 0; i < 32; i++) {
      nonce += chars.charAt(Math.floor(Math.random() * chars.length));
    }
    return nonce;
  }

  // ---------------------------------------------------------------------------
  // Context helpers
  // ---------------------------------------------------------------------------

  private gatherPromptContext(): Record<string, unknown> {
    const editor = vscode.window.activeTextEditor;
    const ctx: Record<string, unknown> = {
      workspacePath: vscode.workspace.workspaceFolders?.[0]?.uri.fsPath ?? '',
    };

    if (editor) {
      ctx.activeFile = editor.document.uri.fsPath;
      ctx.language = editor.document.languageId;
      ctx.cursorLine = editor.selection.active.line;

      if (!editor.selection.isEmpty) {
        ctx.selection = {
          startLine: editor.selection.start.line,
          endLine: editor.selection.end.line,
          text: editor.document.getText(editor.selection),
        };
      }
    }

    ctx.openFiles = vscode.window.visibleTextEditors.map((e) => e.document.uri.fsPath);

    return ctx;
  }

  private generateSessionId(): string {
    return `session_${Date.now()}_${Math.random().toString(36).slice(2, 8)}`;
  }

  // ---------------------------------------------------------------------------
  // Lifecycle
  // ---------------------------------------------------------------------------

  private onDispose(): void {
    this.unregisterBridgeForwarding();
    for (const d of this.disposables) {
      d.dispose();
    }
    this.disposables.length = 0;
    this.view = undefined;
  }

  dispose(): void {
    this.onDispose();
  }
}
