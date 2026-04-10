/**
 * Rubyn Code VS Code extension — activation and lifecycle.
 */

import * as vscode from 'vscode';
import { Bridge } from './bridge';
import { ProcessManager } from './process-manager';
import { ContextProvider } from './context-provider';
import { createStatusBar } from './status-bar';
import { InitializeParams, InitializeResult } from './types';

// ---------------------------------------------------------------------------
// Module-level state (accessible from both activate and deactivate)
// ---------------------------------------------------------------------------

let bridge: Bridge | undefined;
let processManager: ProcessManager | undefined;
let contextProvider: ContextProvider | undefined;

// ---------------------------------------------------------------------------
// Activation
// ---------------------------------------------------------------------------

export async function activate(
  context: vscode.ExtensionContext,
): Promise<void> {
  // 1. Create output channel.
  const outputChannel = vscode.window.createOutputChannel('Rubyn Code');
  outputChannel.appendLine('Rubyn Code extension activating...');
  context.subscriptions.push(outputChannel);

  // 2. Create ProcessManager and spawn the CLI process.
  processManager = new ProcessManager(outputChannel);
  context.subscriptions.push(processManager);

  let child;
  try {
    child = processManager.spawn();
  } catch {
    // Error already surfaced to user by ProcessManager.
    return;
  }

  // 3. Create Bridge connected to the process stdio.
  if (!child.stdin || !child.stdout) {
    outputChannel.appendLine('ERROR: Failed to get stdio streams from child process');
    vscode.window.showErrorMessage('Failed to start Rubyn Code: could not connect to process.');
    return;
  }

  bridge = new Bridge(child.stdin, child.stdout);
  processManager.setBridge(bridge);
  context.subscriptions.push({ dispose: () => bridge?.dispose() });

  bridge.on('error', (err: Error) => {
    outputChannel.appendLine(`[bridge error] ${err.message}`);
  });

  bridge.on('close', () => {
    outputChannel.appendLine('[bridge] Connection closed');
  });

  // 4. Send initialize request.
  const workspacePath =
    vscode.workspace.workspaceFolders?.[0]?.uri.fsPath ?? '';
  const extensionVersion =
    vscode.extensions.getExtension('rubyn.rubyn-code')?.packageJSON?.version ??
    '0.1.0';

  try {
    const initResult = await bridge.request<InitializeResult>('initialize', {
      workspacePath,
      extensionVersion,
      capabilities: {
        inlineDiff: true,
        streaming: true,
      },
    } as InitializeParams as unknown as Record<string, unknown>);

    outputChannel.appendLine(
      `Server initialized: v${initResult.serverVersion} ` +
        `(${initResult.capabilities.tools} tools, ${initResult.capabilities.skills} skills)`,
    );
  } catch (err) {
    outputChannel.appendLine(
      `Initialize failed: ${err instanceof Error ? err.message : String(err)}`,
    );
    // Continue anyway — some commands may still work.
  }

  // 5. Create ContextProvider.
  contextProvider = new ContextProvider();
  context.subscriptions.push(contextProvider);

  // 6. Register commands.

  // rubyn-code.openChat — focus the chat webview panel.
  context.subscriptions.push(
    vscode.commands.registerCommand('rubyn-code.openChat', () => {
      vscode.commands.executeCommand('rubyn-code.chat.focus');
    }),
  );

  // rubyn-code.reviewPR — send review request with git base branch.
  context.subscriptions.push(
    vscode.commands.registerCommand('rubyn-code.reviewPR', async () => {
      if (!bridge) {
        vscode.window.showErrorMessage('Rubyn Code is not running.');
        return;
      }

      const baseBranch = await vscode.window.showInputBox({
        prompt: 'Base branch for PR review',
        value: 'main',
        placeHolder: 'main',
      });

      if (baseBranch === undefined) {
        return; // Cancelled.
      }

      try {
        await bridge.request('review', {
          baseBranch,
          focus: 'all',
        });
      } catch (err) {
        vscode.window.showErrorMessage(
          `PR review failed: ${err instanceof Error ? err.message : String(err)}`,
        );
      }
    }),
  );

  // rubyn-code.refactorSelection — refactor selected code.
  context.subscriptions.push(
    vscode.commands.registerCommand(
      'rubyn-code.refactorSelection',
      async () => {
        if (!bridge || !contextProvider) {
          vscode.window.showErrorMessage('Rubyn Code is not running.');
          return;
        }

        const editor = vscode.window.activeTextEditor;
        if (!editor || editor.selection.isEmpty) {
          vscode.window.showWarningMessage(
            'Select some code first, then run Refactor Selection.',
          );
          return;
        }

        const { prompt, context: ctx } = await contextProvider.enrichPrompt(
          'refactorSelection',
          'Refactor this code. Improve readability, reduce duplication, and follow Ruby/Rails best practices.',
        );

        try {
          await bridge.request('prompt', {
            text: prompt,
            context: ctx,
            sessionId: generateSessionId(),
          });
        } catch (err) {
          vscode.window.showErrorMessage(
            `Refactor failed: ${err instanceof Error ? err.message : String(err)}`,
          );
        }
      },
    ),
  );

  // rubyn-code.generateSpecs — generate specs for the active file.
  context.subscriptions.push(
    vscode.commands.registerCommand('rubyn-code.generateSpecs', async () => {
      if (!bridge || !contextProvider) {
        vscode.window.showErrorMessage('Rubyn Code is not running.');
        return;
      }

      const editor = vscode.window.activeTextEditor;
      if (!editor) {
        vscode.window.showWarningMessage(
          'Open a file first, then run Generate Specs.',
        );
        return;
      }

      const { prompt, context: ctx } = await contextProvider.enrichPrompt(
        'generateSpecs',
        'Write specs for this file. Provide thorough test coverage with edge cases.',
      );

      try {
        await bridge.request('prompt', {
          text: prompt,
          context: ctx,
          sessionId: generateSessionId(),
        });
      } catch (err) {
        vscode.window.showErrorMessage(
          `Generate specs failed: ${err instanceof Error ? err.message : String(err)}`,
        );
      }
    }),
  );

  // rubyn-code.explainCode — explain selected code.
  context.subscriptions.push(
    vscode.commands.registerCommand('rubyn-code.explainCode', async () => {
      if (!bridge || !contextProvider) {
        vscode.window.showErrorMessage('Rubyn Code is not running.');
        return;
      }

      const editor = vscode.window.activeTextEditor;
      if (!editor || editor.selection.isEmpty) {
        vscode.window.showWarningMessage(
          'Select some code first, then run Explain Code.',
        );
        return;
      }

      const { prompt, context: ctx } = await contextProvider.enrichPrompt(
        'explainCode',
        'Explain this code. Describe what it does, why, and any notable patterns or potential issues.',
      );

      try {
        await bridge.request('prompt', {
          text: prompt,
          context: ctx,
          sessionId: generateSessionId(),
        });
      } catch (err) {
        vscode.window.showErrorMessage(
          `Explain code failed: ${err instanceof Error ? err.message : String(err)}`,
        );
      }
    }),
  );

  // 7. Register status bar.
  try {
    const statusBarDisposable = createStatusBar(context, bridge);
    context.subscriptions.push(statusBarDisposable);
  } catch {
    // Status bar module may not be available yet (being built by another agent).
    outputChannel.appendLine(
      'Status bar module not available — skipping status bar registration.',
    );
  }

  outputChannel.appendLine('Rubyn Code extension activated.');
}

// ---------------------------------------------------------------------------
// Deactivation
// ---------------------------------------------------------------------------

export async function deactivate(): Promise<void> {
  if (bridge) {
    try {
      await bridge.request('shutdown', undefined, 3_000);
    } catch {
      // Best effort.
    }
    bridge.dispose();
    bridge = undefined;
  }

  if (processManager) {
    await processManager.kill();
    processManager = undefined;
  }

  if (contextProvider) {
    contextProvider.dispose();
    contextProvider = undefined;
  }
}

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

/** Generate a random session ID for prompt requests. */
function generateSessionId(): string {
  const timestamp = Date.now().toString(36);
  const random = Math.random().toString(36).slice(2, 10);
  return `session_${timestamp}_${random}`;
}
