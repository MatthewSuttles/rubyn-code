/**
 * Rubyn Code — Tool approval card component.
 *
 * Shows tool invocations inline in the chat with approve/deny controls,
 * mini diff previews for file edits, and command highlighting for bash.
 */

import React, { useCallback, useState } from 'react';

export interface ToolApprovalProps {
  requestId: string;
  tool: string;
  args: Record<string, unknown>;
  requiresApproval: boolean;
  result?: { success: boolean; summary: string } | null;
  onApprove: (requestId: string) => void;
  onDeny: (requestId: string) => void;
}

export const ToolApproval: React.FC<ToolApprovalProps> = ({
  requestId,
  tool,
  args,
  requiresApproval,
  result,
  onApprove,
  onDeny,
}) => {
  const [expanded, setExpanded] = useState(false);

  const handleApprove = useCallback(() => onApprove(requestId), [requestId, onApprove]);
  const handleDeny = useCallback(() => onDeny(requestId), [requestId, onDeny]);

  const isFileEdit = tool === 'write_file' || tool === 'edit_file';
  const isBash = tool === 'bash' || tool === 'execute';
  const isResolved = result != null;

  const statusLabel = isResolved
    ? result!.success
      ? 'completed'
      : 'failed'
    : requiresApproval
    ? 'awaiting approval'
    : 'auto-approved';

  return (
    <div className="tool-card">
      <div
        className="tool-card-header"
        onClick={() => setExpanded(!expanded)}
        role="button"
        tabIndex={0}
        onKeyDown={(e) => {
          if (e.key === 'Enter' || e.key === ' ') { setExpanded(!expanded); }
        }}
      >
        <span className="tool-name">{formatToolName(tool)}</span>
        <span className="tool-status">{statusLabel}</span>
        <span className={`expand-toggle${expanded ? ' expanded' : ''}`}>&#9654;</span>
      </div>

      {expanded && (
        <div className="tool-card-body">
          {/* Bash command highlight */}
          {isBash && args.command && (
            <div className="tool-card-bash-cmd">
              {String(args.command)}
            </div>
          )}

          {/* File edit mini diff */}
          {isFileEdit && renderFileDiff(args)}

          {/* Generic args (collapsed details) */}
          {!isBash && !isFileEdit && (
            <div className="tool-card-args">
              {JSON.stringify(args, null, 2)}
            </div>
          )}

          {/* If bash, also show full args for completeness */}
          {isBash && Object.keys(args).length > 1 && (
            <div className="tool-card-args">
              {JSON.stringify(args, null, 2)}
            </div>
          )}

          {/* Result summary */}
          {isResolved && (
            <div className={`tool-result ${result!.success ? 'success' : 'failure'}`}>
              {result!.summary}
            </div>
          )}

          {/* Approval buttons */}
          {requiresApproval && !isResolved && (
            <div className="tool-card-actions">
              <button className="btn-approve" onClick={handleApprove}>
                Approve
              </button>
              <button className="btn-deny" onClick={handleDeny}>
                Deny
              </button>
            </div>
          )}

          {/* Auto-approve indicator */}
          {!requiresApproval && !isResolved && (
            <div className="auto-approved-badge">Auto-approved (YOLO mode)</div>
          )}
        </div>
      )}

      {/* Inline approval buttons when collapsed */}
      {!expanded && requiresApproval && !isResolved && (
        <div className="tool-card-body">
          <div className="tool-card-actions">
            <button className="btn-approve" onClick={handleApprove}>
              Approve
            </button>
            <button className="btn-deny" onClick={handleDeny}>
              Deny
            </button>
          </div>
        </div>
      )}
    </div>
  );
};

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

function formatToolName(tool: string): string {
  return tool
    .replace(/_/g, ' ')
    .replace(/\b\w/g, (c) => c.toUpperCase());
}

function renderFileDiff(args: Record<string, unknown>): React.ReactNode {
  const path = (args.path ?? args.file_path ?? '') as string;
  const oldContent = (args.old_string ?? args.originalContent ?? '') as string;
  const newContent = (args.new_string ?? args.content ?? args.newContent ?? '') as string;

  if (!oldContent && !newContent) {
    return (
      <div className="tool-card-args">
        {path && <div style={{ marginBottom: 4, fontWeight: 600 }}>{path}</div>}
        {JSON.stringify(args, null, 2)}
      </div>
    );
  }

  const oldLines = oldContent ? oldContent.split('\n') : [];
  const newLines = newContent ? newContent.split('\n') : [];

  return (
    <div className="tool-card-diff">
      {path && (
        <div style={{ marginBottom: 4, fontSize: 11, color: 'var(--vscode-descriptionForeground)' }}>
          {path}
        </div>
      )}
      {oldLines.map((line, i) => (
        <div key={`r-${i}`} className="diff-line removed">- {line}</div>
      ))}
      {newLines.map((line, i) => (
        <div key={`a-${i}`} className="diff-line added">+ {line}</div>
      ))}
    </div>
  );
}
