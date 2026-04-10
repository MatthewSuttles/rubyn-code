/**
 * Comprehensive mock of the `vscode` module for unit tests.
 *
 * This file is resolved in place of the real `vscode` module via the
 * vitest alias configured in vitest.config.ts.
 */

import { vi } from 'vitest';

// ---------------------------------------------------------------------------
// Core value types
// ---------------------------------------------------------------------------

export enum StatusBarAlignment {
  Left = 1,
  Right = 2,
}

export enum ViewColumn {
  Active = -1,
  Beside = -2,
  One = 1,
  Two = 2,
  Three = 3,
}

export enum FileType {
  Unknown = 0,
  File = 1,
  Directory = 2,
  SymbolicLink = 64,
}

// ---------------------------------------------------------------------------
// Uri
// ---------------------------------------------------------------------------

export class Uri {
  readonly scheme: string;
  readonly authority: string;
  readonly path: string;
  readonly query: string;
  readonly fragment: string;
  readonly fsPath: string;

  private constructor(
    scheme: string,
    authority: string,
    path: string,
    query = '',
    fragment = '',
  ) {
    this.scheme = scheme;
    this.authority = authority;
    this.path = path;
    this.query = query;
    this.fragment = fragment;
    this.fsPath = path;
  }

  static file(path: string): Uri {
    return new Uri('file', '', path);
  }

  static parse(value: string): Uri {
    try {
      const url = new URL(value);
      return new Uri(
        url.protocol.replace(':', ''),
        url.hostname,
        decodeURIComponent(url.pathname),
        url.search,
        url.hash,
      );
    } catch {
      return new Uri('unknown', '', value);
    }
  }

  static joinPath(base: Uri, ...pathSegments: string[]): Uri {
    const joined = [base.path, ...pathSegments].join('/').replace(/\/+/g, '/');
    return new Uri(base.scheme, base.authority, joined);
  }

  toString(): string {
    if (this.scheme === 'file') {
      return `file://${this.path}`;
    }
    return `${this.scheme}://${this.authority}${this.path}${this.query}${this.fragment}`;
  }

  with(change: { scheme?: string; authority?: string; path?: string }): Uri {
    return new Uri(
      change.scheme ?? this.scheme,
      change.authority ?? this.authority,
      change.path ?? this.path,
      this.query,
      this.fragment,
    );
  }
}

// ---------------------------------------------------------------------------
// EventEmitter
// ---------------------------------------------------------------------------

export class EventEmitter<T = void> {
  private handlers: Array<(e: T) => void> = [];

  readonly event = (handler: (e: T) => void): Disposable => {
    this.handlers.push(handler);
    return new Disposable(() => {
      this.handlers = this.handlers.filter((h) => h !== handler);
    });
  };

  fire(data: T): void {
    for (const h of this.handlers) {
      h(data);
    }
  }

  dispose(): void {
    this.handlers = [];
  }
}

// ---------------------------------------------------------------------------
// Disposable
// ---------------------------------------------------------------------------

export class Disposable {
  private disposeCallback: () => void;

  constructor(callOnDispose: () => void) {
    this.disposeCallback = callOnDispose;
  }

  dispose(): void {
    this.disposeCallback();
  }

  static from(...disposables: Array<{ dispose: () => void }>): Disposable {
    return new Disposable(() => {
      for (const d of disposables) {
        d.dispose();
      }
    });
  }
}

// ---------------------------------------------------------------------------
// Range / Position / Selection
// ---------------------------------------------------------------------------

export class Position {
  constructor(
    public readonly line: number,
    public readonly character: number,
  ) {}
}

export class Range {
  readonly start: Position;
  readonly end: Position;

  constructor(startLine: number, startChar: number, endLine: number, endChar: number);
  constructor(start: Position, end: Position);
  constructor(
    startOrPos: number | Position,
    startCharOrEnd: number | Position,
    endLine?: number,
    endChar?: number,
  ) {
    if (typeof startOrPos === 'number') {
      this.start = new Position(startOrPos, startCharOrEnd as number);
      this.end = new Position(endLine!, endChar!);
    } else {
      this.start = startOrPos;
      this.end = startCharOrEnd as Position;
    }
  }

  get isEmpty(): boolean {
    return this.start.line === this.end.line && this.start.character === this.end.character;
  }
}

export class Selection extends Range {
  readonly anchor: Position;
  readonly active: Position;
  readonly isReversed: boolean;

