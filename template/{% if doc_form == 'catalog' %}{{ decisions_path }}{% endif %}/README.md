# Decisions

The journal of decisions taken — one file per decision, like an ADR. Only decisions taken, with a reason and a consequence; options still under discussion belong in open questions.

## Format

File name — `YYYY-MM-DD-slug.md`: the date of the decision and a short Latin kebab-case name (`2026-10-28-postgres-storage.md`).

```markdown
# Decision title

## Decision

What was decided — in one paragraph.

## Reason

Why this and not otherwise: what was compared, whose decision it is.

## Consequence

What follows from the decision for the code, the process and other decisions.
```

The journal is append-only: an entry is not rewritten. A decision is revoked or changed by a new entry that links to the old one; the old one may only gain a line linking to the one that revoked it.

## Decisions

<!-- toc: built by knowledge/index.sh, do not edit -->
_empty_
<!-- /toc -->
