# Continuum URL Scheme

Continuum registers the `continuum://` URL scheme for a minimal command surface.

## Supported URLs

| URL | Action |
| --- | --- |
| `continuum://toggle-hidden` | Toggle the hidden menu bar section. |
| `continuum://open-settings` | Open the Continuum settings window. |

## Examples

```sh
open "continuum://toggle-hidden"
open "continuum://open-settings"
```

## Mutation Boundary

Continuum does not expose settings mutation over URLs. The inherited settings-write API is disabled so external tools cannot silently rewrite runtime behavior.
