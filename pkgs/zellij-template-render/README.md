# zellij-template-render

Reusable MiniJinja terminal renderer for Zellij plugins.

The crate provides:

- nested `Flex` row and column layouts
- typed `Button` actions and two-dimensional click hitboxes
- focus-following overflow
- ANSI-aware measurement and clipping
- `bold`, `dim`, `fg`, `bg`, and time-format filters

Plugins own template data, action semantics, and button presentation. The renderer does not depend on `zellij-tile`.

```rust
use zellij_template_render::{
    context, ActionRegistry, ButtonPresentation, Renderer, Value, Viewport,
};

#[derive(Clone, Debug, PartialEq, Eq)]
enum Action {
    Select(usize),
}

let actions = ActionRegistry::new().with("select", |args| {
    let index = args.first().and_then(Value::as_usize).unwrap();
    Ok(Action::Select(index))
});
let frame = Renderer::new(actions).render(
    r#"{% call Button(on_click=actions.select(2)) %}two{% endcall %}"#,
    context! {},
    Viewport { rows: 1, cols: 10 },
    |button| Ok(ButtonPresentation {
        label: button.label.to_string(),
        focused: button.focused.unwrap_or(false),
    }),
)?;
# Ok::<(), zellij_template_render::Error>(())
```

`Button` only accepts values returned by registered functions under `actions`. Action decoder results become typed values in `Frame::hitboxes`.
