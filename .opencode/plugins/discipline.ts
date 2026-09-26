// .opencode/plugins/discipline.ts — opencode parity layer for the project's
// Claude Code discipline hooks. REUSES the tested Dart scripts under scripts/
// rather than reimplementing their rules (one source of truth, zero drift):
//
//   scripts/git_safety_hook.dart   (Claude PreToolUse Bash, blocking)
//     -> tool.execute.before: fed a Claude-compatible JSON payload on stdin;
//        exit code 2 => throw => opencode denies the tool call. Pre-filtered
//        to git-shaped commands so ordinary bash pays no dart-run cost.
//        Fail-CLOSED fallback when dart itself is unavailable: raw
//        git commit/push not going through the safe_* wrappers is denied.
//
//   scripts/discipline_hook.dart   (SessionStart: worktree warning, OI board,
//                                   MEMORY.md nudge; UserPromptSubmit: hot-set)
//   scripts/check_alerts.dart      (SessionStart: unacknowledged alerts)
//   scripts/reconcile_ci.dart      (SessionStart: CI failures on armed pushes)
//     -> event(session.created | session.compacted): all three run once, their
//        output is stored in memory and injected via the system transform.
//
//   scripts/batch_close_hook.dart  (Claude Stop hook: §5 close-out checklist)
//     -> event(session.idle): the dart script keeps its own once-per-HEAD-sha
//        state file and kill switch; when it emits decision=block the reason
//        is surfaced at the NEXT model call and cleared (opencode cannot
//        block a turn end — documented delta vs Claude Code).
//
//   The discipline hot-set + skill reminder are embedded BYTE-IDENTICAL from
//   scripts/discipline_hook.dart (extracted at port time) and injected
//   ALWAYS-ON via experimental.chat.system.transform — stronger than the
//   Claude trigger-matched injection because it survives compaction by
//   construction; experimental.session.compacting re-pushes it as well.
//
// SAFETY CONTRACT (mirrors the dart hooks): this plugin must never wedge a
// session. Every hook body is defensive; failures fail OPEN except the two
// explicit deny paths (dart exit 2, dart-unavailable raw commit/push).
// Kill switch: touch .opencode/.discipline.disabled
import type { Plugin } from "@opencode-ai/plugin"
import { spawnSync } from "node:child_process"
import * as fs from "node:fs"
import * as os from "node:os"
import * as path from "node:path"

const HOT_SET = `
⚠️ DISCIPLINE HOT-SET (harness-injected — this reads like a bug/fix/observation).
Apply these BEFORE touching code; instantiate them as TodoWrite items now:
1. WAIT → BRAINSTORM → PROPOSE. If APK observations, gather ALL first; never reflex-fix (§4.1).
2. BUG-HISTORY FIRST. Grep docs/diagnoses/INDEX.md + feedback_*.md for this symptom/file BEFORE
   hypothesizing a root cause; cite or rule out recurrence (§4.1.5).
3. NAME WRITER + READER by file:line before proposing any fix — writer/reader drift is the
   default suspect class (§4.1, recurring ≥15×).
4. NO DEFERRALS, incl. euphemisms. Banned re-wraps: "dedicated/follow-up/test-maintenance/cleanup
   batch", "gradual population", "can be folded into", "lower-severity", "responsible handoff".
   Fix every surfaced bug in THIS batch (§4.2).
5. DIAGNOSE-DOC + behavioral regression test per fix; verify the FULL chain (write→read), not
   just an HTTP/exit-0 shape (§4.4 r21/r22).
6. SELF-TRIGGER the ≥account /code-review (B-pass) BEFORE the --no-ff merge — don't wait to be
   asked (§4.3).
7. BEFORE any Skill call, load + apply §4 (and the Wardroom brand soul for copy) — never fire a
   skill blind (§4.12).
Verify numeric claims from subagents/memory against the actual file before relying on them.`

