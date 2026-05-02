# Diagram regeneration

PlantUML sources are kept as the source of truth:

- `docs/diagrams/system-context.puml`
- `docs/diagrams/runtime-components.puml`
- `docs/diagrams/operator-flow.puml`

GitHub markdown embeds pre-rendered SVGs:

- `docs/diagrams/system-context.svg`
- `docs/diagrams/runtime-components.svg`
- `docs/diagrams/operator-flow.svg`

## When to regenerate

Regenerate SVG files whenever any `.puml` source is changed.

## Regenerate command

From repository root:

```bash
docker run --rm -v "$PWD":/work -w /work plantuml/plantuml -tsvg \
  docs/diagrams/system-context.puml \
  docs/diagrams/runtime-components.puml \
  docs/diagrams/operator-flow.puml
```

Then commit both the modified `.puml` and regenerated `.svg` files together.
