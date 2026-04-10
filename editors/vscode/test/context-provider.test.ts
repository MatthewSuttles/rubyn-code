import { describe, it, expect, vi, beforeEach, afterEach } from 'vitest';
import * as vscode from 'vscode';
import {
  __resetAll,
  __setConfig,
  __getFileSystemWatchers,
  Uri,
  Selection,
  Position,
  TabInputText,
  FileType,
} from './helpers/mock-vscode';
import { ContextProvider } from '../src/context-provider';

describe('ContextProvider', () => {
  let provider: ContextProvider;

  beforeEach(() => {
    __resetAll();

    // Set up a default workspace folder
    (vscode.workspace as any).workspaceFolders = [
      { uri: Uri.file('/workspace/my-app'), name: 'my-app', index: 0 },
    ];
  });

  afterEach(() => {
    provider?.dispose();
    __resetAll();
  });

  // Helper to create a mock editor
  function mockEditor(opts: {
    fsPath: string;
    languageId: string;
    selectionStart?: [number, number];
    selectionEnd?: [number, number];
    selectedText?: string;
    cursorLine?: number;
  }) {
    const selStart = opts.selectionStart ?? [0, 0];
    const selEnd = opts.selectionEnd ?? selStart;
    const selection = new Selection(
      new Position(selStart[0], selStart[1]),
      new Position(selEnd[0], selEnd[1]),
    );

    (vscode.window as any).activeTextEditor = {
      document: {
        uri: Uri.file(opts.fsPath),
        languageId: opts.languageId,
        getText: vi.fn((sel?: any) => {
          if (sel) return opts.selectedText ?? '';
          return '';
        }),
      },
      selection,
    };
  }

  // -----------------------------------------------------------------------
  // Active context with Ruby file
  // -----------------------------------------------------------------------

  describe('getActiveContext()', () => {
    it('returns correct context for a Ruby file with selection', () => {
      mockEditor({
        fsPath: '/workspace/my-app/app/models/user.rb',
        languageId: 'ruby',
        selectionStart: [4, 0],
        selectionEnd: [10, 20],
        selectedText: 'def full_name\n  "#{first_name} #{last_name}"\nend',
        cursorLine: 10,
      });

      provider = new ContextProvider();
      const ctx = provider.getActiveContext();

      expect(ctx.workspacePath).toBe('/workspace/my-app');
      expect(ctx.activeFile).toBe('app/models/user.rb');
      expect(ctx.language).toBe('ruby');
      expect(ctx.cursorLine).toBe(11); // 1-based (selectionEnd line 10 + 1)
      expect(ctx.selection).toBeDefined();
      expect(ctx.selection!.startLine).toBe(5); // 1-based
      expect(ctx.selection!.endLine).toBe(11); // 1-based
      expect(ctx.selection!.text).toBe('def full_name\n  "#{first_name} #{last_name}"\nend');
    });

    it('returns graceful fallback when no file is open', () => {
      (vscode.window as any).activeTextEditor = undefined;

      provider = new ContextProvider();
      const ctx = provider.getActiveContext();

      expect(ctx.workspacePath).toBe('/workspace/my-app');
      expect(ctx.activeFile).toBeUndefined();
      expect(ctx.language).toBeUndefined();
      expect(ctx.selection).toBeUndefined();
      expect(ctx.cursorLine).toBeUndefined();
    });

    it('reports correct language for non-Ruby files', () => {
      mockEditor({
        fsPath: '/workspace/my-app/config/database.yml',
        languageId: 'yaml',
      });

      provider = new ContextProvider();
      const ctx = provider.getActiveContext();

      expect(ctx.language).toBe('yaml');
    });

    it('omits selection when nothing is selected (empty selection)', () => {
      mockEditor({
        fsPath: '/workspace/my-app/app/models/user.rb',
        languageId: 'ruby',
        selectionStart: [5, 0],
        selectionEnd: [5, 0], // Same position = empty
      });

      provider = new ContextProvider();
      const ctx = provider.getActiveContext();

      expect(ctx.selection).toBeUndefined();
    });
  });

  // -----------------------------------------------------------------------
  // Selection extraction
  // -----------------------------------------------------------------------

  describe('selection extraction', () => {
    it('correctly converts 0-based VS Code lines to 1-based', () => {
      mockEditor({
        fsPath: '/workspace/my-app/app/controllers/users_controller.rb',
        languageId: 'ruby',
        selectionStart: [0, 0],
        selectionEnd: [2, 5],
        selectedText: 'class UsersController\n  def index\n  end',
      });

      provider = new ContextProvider();
      const ctx = provider.getActiveContext();

      expect(ctx.selection!.startLine).toBe(1);
      expect(ctx.selection!.endLine).toBe(3);
      expect(ctx.selection!.text).toContain('class UsersController');
    });
  });

  // -----------------------------------------------------------------------
  // Open files list
  // -----------------------------------------------------------------------

  describe('open files list', () => {
    it('returns relative paths for all open tab files', () => {
      (vscode.window.tabGroups as any).all = [
        {
          tabs: [
            { input: new TabInputText(Uri.file('/workspace/my-app/app/models/user.rb')) },
            { input: new TabInputText(Uri.file('/workspace/my-app/Gemfile')) },
            { input: { someOtherType: true } }, // non-text tab
          ],
        },
        {
          tabs: [
            { input: new TabInputText(Uri.file('/workspace/my-app/config/routes.rb')) },
          ],
        },
      ];

      provider = new ContextProvider();
      const ctx = provider.getActiveContext();

      expect(ctx.openFiles).toEqual([
        'app/models/user.rb',
        'Gemfile',
        'config/routes.rb',
      ]);
    });

    it('returns empty array when no tabs are open', () => {
      (vscode.window.tabGroups as any).all = [];

      provider = new ContextProvider();
      const ctx = provider.getActiveContext();

      expect(ctx.openFiles).toEqual([]);
    });
  });

  // -----------------------------------------------------------------------
  // Project context - Rails app
  // -----------------------------------------------------------------------

  describe('getProjectContext()', () => {
    it('detects Rails app with correct versions', async () => {
      const gemfileContent = `source "https://rubygems.org"\ngem 'rails', '~> 7.1'\ngem 'pg'`;
      const gemfileLock = `GEM\n  specs:\n    rails (7.1.3)\n    pg (1.5.4)`;
      const rubyVersion = '3.3.0';

      (vscode.workspace.fs.readFile as any).mockImplementation(async (uri: any) => {
        const path = uri.fsPath ?? uri.path;
        if (path.endsWith('/Gemfile')) return new TextEncoder().encode(gemfileContent);
        if (path.endsWith('/Gemfile.lock')) return new TextEncoder().encode(gemfileLock);
        if (path.endsWith('/.ruby-version')) return new TextEncoder().encode(rubyVersion);
        throw new Error('ENOENT');
      });

      (vscode.workspace.fs.stat as any).mockImplementation(async (uri: any) => {
        const path = uri.fsPath ?? uri.path;
        if (path.endsWith('/spec')) return { type: FileType.Directory };
        if (path.endsWith('/RUBYN.md')) return { type: FileType.File };
        throw new Error('ENOENT');
      });

      provider = new ContextProvider();
      const ctx = await provider.getProjectContext();

      expect(ctx.isRails).toBe(true);
      expect(ctx.railsVersion).toBe('7.1.3');
      expect(ctx.rubyVersion).toBe('3.3.0');
      expect(ctx.testFramework).toBe('rspec');
      expect(ctx.hasRubynMd).toBe(true);
    });

    it('detects non-Rails Ruby app', async () => {
      const gemfileContent = `source "https://rubygems.org"\ngem 'sinatra'\ngem 'rspec'`;
      const gemfileLock = `GEM\n  specs:\n    sinatra (4.0.0)`;

      (vscode.workspace.fs.readFile as any).mockImplementation(async (uri: any) => {
        const path = uri.fsPath ?? uri.path;
        if (path.endsWith('/Gemfile')) return new TextEncoder().encode(gemfileContent);
        if (path.endsWith('/Gemfile.lock')) return new TextEncoder().encode(gemfileLock);
        throw new Error('ENOENT');
      });

      (vscode.workspace.fs.stat as any).mockImplementation(async () => {
        throw new Error('ENOENT');
      });

      provider = new ContextProvider();
      const ctx = await provider.getProjectContext();

      expect(ctx.isRails).toBe(false);
      expect(ctx.railsVersion).toBeNull();
      expect(ctx.rubyVersion).toBeNull();
      expect(ctx.testFramework).toBe('rspec'); // rspec gem in Gemfile
    });

    it('detects RSpec via spec/ directory when not in Gemfile', async () => {
      const gemfileContent = `source "https://rubygems.org"\ngem 'rails'`;

      (vscode.workspace.fs.readFile as any).mockImplementation(async (uri: any) => {
        const path = uri.fsPath ?? uri.path;
        if (path.endsWith('/Gemfile')) return new TextEncoder().encode(gemfileContent);
        throw new Error('ENOENT');
      });

      (vscode.workspace.fs.stat as any).mockImplementation(async (uri: any) => {
        const path = uri.fsPath ?? uri.path;
        if (path.endsWith('/spec')) return { type: FileType.Directory };
        throw new Error('ENOENT');
      });

      provider = new ContextProvider();
      const ctx = await provider.getProjectContext();

      expect(ctx.testFramework).toBe('rspec');
    });

    it('detects Minitest via test/ directory when no spec/', async () => {
      const gemfileContent = `source "https://rubygems.org"\ngem 'rails'`;

      (vscode.workspace.fs.readFile as any).mockImplementation(async (uri: any) => {
        const path = uri.fsPath ?? uri.path;
        if (path.endsWith('/Gemfile')) return new TextEncoder().encode(gemfileContent);
        throw new Error('ENOENT');
      });

      (vscode.workspace.fs.stat as any).mockImplementation(async (uri: any) => {
        const path = uri.fsPath ?? uri.path;
        if (path.endsWith('/test')) return { type: FileType.Directory };
        throw new Error('ENOENT');
      });

      provider = new ContextProvider();
      const ctx = await provider.getProjectContext();

      expect(ctx.testFramework).toBe('minitest');
    });

    it('returns null testFramework when no spec/ or test/ exists', async () => {
      const gemfileContent = `source "https://rubygems.org"\ngem 'rails'`;

      (vscode.workspace.fs.readFile as any).mockImplementation(async (uri: any) => {
        const path = uri.fsPath ?? uri.path;
        if (path.endsWith('/Gemfile')) return new TextEncoder().encode(gemfileContent);
        throw new Error('ENOENT');
      });

      (vscode.workspace.fs.stat as any).mockImplementation(async () => {
        throw new Error('ENOENT');
      });

      provider = new ContextProvider();
      const ctx = await provider.getProjectContext();

      expect(ctx.testFramework).toBeNull();
    });

    it('returns safe defaults when no workspace folder exists', async () => {
      (vscode.workspace as any).workspaceFolders = undefined;

      provider = new ContextProvider();
      const ctx = await provider.getProjectContext();

      expect(ctx.isRails).toBe(false);
      expect(ctx.rubyVersion).toBeNull();
      expect(ctx.railsVersion).toBeNull();
      expect(ctx.testFramework).toBeNull();
      expect(ctx.hasRubynMd).toBe(false);
    });

    it('parses ruby version from .ruby-version stripping "ruby-" prefix', async () => {
      (vscode.workspace.fs.readFile as any).mockImplementation(async (uri: any) => {
        const path = uri.fsPath ?? uri.path;
        if (path.endsWith('/.ruby-version')) return new TextEncoder().encode('ruby-3.2.2\n');
        throw new Error('ENOENT');
      });

      (vscode.workspace.fs.stat as any).mockImplementation(async () => {
        throw new Error('ENOENT');
      });

      provider = new ContextProvider();
      const ctx = await provider.getProjectContext();

      expect(ctx.rubyVersion).toBe('3.2.2');
    });

    it('falls back to Gemfile for ruby version when no .ruby-version', async () => {
      const gemfileContent = `source "https://rubygems.org"\nruby '3.1.4'\ngem 'rails'`;

      (vscode.workspace.fs.readFile as any).mockImplementation(async (uri: any) => {
        const path = uri.fsPath ?? uri.path;
        if (path.endsWith('/Gemfile')) return new TextEncoder().encode(gemfileContent);
        throw new Error('ENOENT');
      });

      (vscode.workspace.fs.stat as any).mockImplementation(async () => {
        throw new Error('ENOENT');
      });

      provider = new ContextProvider();
      const ctx = await provider.getProjectContext();

      expect(ctx.rubyVersion).toBe('3.1.4');
    });
  });

  // -----------------------------------------------------------------------
  // Caching
  // -----------------------------------------------------------------------

  describe('caching', () => {
    it('returns cached result on second call without re-reading files', async () => {
      const readFileSpy = vscode.workspace.fs.readFile as any;
      readFileSpy.mockImplementation(async () => {
        throw new Error('ENOENT');
      });
      (vscode.workspace.fs.stat as any).mockImplementation(async () => {
        throw new Error('ENOENT');
      });

      provider = new ContextProvider();

      const ctx1 = await provider.getProjectContext();
      const callCount = readFileSpy.mock.calls.length;

      const ctx2 = await provider.getProjectContext();

      // readFile should not have been called again
      expect(readFileSpy.mock.calls.length).toBe(callCount);
      expect(ctx1).toBe(ctx2); // Same reference
    });

    it('invalidates cache when Gemfile changes', async () => {
      (vscode.workspace.fs.readFile as any).mockImplementation(async () => {
        throw new Error('ENOENT');
      });
      (vscode.workspace.fs.stat as any).mockImplementation(async () => {
        throw new Error('ENOENT');
      });

      provider = new ContextProvider();
      const ctx1 = await provider.getProjectContext();

      // Simulate a Gemfile change by firing the change event on the watcher
      const watchers = __getFileSystemWatchers();
      // The second watcher (index 1) is for Gemfile
      expect(watchers.length).toBeGreaterThanOrEqual(2);
      watchers[1]._changeEmitter.fire(Uri.file('/workspace/my-app/Gemfile'));

      const ctx2 = await provider.getProjectContext();

      // Should be a different reference (re-computed)
      expect(ctx2).not.toBe(ctx1);
    });
  });

  // -----------------------------------------------------------------------
  // RUBYN.md detection
  // -----------------------------------------------------------------------

  describe('RUBYN.md detection', () => {
    it('detects RUBYN.md file', async () => {
      (vscode.workspace.fs.readFile as any).mockImplementation(async () => {
        throw new Error('ENOENT');
      });

      (vscode.workspace.fs.stat as any).mockImplementation(async (uri: any) => {
        const path = uri.fsPath ?? uri.path;
        if (path.endsWith('/RUBYN.md')) return { type: FileType.File };
        throw new Error('ENOENT');
      });

      provider = new ContextProvider();
      const ctx = await provider.getProjectContext();

      expect(ctx.hasRubynMd).toBe(true);
    });

    it('detects .rubyn-code directory as alternative', async () => {
      (vscode.workspace.fs.readFile as any).mockImplementation(async () => {
        throw new Error('ENOENT');
      });

      (vscode.workspace.fs.stat as any).mockImplementation(async (uri: any) => {
        const path = uri.fsPath ?? uri.path;
        if (path.endsWith('/.rubyn-code')) return { type: FileType.Directory };
        throw new Error('ENOENT');
      });

      provider = new ContextProvider();
      const ctx = await provider.getProjectContext();

      expect(ctx.hasRubynMd).toBe(true);
    });
  });

  // -----------------------------------------------------------------------
  // enrichPrompt
  // -----------------------------------------------------------------------

  describe('enrichPrompt()', () => {
    it('prepends project and file context for enriched commands', async () => {
      mockEditor({
        fsPath: '/workspace/my-app/app/models/user.rb',
        languageId: 'ruby',
        selectionStart: [2, 0],
        selectionEnd: [5, 10],
        selectedText: 'def full_name\n  first + last\nend',
      });

      const gemfile = `gem 'rails'\ngem 'rspec-rails'`;
      const lock = `GEM\n  specs:\n    rails (7.1.3)`;

      (vscode.workspace.fs.readFile as any).mockImplementation(async (uri: any) => {
        const path = uri.fsPath ?? uri.path;
        if (path.endsWith('/Gemfile')) return new TextEncoder().encode(gemfile);
        if (path.endsWith('/Gemfile.lock')) return new TextEncoder().encode(lock);
        if (path.endsWith('/.ruby-version')) return new TextEncoder().encode('3.3.0');
        throw new Error('ENOENT');
      });

      (vscode.workspace.fs.stat as any).mockImplementation(async () => {
        throw new Error('ENOENT');
      });

      provider = new ContextProvider();
      const result = await provider.enrichPrompt('refactorSelection', 'Make it better');

      expect(result.prompt).toContain('[Project]');
      expect(result.prompt).toContain('Rails');
      expect(result.prompt).toContain('7.1.3');
      expect(result.prompt).toContain('Ruby 3.3.0');
      expect(result.prompt).toContain('rspec');
      expect(result.prompt).toContain('[File] app/models/user.rb');
      expect(result.prompt).toContain('[Selection]');
      expect(result.prompt).toContain('Make it better');
      expect(result.project).not.toBeNull();
      expect(result.project!.isRails).toBe(true);
    });

    it('skips project context for non-enriched commands', async () => {
      mockEditor({
        fsPath: '/workspace/my-app/app/models/user.rb',
        languageId: 'ruby',
      });

      provider = new ContextProvider();
      const result = await provider.enrichPrompt('someOtherCommand', 'Do something');

      expect(result.project).toBeNull();
      expect(result.prompt).not.toContain('[Project]');
      expect(result.prompt).toContain('Do something');
    });

    it('includes file context even without project enrichment', async () => {
      mockEditor({
        fsPath: '/workspace/my-app/app/models/user.rb',
        languageId: 'ruby',
      });

      provider = new ContextProvider();
      const result = await provider.enrichPrompt('randomCommand', 'Hello');

      expect(result.prompt).toContain('[File] app/models/user.rb');
      expect(result.prompt).toContain('Hello');
    });
  });

  // -----------------------------------------------------------------------
  // Dispose
  // -----------------------------------------------------------------------

  describe('dispose()', () => {
    it('disposes all file watchers', () => {
      provider = new ContextProvider();
      const watchers = __getFileSystemWatchers();
      expect(watchers.length).toBe(3); // Gemfile.lock, Gemfile, .ruby-version

      provider.dispose();

      for (const watcher of watchers) {
        expect(watcher.dispose).toHaveBeenCalled();
      }
    });
  });
});
