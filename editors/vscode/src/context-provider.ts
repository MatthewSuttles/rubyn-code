import * as vscode from 'vscode';
import * as path from 'path';
import { PromptContext, Selection } from './types';

export interface ProjectContext {
  isRails: boolean;
  rubyVersion: string | null;
  railsVersion: string | null;
  testFramework: 'rspec' | 'minitest' | null;
  hasRubynMd: boolean;
}

/** Commands that should have context automatically enriched. */
const CONTEXT_ENRICHED_COMMANDS = new Set([
  'refactorSelection',
  'generateSpecs',
  'explainCode',
]);

export class ContextProvider implements vscode.Disposable {
  private cachedProjectContext: ProjectContext | null = null;
  private watchers: vscode.FileSystemWatcher[] = [];

  constructor() {
    this.setupFileWatchers();
  }

  // ---------------------------------------------------------------------------
  // Public API
  // ---------------------------------------------------------------------------

  /** Return editor-level context derived from the active window state. */
  getActiveContext(): PromptContext {
    const editor = vscode.window.activeTextEditor;
    const workspaceFolder = vscode.workspace.workspaceFolders?.[0];
    const workspacePath = workspaceFolder?.uri.fsPath ?? '';

    const result: PromptContext = { workspacePath };

    if (editor) {
      const docPath = editor.document.uri.fsPath;
      result.activeFile = workspacePath
        ? path.relative(workspacePath, docPath)
        : docPath;

      result.language = editor.document.languageId;
      result.cursorLine = editor.selection.active.line + 1; // 1-based

      const sel = editor.selection;
      if (!sel.isEmpty) {
        result.selection = {
          startLine: sel.start.line + 1,
          endLine: sel.end.line + 1,
          text: editor.document.getText(sel),
        };
      }
    }

    result.openFiles = vscode.window.tabGroups.all
      .flatMap((group) => group.tabs)
      .map((tab) => {
        const input = tab.input;
        if (input instanceof vscode.TabInputText) {
          const fsPath = input.uri.fsPath;
          return workspacePath ? path.relative(workspacePath, fsPath) : fsPath;
        }
        return null;
      })
      .filter((p): p is string => p !== null);

    return result;
  }

  /** Return project-level context, cached until Gemfile/ruby-version changes. */
  async getProjectContext(): Promise<ProjectContext> {
    if (this.cachedProjectContext) {
      return this.cachedProjectContext;
    }

    const ctx = await this.buildProjectContext();
    this.cachedProjectContext = ctx;
    return ctx;
  }

  /**
   * Build a full prompt payload for a given command, automatically enriching
   * with active and project context when the command is in the enriched set.
   */
  async enrichPrompt(
    command: string,
    userPrompt: string,
  ): Promise<{ prompt: string; context: PromptContext; project: ProjectContext | null }> {
    const context = this.getActiveContext();
    let project: ProjectContext | null = null;

    if (CONTEXT_ENRICHED_COMMANDS.has(command)) {
      project = await this.getProjectContext();
    }

    const sections: string[] = [];

    if (project) {
      const parts: string[] = [];
      if (project.isRails) {
        parts.push(`Rails project (Rails ${project.railsVersion ?? 'unknown'})`);
      }
      if (project.rubyVersion) {
        parts.push(`Ruby ${project.rubyVersion}`);
      }
      if (project.testFramework) {
        parts.push(`Test framework: ${project.testFramework}`);
      }
      if (parts.length > 0) {
        sections.push(`[Project] ${parts.join(' | ')}`);
      }
    }

    if (context.activeFile) {
      sections.push(`[File] ${context.activeFile} (${context.language ?? 'unknown'})`);
    }

    if (context.selection) {
      sections.push(
        `[Selection] Lines ${context.selection.startLine}-${context.selection.endLine}:\n${context.selection.text}`,
      );
    }

    sections.push(userPrompt);

    return {
      prompt: sections.join('\n\n'),
      context,
      project,
    };
  }

  /** Clean up file watchers. */
  dispose(): void {
    for (const watcher of this.watchers) {
      watcher.dispose();
    }
    this.watchers = [];
  }

  // ---------------------------------------------------------------------------
  // Internals
  // ---------------------------------------------------------------------------

  private setupFileWatchers(): void {
    const gemfileWatcher = vscode.workspace.createFileSystemWatcher(
      '**/Gemfile.lock',
    );
    const gemfileSourceWatcher = vscode.workspace.createFileSystemWatcher(
      '**/Gemfile',
    );
    const rubyVersionWatcher = vscode.workspace.createFileSystemWatcher(
      '**/.ruby-version',
    );

    const invalidate = () => {
      this.cachedProjectContext = null;
    };

    for (const watcher of [gemfileWatcher, gemfileSourceWatcher, rubyVersionWatcher]) {
      watcher.onDidChange(invalidate);
      watcher.onDidCreate(invalidate);
      watcher.onDidDelete(invalidate);
      this.watchers.push(watcher);
    }
  }

