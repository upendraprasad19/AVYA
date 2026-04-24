// _shared/memory_retrieval.ts
//
// Phase B of the semantic-memory system: retrieves the top-N most
// semantically similar past memories for a user, given a query string.
//
// Phase A (accumulation) has been running since migration
// 20260331000001_add_pgvector_memory.sql — every chat turn and nightly
// summary embeds its content and inserts into memory_embeddings.
// This module reads from that table via the pgvector `match_memories`
// RPC and hands ranked matches back to the caller.
//
// Design spec: docs/superpowers/specs/2026-04-24-semantic-retrieval-design.md

import { getEmbedding } from "./embeddings.ts";

export type MemorySourceType =
  | "conversation"
  | "daily_summary"
  | "coaching_note"
  | "pattern_insight";

export type Memory = {
  id: string;
  content: string;
  source_type: MemorySourceType;
  metadata: Record<string, unknown>;
  created_at: string;
  similarity: number;
};

export type RetrievalSource =
  | "retrieval"      // success with >= 1 match
  | "empty"          // RPC returned [] (no user embeddings OR nothing above threshold)
  | "no_embedding"   // getEmbedding returned null (Gemini error)
  | "rpc_error";     // pgvector / network error

export type RetrievalResult = {
  memories: Memory[];
  source: RetrievalSource;
};

export type RetrievalOptions = {
  matchCount?: number;
  threshold?: number;
};

/**
 * Retrieve the most semantically relevant past memories for this user.
 *
 * Never throws. All failure modes return `{ memories: [], source: <code> }`
 * so the caller can unconditionally proceed to fallback behavior.
 */
// deno-lint-ignore no-explicit-any
export async function retrieveRelevantMemories(
  // deno-lint-ignore no-explicit-any
  supabaseClient: any,
  userId: string,
  query: string,
  options: RetrievalOptions = {},
): Promise<RetrievalResult> {
  // Will be implemented in Task 2.
  const _unused = { supabaseClient, userId, query, options };
  return { memories: [], source: "empty" };
}
