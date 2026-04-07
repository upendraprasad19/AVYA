import { serve } from "https://deno.land/std@0.177.0/http/server.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2.39.3";
import { getEmbedding } from "./_shared/embeddings.ts";
import { cascadeChat, FREE_MODELS } from "./_shared/openrouter.ts";

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers":
    "authorization, x-client-info, apikey, content-type",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
};

const OPENROUTER_API_KEY = Deno.env.get("OPENROUTER_API_KEY")!;
const SUPABASE_URL = Deno.env.get("SUPABASE_URL")!;
const SUPABASE_SERVICE_ROLE_KEY = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;

// Use cheap Llama 3.1 8B for summarization — ~₹0.01/user/run
const SUMMARY_MODEL = "cerebras/llama-3.1-8b";
const SUMMARY_MODEL_LABEL = "Cerebras Llama 3.1 8B";

const MESSAGE_THRESHOLD = 50;
const KEEP_RECENT = 10;

/**
 * Returns yesterday's date string in IST (UTC+5:30) as YYYY-MM-DD.
 */
function getYesterdayIST(): string {
  const now = new Date();
  const istOffset = 330 * 60 * 1000;
  const istDate = new Date(now.getTime() + istOffset);
  istDate.setDate(istDate.getDate() - 1);
  return istDate.toISOString().split("T")[0];
}

/**
 * Returns today's date string in IST (UTC+5:30) as YYYY-MM-DD.
 */
function getTodayIST(): string {
  const now = new Date();
  const istOffset = 330 * 60 * 1000;
  const istDate = new Date(now.getTime() + istOffset);
  return istDate.toISOString().split("T")[0];
}

/**
 * Call cascadeChat to summarize conversation messages into a fitness summary.
 * Uses the shared cascade utility — tries SUMMARY_MODEL first, then FREE_MODELS.
 */
async function summarizeMessages(
  messages: { user_message: string; ai_response: string; created_at: string }[],
): Promise<string | null> {
  const conversationText = messages
    .map(
      (m) =>
        `[${m.created_at}]\nUser: ${m.user_message}\nCoach: ${m.ai_response}`,
    )
    .join("\n\n");

  const systemPrompt =
    "You are a fitness data summarizer. Given a conversation history between a user and their AI fitness coach, " +
    "extract and summarize the key fitness information into a concise ~200 token summary. Include:\n" +
    "- Current goals and preferences mentioned\n" +
    "- Training patterns and progress noted\n" +
    "- Nutrition habits discussed\n" +
    "- Injuries or limitations mentioned\n" +
    "- Key coaching advice given\n" +
    "Output ONLY the summary text, no preamble.";

  const { content } = await cascadeChat({
    models: [
      SUMMARY_MODEL,
      ...FREE_MODELS,
    ],
    systemPrompt,
    userPrompt: `Summarize this fitness coaching conversation:\n\n${conversationText}`,
    maxTokens: 300,
    timeoutMs: 10000,
    title: "ICANBEFITTER Rolling Context",
  });

  return content;
}

