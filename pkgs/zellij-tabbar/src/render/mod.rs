//! Tabbar-specific template data, actions, and button styling.

use ansi_term::ANSIStrings;
use chrono::Local;
use serde::Serialize;
use zellij_template_render::{
    context, error_frame as render_error_frame, ActionRegistry, ButtonPresentation, ButtonView,
    Error, ErrorKind, Frame, Renderer, Value, Viewport,
};
use zellij_tile::prelude::*;
use zellij_tile_utils::style;

/// Built-in template used when plugin configuration provides no override.
const DEFAULT_TEMPLATE: &str = r#"{%- call Flex(direction="row") -%}
{%- call Flex(shrink=0) -%}{{ session.name }} {% endcall -%}
{%- call Flex(direction="row", grow=1, shrink=1, overflow="scroll") -%}
{%- for tab in session.tabs -%}
{%- call Button(on_click=actions.switch_tab(tab.index), focused=tab.active) -%}{{ tab.name }}{%- endcall -%}
{%- endfor -%}
{%- endcall -%}
{%- call Button(on_click=actions.new_tab()) -%}+{%- endcall -%}
{%- endcall -%}"#;

/// Typed operation attached to cells rendered by `Button`.
#[derive(Clone, Debug, PartialEq, Eq)]
pub(crate) enum ClickAction {
    SwitchTab(usize),
    NewTab,
}

pub(crate) type RenderedFrame = Frame<ClickAction>;

#[derive(Serialize)]
struct TemplateSession<'a> {
    name: &'a str,
    tabs: Vec<TemplateTab<'a>>,
}

#[derive(Serialize)]
struct TemplateTab<'a> {
    name: &'a str,
    index: usize,
    active: bool,
}

#[derive(Serialize)]
struct TemplateTheme {
    text: String,
    background: String,
    active_text: String,
    active_background: String,
    muted_text: String,
    muted_background: String,
    alert: String,
}

/// Chooses configured template, falling back to the built-in template.
pub(crate) fn selected_template(override_template: Option<&str>) -> &str {
    override_template.unwrap_or(DEFAULT_TEMPLATE)
}

/// Renders tabbar data through the shared template renderer.
pub(crate) fn render(
    template: &str,
    session_name: Option<&str>,
    tabs: &[TabInfo],
    rows: usize,
    cols: usize,
    colors: Styling,
    capabilities: PluginCapabilities,
) -> Result<RenderedFrame, Error> {
    let actions = ActionRegistry::new()
        .with("switch_tab", |args| {
            let index = args.first().and_then(Value::as_usize).ok_or_else(|| {
                Error::new(
                    ErrorKind::InvalidOperation,
                    "switch_tab expects an integer index",
                )
            })?;
            Ok(ClickAction::SwitchTab(index))
        })
        .with("new_tab", |args| {
            if !args.is_empty() {
                return Err(Error::new(
                    ErrorKind::InvalidOperation,
                    "new_tab expects no arguments",
                ));
            }
            Ok(ClickAction::NewTab)
        });
    let model = TemplateSession {
        name: session_name.unwrap_or_default(),
        tabs: tabs
            .iter()
            .map(|tab| TemplateTab {
                name: &tab.name,
                index: tab.position + 1,
                active: tab.active,
            })
            .collect(),
    };
    let theme = TemplateTheme {
        text: color_token(colors.text_unselected.base),
        background: color_token(colors.text_unselected.background),
        active_text: color_token(colors.ribbon_selected.base),
        active_background: color_token(colors.ribbon_selected.background),
        muted_text: color_token(colors.ribbon_unselected.base),
        muted_background: color_token(colors.ribbon_unselected.background),
        alert: color_token(colors.ribbon_unselected.emphasis_3),
    };
    let tabs = tabs.to_vec();
    Renderer::new(actions).render(
        template,
        context! {
            session => model,
            system => context! { time => Local::now().timestamp() },
            context => context! { theme => theme },
        },
        Viewport { rows, cols },
        move |button| present_button(button, &tabs, colors, capabilities),
    )
}

pub(crate) fn error_frame(error: &Error, rows: usize, cols: usize) -> RenderedFrame {
    render_error_frame(error, Viewport { rows, cols })
}

fn present_button(
    button: ButtonView<'_, ClickAction>,
    tabs: &[TabInfo],
    colors: Styling,
    capabilities: PluginCapabilities,
) -> Result<ButtonPresentation, Error> {
    let focused = button.focused.unwrap_or_else(|| match button.action {
        ClickAction::SwitchTab(index) => tabs
            .iter()
            .any(|tab| tab.active && tab.position + 1 == *index),
        ClickAction::NewTab => false,
    });
    Ok(ButtonPresentation {
        label: style_button(
            button.label,
            button.action,
            focused,
            tabs,
            colors,
            capabilities,
        )?,
        focused,
    })
}