  constructor(anchorLine: number, anchorChar: number, activeLine: number, activeChar: number);
  constructor(anchor: Position, active: Position);
  constructor(
    anchorOrLine: number | Position,
    anchorCharOrActive: number | Position,
    activeLine?: number,
    activeChar?: number,
  ) {
    if (typeof anchorOrLine === 'number') {
      super(anchorOrLine, anchorCharOrActive as number, activeLine!, activeChar!);
      this.anchor = new Position(anchorOrLine, anchorCharOrActive as number);
      this.active = new Position(activeLine!, activeChar!);
    } else {
      super(anchorOrLine, anchorCharOrActive as Position);
      this.anchor = anchorOrLine;
      this.active = anchorCharOrActive as Position;
    }
    this.isReversed = false;
  }
}

// ---------------------------------------------------------------------------
// WorkspaceEdit
// ---------------------------------------------------------------------------

export class WorkspaceEdit {
  private edits: Array<{ uri: Uri; range: Range; newText: string }> = [];

  replace(uri: Uri, range: Range, newText: string): void {
    this.edits.push({ uri, range, newText });
  }

  insert(uri: Uri, position: Position, newText: string): void {
    this.edits.push({ uri, range: new Range(position, position), newText });
  }

  delete(uri: Uri, range: Range): void {
    this.edits.push({ uri, range, newText: '' });
  }

  getEdits(): Array<{ uri: Uri; range: Range; newText: string }> {
    return this.edits;
  }
}

// ---------------------------------------------------------------------------
// TabInputText / TabInputTextDiff
// ---------------------------------------------------------------------------

export class TabInputText {
  constructor(public readonly uri: Uri) {}
}

export class TabInputTextDiff {
  constructor(
    public readonly original: Uri,
    public readonly modified: Uri,
  ) {}
}

// ---------------------------------------------------------------------------
// CancellationToken
// ---------------------------------------------------------------------------

export class CancellationTokenSource {
  token = {
    isCancellationRequested: false,
    onCancellationRequested: vi.fn(),
  };

  cancel(): void {
    this.token.isCancellationRequested = true;
  }

  dispose(): void {}
}

// ---------------------------------------------------------------------------
// MarkdownString
// ---------------------------------------------------------------------------

export class MarkdownString {
  value: string;
  isTrusted = false;

  constructor(value = '', _supportThemeIcons = false) {
    this.value = value;
  }

  appendMarkdown(value: string): this {
    this.value += value;
    return this;
  }

  appendText(value: string): this {
    this.value += value;
    return this;
  }
}

// ---------------------------------------------------------------------------
// Mock status bar item
// ---------------------------------------------------------------------------

function createMockStatusBarItem(): any {
  return {
    text: '',
    tooltip: undefined as string | MarkdownString | undefined,
    command: undefined as string | undefined,
    backgroundColor: undefined,
    alignment: StatusBarAlignment.Left,
    priority: 0,
    show: vi.fn(),
    hide: vi.fn(),
    dispose: vi.fn(),
  };
}

// ---------------------------------------------------------------------------
// Mock output channel
// ---------------------------------------------------------------------------

function createMockOutputChannel(name: string): any {
  return {
    name,
    append: vi.fn(),
    appendLine: vi.fn(),
    clear: vi.fn(),
    show: vi.fn(),
    hide: vi.fn(),
    dispose: vi.fn(),
    replace: vi.fn(),
  };
}

// ---------------------------------------------------------------------------
// Mock file system watcher
// ---------------------------------------------------------------------------

function createMockFileSystemWatcher(): any {
  const changeEmitter = new EventEmitter<Uri>();
  const createEmitter = new EventEmitter<Uri>();
  const deleteEmitter = new EventEmitter<Uri>();

  return {
    onDidChange: changeEmitter.event,
    onDidCreate: createEmitter.event,
    onDidDelete: deleteEmitter.event,
    _changeEmitter: changeEmitter,
    _createEmitter: createEmitter,
    _deleteEmitter: deleteEmitter,
    dispose: vi.fn(),
  };
}

// ---------------------------------------------------------------------------
// Configuration mock
// ---------------------------------------------------------------------------

const configStore: Record<string, Record<string, unknown>> = {};

export function __setConfig(section: string, values: Record<string, unknown>): void {
  configStore[section] = { ...values };
}

export function __resetConfig(): void {
  for (const key of Object.keys(configStore)) {
    delete configStore[key];
  }
}