serve(async (req: Request) => {
  if (req.method === "OPTIONS") {
    return new Response("ok", { headers: corsHeaders });
  }

  if (req.method !== "POST") {
    return new Response(JSON.stringify({ error: "Method not allowed" }), {
      status: 405,
      headers: { ...corsHeaders, "Content-Type": "application/json" },
    });
  }

  try {
    // This is a cron job — uses service role key, no JWT validation needed
    const supabaseClient = createClient(SUPABASE_URL, SUPABASE_SERVICE_ROLE_KEY);

    // Find users with >50 messages in ai_coach_interactions
    // Use a raw count query grouped by user_id
    const { data: userCounts, error: countError } = await supabaseClient.rpc(
      "get_users_with_message_count",
      { min_count: MESSAGE_THRESHOLD },
    );

    // Fallback: if RPC doesn't exist, query all users and count manually
    let usersToProcess: { user_id: string; msg_count: number }[] = [];

    if (countError || !userCounts) {
      console.log(
        "RPC not available, falling back to manual count. Error:",
        countError?.message,
      );

      // Get distinct user_ids from ai_coach_interactions
      const { data: distinctUsers, error: distinctError } =
        await supabaseClient
          .from("ai_coach_interactions")
          .select("user_id")
          .limit(10000);

      if (distinctError || !distinctUsers) {
        console.error("Failed to fetch users:", distinctError);
        return new Response(
          JSON.stringify({ error: "Failed to fetch users for processing" }),
          {
            status: 500,
            headers: { ...corsHeaders, "Content-Type": "application/json" },
          },
        );
      }

      // Count messages per user
      const userMsgCounts: Record<string, number> = {};
      for (const row of distinctUsers) {
        userMsgCounts[row.user_id] =
          (userMsgCounts[row.user_id] ?? 0) + 1;
      }

      // Filter users with >= threshold
      // Note: The distinct query above doesn't give actual counts per user.
      // We need to do individual counts for each unique user.
      const uniqueUserIds = [...new Set(distinctUsers.map((r) => r.user_id))];

      for (const uid of uniqueUserIds) {
        const { count, error: cErr } = await supabaseClient
          .from("ai_coach_interactions")
          .select("id", { count: "exact", head: true })
          .eq("user_id", uid);

        if (!cErr && (count ?? 0) >= MESSAGE_THRESHOLD) {
          usersToProcess.push({ user_id: uid, msg_count: count ?? 0 });
        }
      }
    } else {
      usersToProcess = userCounts as {
        user_id: string;
        msg_count: number;
      }[];
    }

    if (usersToProcess.length === 0) {
      return new Response(
        JSON.stringify({
          status: "success",
          users_processed: 0,
          message: "No users with enough messages to summarize",
        }),
        {
          status: 200,
          headers: { ...corsHeaders, "Content-Type": "application/json" },
        },
      );
    }

    const snapshotDate = getTodayIST();
    let processed = 0;
    let errors = 0;
    let skipped = 0;

    for (const { user_id: userId, msg_count: msgCount } of usersToProcess) {
      try {
        // Fetch all messages ordered by created_at ascending
        const { data: allMessages, error: msgError } = await supabaseClient
          .from("ai_coach_interactions")
          .select("id, user_message, ai_response, created_at")
          .eq("user_id", userId)
          .order("created_at", { ascending: true });

        if (msgError || !allMessages || allMessages.length < MESSAGE_THRESHOLD) {
          skipped++;
          continue;
        }

        // Messages to summarize = all except the last KEEP_RECENT
        const keepIndex = allMessages.length - KEEP_RECENT;
        const toSummarize = allMessages.slice(0, keepIndex);
        const toKeep = allMessages.slice(keepIndex);

        if (toSummarize.length === 0) {
          skipped++;
          continue;
        }

        // ── Phase C: Embed each message BEFORE deleting it ─────────────────
        // Preserves semantic memory permanently in memory_embeddings.
        // Delete only happens after this block — safe to re-run on failure.
        // Partial embedding is acceptable (logged but doesn't abort the run).
        let embeddedCount = 0;
        for (const msg of toSummarize) {
          try {
            const content = `User: ${msg.user_message}\nCoach: ${msg.ai_response}`;
            const embedding = await getEmbedding(content, "RETRIEVAL_DOCUMENT");
            if (!embedding) continue;
            await supabaseClient.from("memory_embeddings").insert({
              user_id: userId,
              embedding,
              content,
              source_type: "conversation",
              metadata: {
                original_interaction_id: msg.id,
                date: (msg.created_at as string).split("T")[0],
                archived_by: "rolling-context",
              },
            });
            embeddedCount++;
          } catch (embErr) {
            console.error(
              `[rolling-context] Embed failed for msg ${msg.id}:`,
              embErr,
            );
          }
        }
        console.log(
          `[rolling-context] User ${userId}: embedded ${embeddedCount}/${toSummarize.length} messages before archival`,
        );

        // Summarize the older messages
        const summary = await summarizeMessages(toSummarize);

        if (!summary) {
          console.error(
            `Failed to summarize messages for user ${userId} after retries`,
          );
          errors++;
          continue;
        }

        // Save summary to user_daily_snapshots.snapshot_json.fitness_summary
        // First, fetch existing snapshot for today (if any)
        const { data: existingSnapshot } = await supabaseClient
          .from("user_daily_snapshots")
          .select("id, snapshot_json")
          .eq("user_id", userId)
          .eq("snapshot_date", snapshotDate)
          .single();

        const updatedJson = {
          ...(existingSnapshot?.snapshot_json ?? {}),
          fitness_summary: summary,
          fitness_summary_updated_at: new Date().toISOString(),
          messages_summarized: toSummarize.length,
          messages_kept: toKeep.length,
        };

        // Upsert the snapshot with fitness_summary
        const { error: upsertError } = await supabaseClient
          .from("user_daily_snapshots")
          .upsert(
            {
              user_id: userId,
              snapshot_date: snapshotDate,
              snapshot_json: updatedJson,
              created_at: new Date().toISOString(),
            },
            { onConflict: "user_id,snapshot_date" },
          );

        if (upsertError) {
          console.error(
            `Failed to save summary for user ${userId}:`,
            upsertError,
          );
          errors++;
          continue;
        }

        // Delete the summarized messages (keep last KEEP_RECENT)
        const idsToDelete = toSummarize.map((m) => m.id);

        // Delete in batches of 100 to avoid query size limits
        const batchSize = 100;
        for (let i = 0; i < idsToDelete.length; i += batchSize) {
          const batch = idsToDelete.slice(i, i + batchSize);
          const { error: deleteError } = await supabaseClient
            .from("ai_coach_interactions")
            .delete()
            .in("id", batch);

          if (deleteError) {
            console.error(
              `Failed to delete batch for user ${userId}:`,
              deleteError,
            );
            // Continue — partial delete is acceptable, will be cleaned up next run
          }
        }

        processed++;
        console.log(
          `User ${userId}: summarized ${toSummarize.length} messages, kept ${toKeep.length}`,
        );
      } catch (userErr) {
        console.error(`Error processing user ${userId}:`, userErr);
        errors++;
      }
    }

    return new Response(
      JSON.stringify({
        status: "success",
        users_processed: processed,
        users_skipped: skipped,
        errors,
        total_eligible: usersToProcess.length,
      }),
      {
        status: 200,
        headers: { ...corsHeaders, "Content-Type": "application/json" },
      },
    );
  } catch (err) {
    const message = err instanceof Error ? err.message : "Internal server error";
    console.error("Rolling context error:", message);
    return new Response(JSON.stringify({ error: message }), {
      status: 500,
      headers: { ...corsHeaders, "Content-Type": "application/json" },
    });
  }
});