fn style_button(
    label: &str,
    action: &ClickAction,
    focused: bool,
    tabs: &[TabInfo],
    palette: Styling,
    capabilities: PluginCapabilities,
) -> Result<String, Error> {
    let separator = if capabilities.arrow_fonts { "" } else { "" };
    let label = match action {
        ClickAction::SwitchTab(index) => {
            let tab = find_tab(tabs, *index)?;
            let mut label = label.to_string();
            if tab.is_fullscreen_active {
                label.push_str(" (FULLSCREEN)");
            } else if tab.is_sync_panes_active {
                label.push_str(" (SYNC)");
            }
            if tab.has_bell_notification || tab.is_flashing_bell {
                label.push_str(" [!]");
            }
            label
        },
        ClickAction::NewTab => label.to_string(),
    };
    let alternate = match action {
        ClickAction::SwitchTab(index) => index % 2 == 0 && capabilities.arrow_fonts,
        ClickAction::NewTab => tabs.len() % 2 == 1 && capabilities.arrow_fonts,
    };
    let background = if focused {
        palette.ribbon_selected.background
    } else if alternate {
        palette.ribbon_unselected.emphasis_1
    } else {
        palette.ribbon_unselected.background
    };
    let foreground = match action {
        ClickAction::SwitchTab(index) => {
            let tab = find_tab(tabs, *index)?;
            if tab.is_flashing_bell || tab.has_bell_notification {
                if focused {
                    palette.ribbon_selected.emphasis_3
                } else {
                    palette.ribbon_unselected.emphasis_3
                }
            } else if focused {
                palette.ribbon_selected.base
            } else {
                palette.ribbon_unselected.base
            }
        },
        ClickAction::NewTab => palette.ribbon_unselected.base,
    };
    let fill = palette.text_unselected.background;
    let left = style!(fill, background).paint(separator);
    let text = style!(foreground, background)
        .bold()
        .paint(format!(" {} ", label));
    let right = style!(background, fill).paint(separator);
    Ok(ANSIStrings(&[left, text, right]).to_string())
}

fn find_tab(tabs: &[TabInfo], index: usize) -> Result<&TabInfo, Error> {
    tabs.iter()
        .find(|tab| tab.position + 1 == index)
        .ok_or_else(|| {
            Error::new(
                ErrorKind::InvalidOperation,
                "switch_tab index does not exist",
            )
        })
}

fn color_token(color: PaletteColor) -> String {
    match color {
        PaletteColor::Rgb((r, g, b)) => format!("rgb:{r},{g},{b}"),
        PaletteColor::EightBit(index) => format!("index:{index}"),
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    fn plain_text(value: &str) -> String {
        let mut output = String::new();
        let mut chars = value.chars().peekable();
        while let Some(ch) = chars.next() {
            if ch == '\u{1b}' {
                consume_ansi(&mut chars);
            } else {
                output.push(ch);
            }
        }
        output
    }

    fn consume_ansi(chars: &mut std::iter::Peekable<std::str::Chars<'_>>) {
        match chars.next() {
            Some('[') => {
                for ch in chars.by_ref() {
                    if ('@'..='~').contains(&ch) {
                        break;
                    }
                }
            },
            Some(']') => {
                while let Some(ch) = chars.next() {
                    if ch == '\u{7}' {
                        break;
                    }
                    if ch == '\u{1b}' && chars.peek() == Some(&'\\') {
                        chars.next();
                        break;
                    }
                }
            },
            _ => {},
        }
    }

    #[test]
    fn default_and_custom_template_selection() {
        assert_eq!(selected_template(None), DEFAULT_TEMPLATE);
        assert_eq!(selected_template(Some("custom")), "custom");
    }

    #[test]
    fn default_template_renders_buttons_and_actions() {
        let mut first = TabInfo {
            name: "one".into(),
            active: true,
            ..TabInfo::default()
        };
        first.position = 0;
        let second = TabInfo {
            name: "two".into(),
            position: 1,
            ..TabInfo::default()
        };
        let mode = ModeInfo::default();
        let frame = render(
            DEFAULT_TEMPLATE,
            Some("demo"),
            &[first, second],
            1,
            80,
            mode.style.colors,
            PluginCapabilities { arrow_fonts: false },
        )
        .unwrap();
        assert!(plain_text(&frame.lines[0]).contains("one"));
        assert!(frame.hitboxes[0]
            .iter()
            .any(|action| action == &Some(ClickAction::SwitchTab(1))));
        assert!(frame.hitboxes[0]
            .iter()
            .any(|action| action == &Some(ClickAction::NewTab)));
    }

    #[test]
    fn missing_explicit_focus_still_follows_active_tab() {
        let tab = TabInfo {
            name: "one".into(),
            active: true,
            ..TabInfo::default()
        };
        let mode = ModeInfo::default();
        let frame = render(
            r#"{% call Flex(overflow="scroll") %}{% call Button(on_click=actions.switch_tab(1)) %}one{% endcall %}{% endcall %}"#,
            None,
            &[tab],
            1,
            3,
            mode.style.colors,
            PluginCapabilities { arrow_fonts: true },
        )
        .unwrap();
        assert!(frame.hitboxes[0]
            .iter()
            .any(|action| action == &Some(ClickAction::SwitchTab(1))));
    }
}
