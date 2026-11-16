# Spec revision journal

One file per revision. The journal is append-only: a revision is not rewritten after the fact, a mistake is fixed by the next revision.

## Format

File name — `NNNN-1.N.md`: a four-digit sequence number and the spec version (`0001-1.1.md`, `0012-1.12.md`). The number sets the order, the version is the "(1.N)" label that marks the revision in the spec sections.

```markdown
---
version: "1.N"
date: YYYY-MM-DD
folded: false
---

# Short revision title

What changed and why: whose decision or answer, which spec sections are affected.
```

- `version` — quoted: without quotes YAML reads `1.10` as the number `1.1`.
- `date` — the day the revision was accepted.
- `folded` — whether the revision is folded into the spec sections. A new revision is `false`; after folding into the sections — `true`.

The list of unfolded revisions is not kept by hand: `knowledge/spec-unfolded.sh` prints it, and with `--write` rewrites the block in the spec README.
