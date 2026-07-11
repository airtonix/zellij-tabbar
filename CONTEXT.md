# Glossary

## Render Context

Template-visible snapshot used to produce a frame. It contains session data, tab data, system data, and opaque actions. It does not perform plugin state changes while rendering.

## Rendered Frame

Complete render result for one viewport. It contains terminal lines and a same-coordinate two-dimensional hitbox grid.

## Click Action

Opaque, typed operation attached to button cells in a rendered frame. State dispatches it only after a left click on a matching hitbox.
