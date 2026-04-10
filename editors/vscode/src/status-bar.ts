/**
 * Rubyn Code VS Code extension — status bar integration.
 *
 * Displays agent state, session cost, and token usage in the editor's
 * status bar, updating in real time via JSON-RPC notifications from the
 * Rubyn Code CLI process.
 */

import * as vscode from 'vscode';
import { Bridge } from './bridge';
import { AgentStatusParams, SessionCostParams } from './types';

// ---------------------------------------------------------------------------
// Status bar item
// ---------------------------------------------------------------------------

export class StatusBar implements vscode.Disposable {
  private readonly item: vscode.StatusBarItem;
  private agentState: AgentStatusParams['state'] = 'idle';
  private detail: string | undefined;
  private toolCalls = 0;
  private tokensUsed = 0;
  private cost = 0;

  /** Latest session-level cost snapshot (if received). */
  private sessionCost: SessionCostParams | undefined;

  constructor() {
    this.item = vscode.window.createStatusBarItem(
      vscode.StatusBarAlignment.Left,
      100,
    );
    this.item.command = 'rubyn-code.openChat';
    this.render();
    this.item.show();
  }

  // -----------------------------------------------------------------------
  // Public update methods
  // -----------------------------------------------------------------------

  /** Called when an `agent/status` notification arrives. */
  updateAgentStatus(params: AgentStatusParams): void {
    this.agentState = params.state;
    this.detail = params.detail;

    if (params.toolCalls !== undefined) {
      this.toolCalls = params.toolCalls;
    }
    if (params.tokensUsed !== undefined) {
      this.tokensUsed = params.tokensUsed;
    }
    if (params.cost !== undefined) {
      this.cost = params.cost;
    }

    this.render();
  }

  /** Called when a `session/cost` notification arrives. */
  updateSessionCost(params: SessionCostParams): void {
    this.sessionCost = params;
    this.render();
  }

  /** Reset to the disconnected state (e.g. when the CLI process exits). */
  setDisconnected(): void {
    this.agentState = 'idle';
    this.detail = undefined;
    this.renderDisconnected();
  }

  // -----------------------------------------------------------------------
  // Rendering
  // -----------------------------------------------------------------------

  private render(): void {
    this.item.text = this.buildText();
    this.item.tooltip = this.buildTooltip();
    this.item.backgroundColor = this.agentState === 'idle'
      ? undefined
      : undefined; // reserved for future error highlighting
  }

  private renderDisconnected(): void {
    this.item.text = '$(debug-disconnect) Rubyn \u00b7 disconnected';
    this.item.tooltip = 'Rubyn Code is disconnected. Click to reconnect.';
  }

  private buildText(): string {
    switch (this.agentState) {
      case 'idle':
        return '$(ruby) Rubyn';
      case 'thinking':
        return '$(loading~spin) Rubyn \u00b7 thinking\u2026';
      case 'tool_use':
        return `$(tools) Rubyn \u00b7 ${this.detail ?? 'tool'}`;
      case 'streaming':
        return '$(edit) Rubyn \u00b7 writing\u2026';
      case 'reviewing':
        return '$(eye) Rubyn \u00b7 reviewing\u2026';
      case 'learning':
        return '$(book) Rubyn \u00b7 learning\u2026';
      default:
        return '$(ruby) Rubyn';
    }
  }

  private buildTooltip(): vscode.MarkdownString {
    const md = new vscode.MarkdownString('', true);
    md.isTrusted = true;

    md.appendMarkdown('### Rubyn Code\n\n');

    // Session cost
    const totalCost = this.sessionCost?.totalCost ?? this.cost;
    md.appendMarkdown(`**Session cost:** \$${totalCost.toFixed(4)}\n\n`);

    // Tokens
    if (this.sessionCost) {
      const { inputTokens, outputTokens, cacheHits } = this.sessionCost;
      md.appendMarkdown(
        `**Tokens:** ${formatNumber(inputTokens)} in / ${formatNumber(outputTokens)} out` +
        (cacheHits > 0 ? ` (${formatNumber(cacheHits)} cached)` : '') +
        '\n\n',
      );
    } else if (this.tokensUsed > 0) {
      md.appendMarkdown(`**Tokens used:** ${formatNumber(this.tokensUsed)}\n\n`);
    }

    // Tool calls
    if (this.toolCalls > 0) {
      md.appendMarkdown(`**Tool calls:** ${this.toolCalls}\n\n`);
    }

    // Budget
    if (this.sessionCost) {
      const { budgetRemaining, sessionBudget } = this.sessionCost;
      const pct = sessionBudget > 0
        ? Math.round((budgetRemaining / sessionBudget) * 100)
        : 100;
      md.appendMarkdown(
        `**Budget remaining:** \$${budgetRemaining.toFixed(4)} / \$${sessionBudget.toFixed(4)} (${pct}%)\n\n`,
      );
    }

    return md;
  }

  // -----------------------------------------------------------------------
  // Dispose
  // -----------------------------------------------------------------------

  dispose(): void {
    this.item.dispose();
  }
}

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

/** Format a large number with locale separators (e.g. 1,234,567). */
function formatNumber(n: number): string {
  return n.toLocaleString('en-US');
}

// ---------------------------------------------------------------------------
// Factory
// ---------------------------------------------------------------------------

/**
 * Create a {@link StatusBar}, wire it to the bridge's notification events,
 * and return it as a disposable.
 */
export function createStatusBar(bridge: Bridge): vscode.Disposable {
  const statusBar = new StatusBar();

  const onAgentStatus = (params: Record<string, unknown> | undefined) => {
    if (params) {
      statusBar.updateAgentStatus(params as unknown as AgentStatusParams);
    }
  };

  const onSessionCost = (params: Record<string, unknown> | undefined) => {
    if (params) {
      statusBar.updateSessionCost(params as unknown as SessionCostParams);
    }
  };

  const onClose = () => {
    statusBar.setDisconnected();
  };

  bridge.on('agent/status', onAgentStatus);
  bridge.on('session/cost', onSessionCost);
  bridge.on('close', onClose);

  // Return a composite disposable that tears down everything.
  return {
    dispose() {
      bridge.off('agent/status', onAgentStatus);
      bridge.off('session/cost', onSessionCost);
      bridge.off('close', onClose as any);
      statusBar.dispose();
    },
  };
}
