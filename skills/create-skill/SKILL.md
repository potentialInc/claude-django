---
name: create-skill
description: Create a new Claude Code skill by interviewing the user about its purpose, configuration, and instructions
argument-hint: [skill-name or description]
disable-model-invocation: true
---

# Skill Creator

Create a new Claude Code skill from the user's description: **$ARGUMENTS**

## Workflow — FOLLOW THIS ORDER STRICTLY

### Phase 1: Interview

Use `AskUserQuestion` to gather all the information needed. Ask in rounds — don't overwhelm with all questions at once.

**Round 1 — Identity:**
- What is the skill name? (lowercase, hyphens only, max 64 chars)
- What does this skill do? (1-2 sentence description)
- Should it accept arguments? If yes, what's the hint? (e.g., `[filename]`, `[model-name]`)

**Round 2 — Behavior:**
- Should Claude auto-invoke this skill based on context, or manual only? (`disable-model-invocation`)
- Should it appear in the `/` slash menu? (`user-invocable`)
- Should it run in a forked subagent context? (`context: fork`)
- What tools should it be allowed to use without asking? (`allowed-tools`)

**Round 3 — Content:**
- What is the core instruction/purpose? What should it do step by step?
- Does it need a specific workflow? (e.g., interview → plan → build)
- Are there rules, constraints, or things it should never do?
- Does it need code templates, examples, or reference material?

**Keep asking** until you have a complete picture. Do NOT guess — ask.

### Phase 2: Design

1. **Enter plan mode** using `EnterPlanMode`
2. Design the complete SKILL.md in the plan file, including:
   - Full YAML frontmatter with all configuration
   - Complete markdown body with instructions
   - Any supporting sections (templates, rules, examples)
3. Present the design to the user via `ExitPlanMode` for approval

### Phase 3: Build

1. **Only after user approves**, create the skill file
2. Write to: `skills/<skill-name>/SKILL.md`

---

## SKILL.md Format Reference

### YAML Frontmatter

```yaml
---
name: skill-name                    # Required: lowercase, hyphens, max 64 chars
description: What this skill does   # Recommended: Claude uses this to decide when to auto-load
disable-model-invocation: true      # Optional: true = manual only, false = Claude can auto-invoke
user-invocable: true                # Optional: false = hidden from / menu, only Claude can invoke
argument-hint: [arg1] [arg2]        # Optional: hint shown during autocomplete
allowed-tools: Read, Grep, Bash     # Optional: tools allowed without asking permission
model: sonnet                       # Optional: model override for this skill
context: fork                       # Optional: run in isolated subagent context
agent: Explore                      # Optional: subagent type when context=fork
---
```

### Frontmatter Field Guide

| Field | Default | When to Use |
|-------|---------|-------------|
| `name` | directory name | Always set explicitly |
| `description` | none | Always — Claude uses this for auto-invocation decisions |
| `disable-model-invocation` | `false` | Set `true` for skills with side effects or that need explicit invocation |
| `user-invocable` | `true` | Set `false` for background knowledge only Claude should use |
| `argument-hint` | none | When the skill accepts arguments |
| `allowed-tools` | none | When the skill needs specific tools without permission prompts |
| `context` | none | Set `fork` to isolate from main conversation |
| `agent` | none | Set subagent type (`Explore`, `Plan`, `general-purpose`) when `context: fork` |

### Argument Substitution

| Placeholder | Resolves To |
|-------------|-------------|
| `$ARGUMENTS` | All arguments passed to the skill |
| `$ARGUMENTS[0]` or `$0` | First argument |
| `$ARGUMENTS[1]` or `$1` | Second argument |

### Markdown Body

The body should contain:
1. **Title** — what the skill does
2. **Context line** — `$ARGUMENTS` reference if it accepts arguments
3. **Instructions** — step-by-step what to do
4. **Templates/Examples** — if applicable
5. **Rules/Constraints** — what to follow and what to avoid

## After Creating

- Inform the user the skill is ready at `skills/<name>/SKILL.md`
- Tell them to invoke it with `/<skill-name> [arguments]`
