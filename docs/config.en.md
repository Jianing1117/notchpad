<p align="right"><a href="config.md">中文</a> · English</p>

# Configuration

The config file lives at `~/Library/Application Support/NotchPad/config.json`. The easiest way to open it: **⋯ › Edit Config…** in the panel's top-right corner.

Save your changes and the next hover picks them up. If something is wrong, a yellow line at the top of the panel says what, and NotchPad falls back to the default config in the meantime — nothing is lost.

> TextEdit may turn your quotes into curly quotes (“ ”). NotchPad copes with that.

## Overall shape

```json
{
  "language": "en",
  "tabs": [ ... ],
  "panel": { "width": 560, "height": 420 }
}
```

- `language` (optional): UI language, `"zh"` or `"en"`. Follows the system when absent. You can also switch it under **⋯ › Language**, which relaunches the app.
- `tabs`: the tabs from left to right, up to 5.
- `panel` (optional): size of the open panel in points. Default 560 × 420.

## Fields every tab has

| Field | Required | Meaning |
|---|---|---|
| `type` | ✓ | `pipeline`, `sections` or `jots` |
| `title` | ✓ | Shown on the tab — keep it short |
| `color` | | Accent color, e.g. `"#42FF8C"`. Defaults to a built-in neon palette |
| `placeholder` | | Hint text in the input field |

## Pipeline

Stages you move items through, top to bottom; after the last stage comes "done". Click the circle to move an item to the next stage; click a done item to move it back.

| Field | Meaning |
|---|---|
| `stages` | The stages, each `{ "title": "Shown name", "list": "Reminders list name" }`. `list` defaults to `title` |
| `doneTitle` | Name of the done section, e.g. `"Filmed"`. Shows the last 10, plus how many were done this month |

In Reminders, each stage is a list and "done" means checked. So moving a reminder from one list to another on your iPhone moves it between stages here too.

## Sections

Parallel checklists. Click the circle to check an item off; it sinks to the bottom of its section. Only items checked off today are shown.

| Field | Meaning |
|---|---|
| `sections` | Each `{ "title": "Shown name", "list": "List name", "color": "#FF61B3" }`. `list` and `color` are optional |
| `pinned` | Optional pinned card, see below |

With a single section the header is hidden, so it looks like a plain to-do list.

### Pinned card

Shows the bullet list under one heading of a Markdown file. Read-only — NotchPad never writes to it.

| Field | Meaning |
|---|---|
| `file` | Path starting with `/` or `~` is absolute; anything else is next to config.json, e.g. `"goals.md"` |
| `heading` | Which heading to read, e.g. `"This Month"`. Any heading containing this text matches |
| `title` | Name on the card; defaults to `heading` |

In the file:

```markdown
## This Month (2026-10)
- [Content] Publish twice a week
- [Learning] Finish the editing course
- [x] Done items are greyed out and struck through
```

- A leading `[Tag]` or `【Tag】` becomes the small label on the left.
- Keep the year-month (`2026-10`) in the heading and the card will say "time to update" once the month is over.
- If the file is inside an Obsidian vault, the ↗ button opens it in Obsidian.

## Jots

| Field | Meaning |
|---|---|
| `folder` | Notes folder (in the iCloud account) to save to; defaults to `title`. Created if missing |

Each jot is its own note; the first line becomes the note's title.

## Tips

- **Missing lists are created** in your default Reminders account (usually iCloud).
- **Renaming a list: change both sides.** Rename it in Reminders first, then update `list` in the config. Changing only the config creates a new empty list and leaves your items in the old one.
- Several tabs can share one list.
- **⋯ › Switch Preset** backs up your current config to `config.backup.json` before replacing it.

## Examples

**A reading pipeline:**

```json
{
  "type": "pipeline",
  "title": "Books",
  "color": "#FFCC47",
  "placeholder": "A book to read — press Return",
  "stages": [
    { "title": "To Read", "list": "Books · To Read" },
    { "title": "Reading", "list": "Books · Reading" }
  ],
  "doneTitle": "Finished"
}
```

**A pinned card reading goals from an Obsidian vault:**

```json
"pinned": {
  "title": "This Month",
  "file": "~/Documents/MyVault/Goals.md",
  "heading": "Monthly Goals"
}
```
