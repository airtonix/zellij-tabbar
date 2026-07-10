use chrono::{Local, TimeZone};
use minijinja::value::Kwargs;
use minijinja::{context, Environment, Error, ErrorKind, State as TemplateState, Value};
use serde::Serialize;
use unicode_width::UnicodeWidthStr;
use zellij_tile::prelude::*;

use crate::tab::tab_style;
use crate::LinePart;

const MARKER_END: &str = "\u{E001}";
const TAB_START: &str = "\u{E000}T";
const TAB_END: &str = "\u{E000}E";
const FLEX_START: &str = "\u{E000}F";

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

pub(crate) fn render(
    template: &str,
    session_name: Option<&str>,
    tabs: &[TabInfo],
    cols: usize,
    hovered_tab_idx: Option<usize>,
    colors: Styling,
    capabilities: PluginCapabilities,
) -> Result<Vec<LinePart>, Error> {
    let mut env = Environment::new();
    env.add_global("viewport_cols", cols);
    env.add_filter("format", format_time);
    env.add_function("Stack", stack);
    env.add_function("Flex", flex);
    let tab_infos = tabs.to_vec();
    env.add_function(
        "Tab",
        move |state: &TemplateState<'_, '_>, kwargs: Kwargs| {
            tab(
                state,
                kwargs,
                &tab_infos,
                hovered_tab_idx,
                colors,
                capabilities,
            )
        },
    );

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
    let rendered = env.render_str(
        template,
        context! {
            session => model,
            system => context! { time => Local::now().timestamp() },
        },
    )?;
    Ok(collect_parts(&rendered))
}

fn tab(
    state: &TemplateState<'_, '_>,
    kwargs: Kwargs,
    tabs: &[TabInfo],
    hovered_tab_idx: Option<usize>,
    colors: Styling,
    capabilities: PluginCapabilities,
) -> Result<String, Error> {
    let index: usize = kwargs.get("index")?;
    let label = kwargs.get::<Option<String>>("label")?;
    let caller = kwargs.get::<Option<Value>>("caller")?;
    kwargs.assert_all_used()?;
    let label = match (label, caller) {
        (Some(label), _) => label,
        (None, Some(caller)) => state.format(caller.call(state, &[])?)?,
        (None, None) => {
            return Err(Error::new(
                ErrorKind::MissingArgument,
                "Tab expects label or caller body",
            ))
        },
    };
    let info = tabs
        .iter()
        .find(|tab| tab.position + 1 == index)
        .ok_or_else(|| Error::new(ErrorKind::InvalidOperation, "Tab index does not exist"))?;
    let part = tab_style(
        label,
        info,
        info.position % 2 == 1,
        hovered_tab_idx == Some(index),
        colors,
        capabilities,
    );
    Ok(format!(
        "{TAB_START}{index}{MARKER_END}{}{TAB_END}{index}{MARKER_END}",
        part.part
    ))
}

fn format_time(timestamp: i64, pattern: String) -> Result<String, Error> {
    let time = Local
        .timestamp_opt(timestamp, 0)
        .single()
        .ok_or_else(|| Error::new(ErrorKind::InvalidOperation, "invalid system time"))?;
    let pattern = pattern
        .replace("YYYY", "%Y")
        .replace("YY", "%y")
        .replace("HH", "%H")
        .replace("MM", "%M")
        .replace("SS", "%S");
    Ok(time.format(&pattern).to_string())
}

fn flex(state: &TemplateState<'_, '_>, kwargs: Kwargs) -> Result<String, Error> {
    let justify = kwargs
        .get::<Option<String>>("justify")?
        .unwrap_or_else(|| "start".into());
    let caller: Value = kwargs.get("caller")?;
    kwargs.assert_all_used()?;
    let body = state.format(caller.call(state, &[])?)?;
    match justify.as_str() {
        "start" | "center" | "end" => Ok(format!("{FLEX_START}{justify}{MARKER_END}{body}")),
        _ => Err(Error::new(
            ErrorKind::InvalidOperation,
            "Flex justify must be start, center, or end",
        )),
    }
}

fn stack(state: &TemplateState<'_, '_>, kwargs: Kwargs) -> Result<String, Error> {
    let caller: Value = kwargs.get("caller")?;
    kwargs.assert_all_used()?;
    let body = state.format(caller.call(state, &[])?)?;
    let cols = state
        .lookup("viewport_cols")
        .and_then(|v| v.as_usize())
        .unwrap_or(0);
    let mut output = String::new();
    for layer in body
        .split(FLEX_START)
        .filter(|layer| !layer.trim().is_empty())
    {
        let Some((justify, content)) = layer.split_once(MARKER_END) else {
            continue;
        };
        let content = content.trim_matches('\n');
        let width = visible_width(content);
        let padding = match justify {
            "center" => cols.saturating_sub(width) / 2,
            "end" => cols.saturating_sub(width),
            _ => 0,
        };
        if output.is_empty() {
            output = " ".repeat(padding);
            output.push_str(content);
        } else {
            let current = visible_width(&output);
            if padding >= current {
                output.push_str(&" ".repeat(padding - current));
                output.push_str(content);
            }
        }
    }
    Ok(output)
}

fn collect_parts(rendered: &str) -> Vec<LinePart> {
    let mut parts = Vec::new();
    let mut plain = String::new();
    let mut i = 0;
    while i < rendered.len() {
        let rest = &rendered[i..];
        if let Some((index, consumed)) = parse_marker(rest, TAB_START) {
            push_plain(&mut parts, &mut plain);
            i += consumed;
            let end_marker = format!("{TAB_END}{index}{MARKER_END}");
            if let Some(end) = rendered[i..].find(&end_marker) {
                let part = rendered[i..i + end].to_string();
                parts.push(LinePart {
                    len: visible_width(&part),
                    part,
                    tab_index: Some(index),
                });
                i += end + end_marker.len();
                continue;
            }
        }
        let ch = rest.chars().next().unwrap();
        plain.push(ch);
        i += ch.len_utf8();
    }
    push_plain(&mut parts, &mut plain);
    parts
}

fn push_plain(parts: &mut Vec<LinePart>, plain: &mut String) {
    if !plain.is_empty() {
        parts.push(LinePart {
            len: visible_width(plain),
            part: std::mem::take(plain),
            tab_index: None,
        });
    }
}

fn parse_marker(input: &str, prefix: &str) -> Option<(usize, usize)> {
    let rest = input.strip_prefix(prefix)?;
    let end = rest.find(MARKER_END)?;
    Some((
        rest[..end].parse().ok()?,
        prefix.len() + end + MARKER_END.len(),
    ))
}

fn visible_width(value: &str) -> usize {
    let mut plain = String::new();
    let mut rest = value;
    while let Some(index) = rest.find('\u{1b}') {
        plain.push_str(&rest[..index]);
        rest = &rest[index + 1..];
        rest = rest.find('m').map_or("", |end| &rest[end + 1..]);
    }
    plain.push_str(rest);
    UnicodeWidthStr::width(plain.as_str())
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn stack_places_flex_layers_at_both_edges() {
        let mut env = Environment::new();
        env.add_global("viewport_cols", 10usize);
        env.add_function("Stack", stack);
        env.add_function("Flex", flex);
        let output = env
            .render_str(
                "{% call Stack() %}{% call Flex(justify='start') %}left{% endcall %}\n{% call Flex(justify='end') %}end{% endcall %}{% endcall %}",
                (),
            )
            .unwrap();
        assert_eq!(output, "left   end");
    }
}
