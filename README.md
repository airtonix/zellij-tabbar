# zellij-tabbar

Single-crate Rust/WASM Zellij plugin copied from `zellij-agent-threads`.

```bash
moon run repo:build
moon run repo:check
moon run repo:test
```

Publish the built WASM to an existing GitHub release:

```bash
PUBLISH_TAG=v0.1.0 moon run repo:publish
```

`gh` uses the current repository. Set `GITHUB_REPOSITORY=owner/repo` when no Git remote is available.
