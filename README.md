# DayTrace Documentation Pack

This pack is designed to be copied into the DayTrace Flutter repository.

## Files
- `DayTrace_PRD_v1.0.pdf`: human-readable approved specification.
- `PRD.md`: AI-readable source of truth.
- `AGENTS.md`: permanent coding-agent contract; place at repository root.
- `ARCHITECTURE.md`: technical boundaries and code structure.
- `DATABASE_SCHEMA.sql`: canonical logical schema.
- `IMPLEMENTATION_PLAN.md`: phased execution and quality gates.
- `MASTER_PROMPT.md`: paste once at the start of an AI IDE session, then append one task.
- `DECISIONS.md`: append-only architecture/product decision record.
- `CHANGELOG.md`: implementation history.

## Suggested Repository Placement
```text
DayTrace/
  AGENTS.md
  CHANGELOG.md
  docs/
    PRD.md
    ARCHITECTURE.md
    DATABASE_SCHEMA.sql
    IMPLEMENTATION_PLAN.md
    MASTER_PROMPT.md
    DECISIONS.md
```

The PDF is for reading and sharing. AI agents should primarily read the Markdown and SQL files because structured text wastes fewer tokens and is easier to search than repeatedly parsing a PDF.
# Daytrace