function getConfiguration(section?: string) {
  const store = section ? configStore[section] ?? {} : {};
  return {
    get: vi.fn(<T>(key: string, defaultValue?: T): T => {
      const val = store[key];
      return val !== undefined ? (val as T) : defaultValue!;
    }),
    has: vi.fn((key: string) => key in store),
    inspect: vi.fn(),
    update: vi.fn(),
  };
}

// ---------------------------------------------------------------------------
// Registered commands storage
// ---------------------------------------------------------------------------

const registeredCommands = new Map<string, (...args: unknown[]) => unknown>();

// ---------------------------------------------------------------------------
// window
// ---------------------------------------------------------------------------

export const window = {
  createStatusBarItem: vi.fn((_alignment?: StatusBarAlignment, _priority?: number) => {
    return createMockStatusBarItem();
  }),
  showInformationMessage: vi.fn(async (..._args: unknown[]) => undefined as string | undefined),
  showWarningMessage: vi.fn(async (..._args: unknown[]) => undefined as string | undefined),
  showErrorMessage: vi.fn(async (..._args: unknown[]) => undefined as string | undefined),
  showInputBox: vi.fn(async (..._args: unknown[]) => undefined as string | undefined),
  createOutputChannel: vi.fn((name: string) => createMockOutputChannel(name)),
  showTextDocument: vi.fn(async () => undefined),
  activeTextEditor: undefined as any,
  visibleTextEditors: [] as any[],
  tabGroups: {
    all: [] as any[],
    close: vi.fn(async () => true),
  },
};

// ---------------------------------------------------------------------------
// workspace
// ---------------------------------------------------------------------------

const fileSystemWatchers: any[] = [];

export const workspace = {
  getConfiguration: vi.fn(getConfiguration),
  workspaceFolders: undefined as
    | Array<{ uri: Uri; name: string; index: number }>
    | undefined,
  fs: {
    readFile: vi.fn(async (_uri: Uri): Promise<Uint8Array> => new Uint8Array()),
    writeFile: vi.fn(async (_uri: Uri, _content: Uint8Array) => {}),
    stat: vi.fn(async (_uri: Uri) => ({ type: FileType.File, ctime: 0, mtime: 0, size: 0 })),
    delete: vi.fn(async (_uri: Uri) => {}),
    createDirectory: vi.fn(async (_uri: Uri) => {}),
  },
  applyEdit: vi.fn(async (_edit: WorkspaceEdit) => true),
  openTextDocument: vi.fn(async (uri: Uri | string) => ({
    uri: typeof uri === 'string' ? Uri.file(uri) : uri,
    getText: vi.fn(() => ''),
    positionAt: vi.fn((offset: number) => new Position(0, offset)),
    languageId: 'ruby',
    lineCount: 1,
    save: vi.fn(async () => true),
  })),
  createFileSystemWatcher: vi.fn((_pattern: string) => {
    const watcher = createMockFileSystemWatcher();
    fileSystemWatchers.push(watcher);
    return watcher;
  }),
  registerTextDocumentContentProvider: vi.fn((_scheme: string, _provider: any) => {
    return new Disposable(() => {});
  }),
  onDidChangeConfiguration: vi.fn((_handler: any) => new Disposable(() => {})),
};

// ---------------------------------------------------------------------------
// commands
// ---------------------------------------------------------------------------

export const commands = {
  registerCommand: vi.fn((command: string, callback: (...args: unknown[]) => unknown) => {
    registeredCommands.set(command, callback);
    return new Disposable(() => {
      registeredCommands.delete(command);
    });
  }),
  executeCommand: vi.fn(async (command: string, ...args: unknown[]) => {
    const handler = registeredCommands.get(command);
    if (handler) {
      return handler(...args);
    }
    return undefined;
  }),
};

// ---------------------------------------------------------------------------
// extensions
// ---------------------------------------------------------------------------

export const extensions = {
  getExtension: vi.fn((_id: string) => ({
    packageJSON: { version: '0.1.0' },
  })),
};

// ---------------------------------------------------------------------------
// Helpers for test setup / teardown
// ---------------------------------------------------------------------------

export function __getFileSystemWatchers(): any[] {
  return fileSystemWatchers;
}

export function __getRegisteredCommands(): Map<string, (...args: unknown[]) => unknown> {
  return registeredCommands;
}

export function __resetAll(): void {
  window.activeTextEditor = undefined;
  window.visibleTextEditors = [];
  window.tabGroups.all = [];
  workspace.workspaceFolders = undefined;
  fileSystemWatchers.length = 0;
  registeredCommands.clear();
  __resetConfig();

  // Reset all mock call state
  vi.clearAllMocks();
}
