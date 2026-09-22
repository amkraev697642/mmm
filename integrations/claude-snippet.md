# >>> mmm >>>
## Memory (mmm)
Cross-project knowledge lives at `~/.omc/wiki/`, project-specific at `<repo>/.omc/wiki/` —
both symlinked into `~/mmm`'s canonical store by `mmm init`. Read/write those paths exactly
as before; `mmm` only changes where the bytes physically live.

- **Look something up:** `mmm q "<term>"` first — instant, free, no model call — before
  grepping or re-deriving it. `mmm a "<question>"` for a natural-language version.
- **Capture before finishing a task:** if it produced a durable finding (multi-file
  investigation, architecture decision, a bug's root cause), update the page that already
  covers it — create one only if nothing does. `mmm import <file-or-folder>` for an existing
  notes dump. Follow `~/mmm/content-rules.md` (bite-sized, one topic, cross-linked).
- **New project:** `mmm init <path>` links it in — idempotent, safe to re-run.
- **Health check:** `mmm doctor` before handing off or packing.
# <<< mmm <<<