  private async buildProjectContext(): Promise<ProjectContext> {
    const workspaceFolder = vscode.workspace.workspaceFolders?.[0];
    if (!workspaceFolder) {
      return {
        isRails: false,
        rubyVersion: null,
        railsVersion: null,
        testFramework: null,
        hasRubynMd: false,
      };
    }

    const root = workspaceFolder.uri;

    const [gemfileContent, gemfileLockContent, rubyVersionContent, hasRubynMd] =
      await Promise.all([
        this.readWorkspaceFile(root, 'Gemfile'),
        this.readWorkspaceFile(root, 'Gemfile.lock'),
        this.readWorkspaceFile(root, '.ruby-version'),
        this.detectRubynMd(root),
      ]);

    const isRails = gemfileContent !== null && /gem\s+['"]rails['"]/.test(gemfileContent);

    const rubyVersion = this.parseRubyVersion(rubyVersionContent, gemfileContent);
    const railsVersion = this.parseRailsVersion(gemfileLockContent);
    const testFramework = await this.detectTestFramework(root, gemfileContent);

    return {
      isRails,
      rubyVersion,
      railsVersion,
      testFramework,
      hasRubynMd,
    };
  }

  private async readWorkspaceFile(
    root: vscode.Uri,
    relativePath: string,
  ): Promise<string | null> {
    try {
      const uri = vscode.Uri.joinPath(root, relativePath);
      const bytes = await vscode.workspace.fs.readFile(uri);
      return Buffer.from(bytes).toString('utf-8');
    } catch {
      return null;
    }
  }

  private parseRubyVersion(
    rubyVersionFile: string | null,
    gemfileContent: string | null,
  ): string | null {
    // Prefer .ruby-version file
    if (rubyVersionFile) {
      const trimmed = rubyVersionFile.trim();
      if (trimmed.length > 0) {
        // Strip optional "ruby-" prefix (e.g. "ruby-3.2.2")
        return trimmed.replace(/^ruby-/i, '');
      }
    }

    // Fallback: parse from Gemfile  (e.g.  ruby '3.2.2'  or  ruby "3.2.2")
    if (gemfileContent) {
      const match = gemfileContent.match(/^\s*ruby\s+['"]([^'"]+)['"]/m);
      if (match) {
        return match[1];
      }
    }

    return null;
  }

  private parseRailsVersion(gemfileLockContent: string | null): string | null {
    if (!gemfileLockContent) {
      return null;
    }

    // Gemfile.lock lists gems indented under their parent like:
    //     rails (7.1.3)
    const match = gemfileLockContent.match(/^\s+rails\s+\(([^)]+)\)/m);
    return match ? match[1] : null;
  }

  private async detectTestFramework(
    root: vscode.Uri,
    gemfileContent: string | null,
  ): Promise<'rspec' | 'minitest' | null> {
    // Check Gemfile first for explicit declarations
    if (gemfileContent) {
      if (/gem\s+['"]rspec-rails['"]/.test(gemfileContent) ||
          /gem\s+['"]rspec['"]/.test(gemfileContent)) {
        return 'rspec';
      }
    }

    // Check for spec/ directory (rspec) vs test/ directory (minitest)
    const specExists = await this.directoryExists(root, 'spec');
    if (specExists) {
      return 'rspec';
    }

    const testExists = await this.directoryExists(root, 'test');
    if (testExists) {
      return 'minitest';
    }

    return null;
  }

  private async directoryExists(
    root: vscode.Uri,
    dirName: string,
  ): Promise<boolean> {
    try {
      const uri = vscode.Uri.joinPath(root, dirName);
      const stat = await vscode.workspace.fs.stat(uri);
      return (stat.type & vscode.FileType.Directory) !== 0;
    } catch {
      return false;
    }
  }

  private async detectRubynMd(root: vscode.Uri): Promise<boolean> {
    const rubynMdExists = await this.fileExists(root, 'RUBYN.md');
    if (rubynMdExists) {
      return true;
    }

    return this.directoryExists(root, '.rubyn-code');
  }

  private async fileExists(
    root: vscode.Uri,
    fileName: string,
  ): Promise<boolean> {
    try {
      const uri = vscode.Uri.joinPath(root, fileName);
      const stat = await vscode.workspace.fs.stat(uri);
      return (stat.type & vscode.FileType.File) !== 0;
    } catch {
      return false;
    }
  }
}
