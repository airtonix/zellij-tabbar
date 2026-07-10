# zellij-tabbar

Single-crate Rust/WASM Zellij tab bar plugin.

Optional `template` plugin configuration replaces the built-in tab bar layout:

```kdl
plugin location="file:/path/to/zellij-tabbar.wasm" {
    template r#"{% call Stack() -%}
{% call Flex(justify="start") %}{{ session.name }} {% for tab in session.tabs %}{% call Tab(index=tab.index, label=tab.name) %}{% endcall %}{% endfor %}{% endcall %}
{% call Flex(justify="end") %}{{ system.time | format("HH:MM") }}{% endcall %}
{%- endcall %}"#
}
```

Template data:

- `session.name`
- `session.tabs`: `name`, one-based `index`, and `active`
- `system.time`: current local timestamp; `format` accepts `YYYY`, `YY`, `HH`, `MM`, and `SS`
- `Tab(index=..., label=...)`: renders existing tab styling and click target
- `Flex(justify="start|center|end")` inside `Stack()`: overlays content on one row

No `template` setting keeps existing renderer unchanged.

```bash
moon run repo:build
moon run repo:check
moon run repo:test
moon run repo:e2e # requires bats, python3, and Zellij 0.45.x
```

Publish the built WASM to an existing GitHub release:

```bash
PUBLISH_TAG=v0.1.0 moon run repo:publish
```

`gh` uses the current repository. Set `GITHUB_REPOSITORY=owner/repo` when no Git remote is available.
