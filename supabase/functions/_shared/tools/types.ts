import { z } from "npm:zod@3.25.76";

/** A tool either reads (server-execute, returns data to model) or writes (emits typed intent for client to confirm + execute). */
export type ToolKind = "read" | "write";

/** Confirmation UX class for write tools. Read tools have no confirmation. */
export type ConfirmationClass = "trivial" | "reviewable" | "destructive";

/** Tier requirement. Free tools are visible to all users; PRO tools are filtered out for free users at registry build time. */
export type ToolTier = "free" | "pro";

/** Family grouping for tools (for telemetry + organization). */
export type ToolFamily = "workout" | "nutrition" | "progress" | "plan";

/** Context passed to read-tool handlers. Includes auth + Supabase service-role client. */
export interface ToolContext {
  userId: string;
  isPro: boolean;
  // Supabase service-role client. Type kept loose to avoid coupling to a specific client version.
  // Callers should pass a SupabaseClient<Database> instance.
  // deno-lint-ignore no-explicit-any
  sb: any;
  requestId: string;
}

/** A typed write intent emitted by a write tool, returned to the client for confirmation + Hive execution. */
export interface ToolIntent {
  /** Stable unique ID for this intent (used for client-side lifecycle tracking + concurrent-edit guard). */
  id: string;
  /** Tool name that emitted this intent (e.g. "swapExercise"). Client uses this to route to the right dispatcher branch. */
  type: string;
  /** Validated payload — exactly the shape the tool's Zod schema parsed. */
  // deno-lint-ignore no-explicit-any
  payload: Record<string, any>;
  /** UX class — drives which widget renders the confirmation. */
  confirmationClass: ConfirmationClass;
  /** Human-readable one-line summary for inline cards (e.g. "Squat → Goblet Squat"). */
  previewSummary: string;
  /** ISO 8601 timestamp; client enforces a 1h TTL. */
  createdAt: string;
}

/** A single tool invocation record for telemetry. Stored as one element of ai_coach_interactions.tool_calls JSONB. */
export interface ToolCallRecord {
  name: string;
  status: "ok" | "queued" | "invalid_args" | "pro_blocked" | "unknown" | "failed" | "timeout";
  // deno-lint-ignore no-explicit-any
  args?: Record<string, any>;
  latency_ms?: number;
  error?: string;
}

/** A tool definition — one of these per tool. Lives in supabase/functions/_shared/tools/<family>/<toolName>.ts. */
export interface ToolDefinition<TArgs = unknown, TResult = unknown> {
  name: string;
  family: ToolFamily;
  kind: ToolKind;
  /** Required for write tools; ignored for read tools. */
  confirmationClass?: ConfirmationClass;
  tier: ToolTier;
  /** Plain-text description sent to Gemini in the function declaration. Tell the model when to call this. */
  description: string;
  /**
   * Optional natural-language hints that disambiguate this tool from siblings.
   * Appended to `description` when emitting Gemini function declarations so the
   * model has explicit guidance for multi-intent messages. Per spec §5.2.
   */
  selectionHints?: string;
  /** Zod schema validating the function-call args. */
  schema: z.ZodTypeAny;
  /** Optional max latency for read tools. Default 3000ms. Ignored for write tools. */
  maxLatencyMs?: number;
  /**
   * Build a ToolIntent for write tools. Receives the validated args plus the
   * tool context (auth + Supabase client + tier). Required when kind='write'.
   *
   * MAY be async — returning `Promise<...>` lets a tool do server-side prep
   * (e.g. parse free-text via Gemini) before emitting the intent. Sync builders
   * just return the object directly; tool-loop awaits both shapes naturally.
   *
   * If the builder throws, tool-loop catches it and feeds an `intent_build_failed`
   * functionResponse back to the model so the conversation can recover.
   */
  intentBuilder?: (
    args: TArgs,
    ctx: ToolContext,
  ) =>
    | Promise<Omit<ToolIntent, "id" | "createdAt">>
    | Omit<ToolIntent, "id" | "createdAt">;
  /** Execute a read tool server-side. Receives validated args + context. Required when kind='read'. */
  handler?: (ctx: ToolContext, args: TArgs) => Promise<TResult>;
}
