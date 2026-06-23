# Two-Tiered Config Template

A reusable template for any project that needs to read a config file. Copy the
`bash/` folder, the `python/` folder, or both into your project — along with a
`config_default.yaml` — and you get the same two-tiered config behavior in
either language.

## The two tiers

| File | Role | Committed? |
| --- | --- | --- |
| `config_default.yaml` | Canonical defaults — the source of truth for *which* keys exist and their fallback values. No secrets, no machine-specific values. | ✅ yes |
| `config.yaml` | Local overrides for this machine/checkout. | ❌ no (gitignored) |

**Behavior:**

1. **First run** — if `config.yaml` doesn't exist, it's created by copying
   `config_default.yaml` (comments and structure preserved), so you have a
   file to edit.
2. **Every load** — the effective config is the defaults *deep-merged with*
   `config.yaml`. `config.yaml` wins for any key it sets; every key it omits
   falls back to `config_default.yaml`. So adding a new key to
   `config_default.yaml` later makes it immediately available everywhere,
   without touching existing `config.yaml` files.
3. `config.yaml` on disk is never modified after creation (no backfill).

## Layout

```text
config/
├── config_default.yaml   # SHARED defaults (edit this to add/change keys)
├── config.yaml           # generated on first run; gitignored
├── bash/                 # bash implementation
│   ├── yaml_parser.sh    # pure-bash YAML parser
│   ├── config.sh         # the loader (source this)
│   ├── example.sh
│   └── test_config.sh
└── python/               # python implementation
    ├── config.py         # the loader
    ├── requirements.txt
    ├── example.py
    └── test_config.py
```

## Bash usage

```bash
source bash/config.sh
config_load                 # defaults to repo root; creates config.yaml if missing
# config_load /path/to/dir  # or point at an explicit config dir

config get app.name         # → my-app
config get app.workers      # → 4 (falls back to defaults)
config get features         # list: one item per line
config keys                 # all dotted keys (union of both tiers)
config destroy              # tear down loaded state
```

Run the demo and tests:

```bash
bash bash/example.sh
bash bash/test_config.sh
```

## Python usage

```bash
pip install -r python/requirements.txt    # pyyaml
```

```python
from config import Config

cfg = Config.load()                 # defaults to repo root; creates config.yaml if missing
# cfg = Config.load("/path/to/dir") # or an explicit config dir

cfg["app"]["name"]                  # → "my-app"  (dict-style access)
cfg["app.name"]                     # → "my-app"  (dotted access)
cfg.get("app.workers")              # → 4         (dotted; falls back to defaults)
cfg.get("missing.key", default=0)   # → 0
cfg.require("database.host")         # → raises KeyError if absent
cfg.set("app.workers", 8)           # in-memory override (e.g. a CLI flag); never written to disk
"app.name" in cfg                   # → True
cfg.flat_keys()                     # → ["app.name", "app.workers", ...]  (mirrors bash `config keys`)
cfg.reload()                         # re-read both tiers from disk
cfg.as_dict()                        # → plain dict;  cfg.to_yaml() → YAML string
```

The module-level `load_config`, `get`, and `deep_merge` remain as
backward-compatible wrappers (`load_config` now returns a `Config`, which is a
drop-in for the old dict in both the `cfg["app"]["name"]` and
`get(cfg, "app.name")` styles).

Run the demo and tests:

```bash
python python/example.py
pytest python/test_config.py
```

## Variable & environment references

`config_default.yaml` can use two reference styles:

- `${env:VAR}` / `${env:VAR:-default}` — pulled from the environment.
  **Both** bash and Python expand these.
- `${var}` / `${nested.key}` — cross-references to other keys in the file.
  **Only the bash parser** resolves these. In Python they're left as literal
  strings (PyYAML doesn't interpolate). If you need cross-references in Python,
  resolve them in your own code or extend `Config._expand_env` in `config.py`.

Keep this difference in mind if a config must read identically from both
languages — prefer `${env:...}` for values both sides should resolve.

## Adapting for your project

1. Replace the sample keys in `config_default.yaml` with your own.
2. Copy `bash/` and/or `python/` into your project.
3. Add `config.yaml` to your `.gitignore` (see this repo's `.gitignore`).
4. Point the loader at wherever your config lives via the `config_dir`
   argument if it isn't one level up from the package folder.