const SKILL_REMINDER = `
⚠️ DISCIPLINE BEFORE SKILL (harness-injected — a Skill is about to run).
Load + apply the governing invariants FIRST — never fire a skill blind (§4.12):
- CLAUDE.md §4 process invariants for the action this skill performs;
- the Wardroom brand soul (lib/shared/widgets/wardroom/CLAUDE.md) for ANY copy/UI/mockup work;
- the observation → bug-history → writer/reader workflow (§4.1/§4.1.5) if this is a fix/debug skill.
If this is /code-review or /hermes-pass: confirm the blast-radius and that the ×2 plan-review
already happened (§4.12). If /build-apk: from main only, explicit approval given (§4.3).`

const MEMORY_POINTER = `MEMORY STORE (self-evolution — shared with Claude Code):
- Index: ~/.claude/projects/C--Upendra-Claude-Code-Fitness-App/memory/MEMORY.md
  (read it before trusting anything; soft cap ~17.5KB — consolidate when over).
- Founder corrected a factual claim you made? WRITE
  memory/feedback_mistake_<topic>.md + one MEMORY.md index line BEFORE your
  next tool call. Ship-shape work ends with a project_<topic>.md retrospective.
- Any path/number recalled from memory is point-in-time: verify against the
  live file (Read/Grep) before relying on it.`

const ALWAYS_ON = `═══ DISCIPLINE (harness-injected — opencode parity with Claude Code hooks) ═══
${HOT_SET}

${SKILL_REMINDER}

${MEMORY_POINTER}`

type DartResult = { status: number | null; stdout: string; stderr: string } | null

function runDartHook(script: string, payload: unknown, cwd: string, timeoutMs: number): DartResult {
  try {
    const r = spawnSync("dart", ["run", "--verbosity=error", `scripts/${script}`], {
      input: JSON.stringify(payload),
      cwd,
      encoding: "utf8",
      timeout: timeoutMs,
      windowsHide: true,
    })
    return { status: r.status, stdout: r.stdout ?? "", stderr: r.stderr ?? "" }
  } catch {
    return null
  }
}

function extractAdditionalContext(stdout: string): string {
  if (!stdout || !stdout.trim()) return ""
  try {
    const j = JSON.parse(stdout)
    const ctx = j?.hookSpecificOutput?.additionalContext
    return typeof ctx === "string" ? ctx : ""
  } catch {
    return ""
  }
}

function safeJson(stdout: string): any {
  try {
    return JSON.parse(stdout)
  } catch {
    return null
  }
}

function sessionIdOf(event: any): string {
  const p = event?.properties ?? {}
  return String(p?.info?.id ?? p?.sessionID ?? p?.id ?? "")
}

