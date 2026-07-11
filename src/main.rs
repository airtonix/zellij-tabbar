//! Zellij plugin shell: tracks host state, renders template frames, and dispatches clicks.

mod render;

use std::collections::BTreeMap;

use render::{ClickAction, RenderedFrame};
use zellij_tile::prelude::*;

/// Host-facing plugin state. Rendering details stay inside the `render` module.
#[derive(Default)]
struct State {
    tabs: Vec<TabInfo>,
    mode_info: ModeInfo,
    template: Option<String>,
    frame: RenderedFrame,
}

register_plugin!(State);

impl ZellijPlugin for State {
    fn load(&mut self, configuration: BTreeMap<String, String>) {
        request_permission(&[
            PermissionType::ReadApplicationState,
            PermissionType::ChangeApplicationState,
        ]);
        self.template = configuration.get("template").cloned();
        // Keep the plugin focusable so Zellij forwards mouse clicks to its buttons.
        set_selectable(true);
        subscribe(&[
            EventType::TabUpdate,
            EventType::ModeUpdate,
            EventType::Mouse,
        ]);
    }

    fn update(&mut self, event: Event) -> bool {
        match event {
            Event::ModeUpdate(mode_info) => {
                let changed = self.mode_info != mode_info;
                self.mode_info = mode_info;
                changed && !self.tabs.is_empty()
            },
            Event::TabUpdate(tabs) => {
                self.tabs = tabs;
                // Always repaint: tab closure can produce an empty or otherwise equal-looking update.
                true
            },
            Event::Mouse(Mouse::LeftClick(row, col)) => {
                if let Some(action) = usize::try_from(row)
                    .ok()
                    .and_then(|row| self.frame.hitboxes.get(row))
                    .and_then(|line| line.get(col))
                    .and_then(Clone::clone)
                {
                    match action {
                        ClickAction::SwitchTab(index) => switch_tab_to(index as u32),
                        ClickAction::NewTab => {
                            new_tab::<&str>(None, None);
                        },
                    }
                }
                false
            },
            _ => false,
        }
    }

    fn render(&mut self, rows: usize, cols: usize) {
        if self.tabs.is_empty() {
            // Clear stale output after the final visible tab disappears.
            self.frame = RenderedFrame::default();
        } else {
            let template = render::selected_template(self.template.as_deref());
            self.frame = match render::render(
                template,
                self.mode_info.session_name.as_deref(),
                &self.tabs,
                rows,
                cols,
                self.mode_info.style.colors,
                self.mode_info.capabilities,
            ) {
                Ok(frame) => frame,
                Err(error) => render::error_frame(&error, rows, cols),
            };
        }
        let output = (0..rows)
            .map(|row| {
                let line = self.frame.lines.get(row).map_or("", String::as_str);
                format!("\u{1b}[2K{line}")
            })
            .collect::<Vec<_>>()
            .join("\n");
        print!("{output}");
    }
}
