# Rubyn Code VS Code Extension

The VS Code extension lives in its own repository:

**https://github.com/MatthewSuttles/rubyn-code-vscode**

See the [extension README](https://github.com/MatthewSuttles/rubyn-code-vscode#readme) for installation, features, and configuration.

See the [full documentation](https://github.com/MatthewSuttles/rubyn-code-vscode/blob/main/docs/vscode-extension.md) for detailed setup, troubleshooting, and development guide.

## IDE Server (this repo)

The Ruby-side IDE server that the extension communicates with lives in this repo:

- `lib/rubyn_code/ide/server.rb` — JSON-RPC 2.0 server over stdio
- `lib/rubyn_code/ide/protocol.rb` — Message parsing, validation, serialization
- `lib/rubyn_code/ide/handlers/` — Request handlers (initialize, prompt, cancel, review, etc.)
- `lib/rubyn_code/ide/adapters/tool_output.rb` — Tool execution adapter for approval flows

Start the IDE server with:

```bash
rubyn-code --ide
```

The extension spawns this process automatically.
