# Policy reference

The full reference for every key in `payload/etc/policy.yaml`.
Operators may edit this file at any time; the policy gate re-reads
it on every classification, so changes take effect without
restarting the service.

The on-disk file shipped with the install is the authoritative
example — `C:\ProgramData\AiZombie\etc\policy.yaml`. This document
explains *why* each key exists and how the gate uses it.

## File layout

```yaml
settings:
  destructive_confirmation: "..."
  default_class: destructive
sudo_allow_list:
  - winget
  - choco
  # ...
classes:
  read_only: { approval: auto, description: "..." }
  user_change: { approval: required, description: "..." }
  system_change: { approval: required, description: "..." }
  network_change: { approval: required, description: "..." }
  destructive: { approval: required, confirm_phrase: true, description: "..." }
rules:
  - { pattern: "...", class: "..." }
tool_classes: {}
agent:
  max_tool_calls_per_turn: 12
  max_elevated_calls_per_turn: 3
```

## `settings`

| Key | Default | Purpose |
| --- | --- | --- |
| `destructive_confirmation` | `"yes, I understand this is destructive"` | Phrase the operator must type before a `destructive` action runs. |
| `default_class` | `destructive` | Fail-closed class used when no rule matches. Anything else weakens the safety posture. |

## `sudo_allow_list`

A flat list of program basenames (PowerShell cmdlets or `.exe`
names) that are pre-classified as `system_change` when they would
otherwise fall to `default_class`. This lets common privileged
operations stay in the standard approval flow instead of escalating
to a confirmation phrase.

Entries are matched against the **basename** of the program that the
agent is about to invoke. Add a name here when you find yourself
hitting "destructive confirmation" prompts for a tool that should
only be `system_change`.

## `classes`

The five fixed action classes, in increasing severity:

| Class | Default approval | Confirm phrase | Meaning |
| --- | --- | --- | --- |
| `read_only` | `auto` | no | Diagnostics and inspection only. Never mutates. |
| `user_change` | `required` | no | Changes within the agent account's profile or user-owned files. |
| `system_change` | `required` | no | Package, service, file, or container mutation. |
| `network_change` | `required` | no | Defender Firewall, Tailscale, RDP, sshd, interface mutation. |
| `destructive` | `required` | yes | Irreversible mutation. |

Each class supports:

| Key | Type | Values |
| --- | --- | --- |
| `approval` | string | `auto`, `required` |
| `confirm_phrase` | bool | `true` only meaningful when `approval=required` |
| `description` | string | Free-text rendered in the chat UI |

You can override the defaults — for example to require approval
even for `read_only` — but the class **names** are fixed.

## `rules`

A list of `{ pattern, class }` entries, evaluated in order against
the proposed command string. The first matching rule wins.

* `pattern` is a Python regular expression, applied with `re.search`.
* `class` must be one of the five class names above.
* Order matters: put the more specific patterns first.

Two pattern shapes to be aware of:

* `^Get-…\b` — anchored at the start, used for `read_only` rules so
  a pipeline containing `Get-Process` does not auto-run.
* `\bSet-Service\b` — unanchored, used for `system_change` so the
  same cmdlet is gated wherever it appears.

When a rule needs to span a real shell expression, prefer to keep it
literal rather than allowing arbitrary substitution. The classifier
already strips `sudo` and env-prefix tokens before matching.

## `tool_classes`

Per-tool overrides for the closed pi-mono `TOOL_REGISTRY`. Example:

```yaml
tool_classes:
  gui.click: user_change
  net.status: read_only
```

Tools not listed here use the `classification` defined in
`payload/agent/tools.py`. Unknown tools fall back to `default_class`
(fail-closed).

## `agent`

| Key | Default | Purpose |
| --- | --- | --- |
| `max_tool_calls_per_turn` | `12` | Hard cap on tool calls in a single model turn. |
| `max_elevated_calls_per_turn` | `3` | Cap on tool calls classified above `read_only` in a single turn. |

The chat service refuses further tool calls once a budget is
exhausted and surfaces the refusal in the audit log.

## Worked examples

### Loosen `read_only` so the operator must approve everything

```yaml
classes:
  read_only:
    approval: required
    description: "All commands require approval (paranoid mode)."
```

### Add a new sudo-equivalent program

```yaml
sudo_allow_list:
  - winget
  - choco
  - my-corp-tool   # added
```

### Add a project-specific destructive pattern

```yaml
rules:
  - pattern: '\bmy-corp-tool\s+wipe\b'
    class: destructive
  # ... existing rules ...
```

### Restrict a single pi-mono tool

```yaml
tool_classes:
  gui.click: system_change   # treat clicks as mutating
```

## Editing safely

1. Take a backup: `Copy-Item C:\ProgramData\AiZombie\etc\policy.yaml policy.yaml.bak`.
2. Edit with any text editor; the file is plain YAML.
3. Confirm it parses: `python -c "import yaml; yaml.safe_load(open(r'C:\ProgramData\AiZombie\etc\policy.yaml'))"`.
4. The service re-reads on the next classification — no restart
   required. The change is captured as a `policy_reload` audit
   entry.

A JSON Schema for editor validation lives at
[`../schemas/policy.schema.json`](../schemas/policy.schema.json).