export const DisciplinePlugin: Plugin = async ({ directory, worktree }) => {
  const root = worktree || directory || process.cwd()
  const disabled = () => {
    try {
      return fs.existsSync(path.join(root, ".opencode", ".discipline.disabled"))
    } catch {
      return false
    }
  }

  let sessionContextText = ""
  let batchPendingText = ""

  function refreshSessionContext(sessionId: string): void {
    if (disabled()) return
    const parts: string[] = []

    // 1) discipline_hook SessionStart — worktree warning, OI board, memory nudge
    const dh = runDartHook(
      "discipline_hook.dart",
      { hook_event_name: "SessionStart", source: "startup", session_id: sessionId, cwd: root },
      root,
      180000,
    )
    const dhCtx = dh && dh.status === 0 ? extractAdditionalContext(dh.stdout) : ""
    if (dhCtx) parts.push(dhCtx)

    // 2) unacknowledged alerts
    const al = runDartHook("check_alerts.dart", { session_id: sessionId }, root, 180000)
    if (al && al.status === 0) {
      const j = safeJson(al.stdout)
      if (j && typeof j.count === "number" && j.count > 0 && Array.isArray(j.alerts)) {
        const rows = j.alerts
          .slice(0, 5)
          .map((a: any) => `- [${a.severity ?? "?"}] ${a.summary ?? ""} → ${a.suggested_action ?? ""}`)
          .filter((s: string) => s.trim().length > 4)
          .join("\n")
        if (rows) parts.push(`⚠️ UNACKNOWLEDGED ALERTS (${j.count}${j.count > 5 ? ", showing 5" : ""}):\n${rows}`)
      }
    }

    // 3) CI reconcile on armed pushes
    const ci = runDartHook("reconcile_ci.dart", { session_id: sessionId }, root, 180000)
    if (ci && ci.status === 0) {
      const j = safeJson(ci.stdout)
      const warns = j?.pending_ci_warnings
      if (Array.isArray(warns) && warns.length > 0) {
        const rows = warns
          .slice(0, 5)
          .map((w: any) => `- ${w.kind ?? "?"} on ${w.branch ?? "?"} (${String(w.sha ?? "").slice(0, 8)})${w.conclusion ? `: ${w.conclusion}` : ""}${w.run_url ? ` ${w.run_url}` : ""}`)
          .join("\n")
        parts.push(`⚠️ CI RECONCILE:\n${rows}`)
      }
    }

    sessionContextText = parts.join("\n\n")
  }

  return {
    event: async ({ event }) => {
      try {
        if (event.type === "session.created" || event.type === "session.compacted") {
          refreshSessionContext(sessionIdOf(event))
        } else if (event.type === "session.idle") {
          if (disabled()) return
          const bc = runDartHook(
            "batch_close_hook.dart",
            {
              hook_event_name: "Stop",
              stop_hook_active: false,
              session_id: sessionIdOf(event),
              transcript_path: "",
              cwd: root,
            },
            root,
            180000,
          )
          if (bc && bc.status === 0) {
            const j = safeJson(bc.stdout)
            if (j?.decision === "block" && typeof j.reason === "string" && j.reason.trim()) {
              batchPendingText = j.reason.trim()
            }
          }
        }
      } catch {
        // never wedge the session
      }
    },

    "tool.execute.before": async (input, output) => {
      let verdict: { deny: boolean; reason: string } | null = null
      try {
        if (input?.tool !== "bash" || disabled()) return
        const command = String((output?.args as any)?.command ?? "")
        if (!command || !/\bgit\b/.test(command)) return
        const r = runDartHook(
          "git_safety_hook.dart",
          { hook_event_name: "PreToolUse", tool_name: "Bash", tool_input: { command }, cwd: root },
          root,
          120000,
        )
        if (r && r.status === 2) {
          verdict = { deny: true, reason: (r.stderr || r.stdout || "Blocked by scripts/git_safety_hook.dart (CLAUDE.md §4.3: use scripts/safe_commit.sh / safe_push.sh)").trim() }
        } else if (!r || r.status === null) {
          // dart unavailable — fail CLOSED only for the riskiest shapes
          const rawLanding = /\bgit\s+(commit|push)\b/.test(command) && !/scripts[\\\/]safe_(commit|push|merge)\.sh/.test(command) && !/^ALLOW_RAW_GIT=1\b/.test(command.trim())
          if (rawLanding) {
            verdict = { deny: true, reason: "git_safety_hook.dart unavailable AND raw git commit/push is not allowed — use scripts/safe_commit.sh / scripts/safe_push.sh (CLAUDE.md §4.3)" }
          }
        }
      } catch {
        // fail open for anything unexpected in this hook EXCEPT an explicit verdict
      }
      if (verdict?.deny) throw new Error(verdict.reason)
    },

    "experimental.chat.system.transform": async (_input, output) => {
      try {
        if (disabled()) return
        const extra: string[] = []
        if (sessionContextText) extra.push(sessionContextText)
        if (batchPendingText) {
          extra.push(batchPendingText)
          batchPendingText = "" // surface once per landed sha (dart state file dedupes upstream)
        }
        extra.push(ALWAYS_ON)
        const block = extra.join("\n\n")
        const o = output as any
        if (Array.isArray(o?.system)) o.system.push(block)
        else if (typeof o?.system === "string") o.system = o.system + "\n\n" + block
        else if (o && typeof o === "object") o.system = [block]
      } catch {
        // never wedge the session
      }
    },

    "experimental.session.compacting": async (_input, output) => {
      try {
        if (disabled()) return
        ;(output as any)?.context?.push?.(ALWAYS_ON)
      } catch {
        // never wedge the session
      }
    },
  }
}
