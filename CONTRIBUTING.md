# Contributing to mmm

`bin/mmm` is bash; `mmm-query.py`/`mmm-doctor.py` are stdlib-only Python 3 (no pip installs);
the hooks are plain Node `.mjs`, no dependencies, speaking Claude Code's own hook JSON
contract. `install.sh` is POSIX `sh` on purpose — it's piped through `sh`, which is `dash` on
plenty of systems, not bash.

No package manager, no lockfile, no build step: everything it shells out to (`jq`, `git`,
`rsync`, `rg`, `7z`, and `claude` itself) is either a language stdlib call or an
already-common CLI tool you likely have.

Small and readable end to end, not a framework — send a PR the way you'd send a wiki page:
read the function you're closest to touching before adding a new one alongside it, and run

```
mmm doctor
bash -n bin/mmm && sh -n install.sh
bash tests/smoke.sh   # init/doctor/q against a throwaway HOME
```

before you send it. `mmm doctor` clean is the only ask.

## Contributing *content*

That's a separate thing from contributing to the tool — see [content-rules.md](content-rules.md)
for the rules every wiki page follows (bite-sized, one topic, cross-linked, update-before-create).
