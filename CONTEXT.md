# Glossary

## Template Globals

Template-visible snapshot used to produce a frame. `session`, `system`, `actions`, and `context` are top-level globals. `actions` exposes opaque click-action constructors; `context` contains rendering metadata such as theme colours. Rendering does not perform plugin state changes.

## Rendered Frame

Complete render result for one viewport. It contains terminal lines and a same-coordinate two-dimensional hitbox grid.

## Click Action

Opaque, typed operation attached to button cells in a rendered frame. State dispatches it only after a left click on a matching hitbox.
