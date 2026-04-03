# Auth Layer

OAuth PKCE flow + token storage with fallback chain.

## Classes

- **`OAuth`** — Full OAuth PKCE flow. Generates code verifier/challenge, opens browser for
  authorization, exchanges code for tokens. Custom errors: `StateMismatchError`,
  `TokenExchangeError`, `RefreshError`.

- **`Server`** — Local WEBrick server on `127.0.0.1:19275` to receive the OAuth callback.
  Uses mutex + condition variable to block until the redirect arrives. Times out after 120s.

- **`TokenStore`** — Token persistence with a three-level fallback chain:
  1. macOS Keychain (reads Claude Code's OAuth token from `Claude Code-credentials`)
  2. Local YAML file (`~/.rubyn-code/tokens.yml`)
  3. `ANTHROPIC_API_KEY` environment variable

  Handles token refresh with a 5-minute expiry buffer.
