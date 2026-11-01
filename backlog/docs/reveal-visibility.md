# Visibility of text passages (reveal)

Decided by Nico on 2026-11-01. This replaces the fixed DM-secret markers (TASK-1 AC3). Any
Markdown text in Dragoon (monster, item, note, log entry, package data) can contain passages that
only some people can see.

## Example

A mystical amulet: everyone sees how it looks, Lena (after casting Identify) also sees what it
does, and only the DM knows it is cursed.

```html
A silver amulet with a pale moonstone that feels cold to the touch.

<reveal id="r7" for="lena">**Function:** Once per day the wearer can ...</reveal>

<reveal id="r8" for="dm">**Curse:** The wearer slowly loses ...</reveal>
```

## Rules

- Text without a tag is visible to everyone. The **DM always sees everything**.
- `for` is a comma-separated list: player ids, `party` (all players) or `dm` (DM only).
- `id` is unique within the document and stays stable, so events can point to it. The editor
  creates it.
- Tags can be **nested**. What is visible is the intersection, so a DM-only passage inside Lena's
  passage stays DM-only.
- Works inline (inside a sentence) and around whole paragraphs.
- Shortcut: Obsidian comments `%% ... %%` count as DM-only, because the vault uses them a lot.
  The other markers from the first proposal (`dm_` keys, `[!dm]` callouts, "DM" headings) are
  dropped.

## Revealing is an event

The `for` in the text is the starting state. Reveals during play are events on the timeline:

| Type | `entity` | `data` |
| --- | --- | --- |
| `reveal.changed` | the entity whose text it is | `reveal` (id, e.g. `r7`), `field` (e.g. `description`), `add` (list of ids), `remove` (list of ids) |

So the timeline knows Lena has known the function since day 132, rewinding hides it again, and the
chronicle can show "Lena identified the amulet". Who can see a passage at a given moment = `for` in
the text + all `reveal.changed` events up to that moment.

## Security

The DM host removes every passage a player may not see **before sending** anything to that player
(per recipient), not only in the display. Clients never receive hidden text. This replaces the
filter in `scripts/net/secrets.gd`.

## UI

- **Select text → "Visible for" popup** with checkboxes: each player, *Party*, *DM only*. Applying
  it wraps the selection in a `<reveal>` tag (or edits the existing one); changing it during a
  session writes a `reveal.changed` event.
- **Colored frame** around passages that are hidden from someone. The color is the color the
  person picked for **their account**. That includes the DM: there is no fixed red, the DM uses
  their own account color. Several people means a mixed or striped frame. Passages visible to
  everyone have no frame.
- Anyone who can see a framed passage gets a small hint on hover: "Only you and Lena can see this".
- Obsidian does not know the tag but shows the text inside, so the vault stays readable.
