/**
 * purgeUserStorage — recursive, best-effort removal of every object under
 * `<userId>/` in each given bucket. Extracted verbatim from delete-account
 * (single-owner audit 2026-09-26) so the bucket list and the purge have one
 * owner each and the purge is testable against a fake storage client.
 *
 * OI-32 (audit-2026-05-17 Hermes F7) — recursive Storage purge. `.list(userId)`
 * returns only the top-level entries under `userId/` (objects + subdirectory
 * names, not their contents), so a nested path like `userId/2026/photo.jpg`
 * survived account deletion. DPDP §17 requires erasure of all user-tagged
 * objects — nested or otherwise. The SDK has no `recursive: true` on .list();
 * this is a DFS. Folder entries have `id === null`, file entries a non-null id.
 * Paginated 1000 per call for users with large photo histories.
 *
 * Errors are accumulated in the returned stats and logged, never thrown: the
 * caller must not be blocked from deleting the account by a Storage error.
 *
 * A failed `.list()` loses only what it could not list (Hermes 2026-09-26,
 * L37-F1). Until then one failed page or subfolder threw out of the listing,
 * discarding every path already collected, so NOTHING in that bucket was
 * removed — including files listed fine — while the account deletion still
 * returned 200. Now the failure is recorded as `<bucket>_list:<path>: <msg>`
 * and every path that was listed is still removed.
 *
 * What is still not covered, stated so it is not assumed: an object this purge
 * misses (a failed list or remove) or one written after it (a still-valid JWT
 * uploading an avatar in the seconds after deletion) stays until someone
 * removes it. The errors land in `account_deletion_log.storage_purge_status`,
 * which nothing reads, and `clean-orphan-media` sweeps only chat-media by age.
 * The deleted-user sweep that closes this is unit a4 of
 * docs/plans/2026-09-26-single-owner-batch-a.md.
 */

export interface StorageEntry {
  name: string;
  id: string | null;
}

export interface StorageBucketLike {
  list(
    path: string,
    options: { limit: number; offset: number },
  ): PromiseLike<{ data: StorageEntry[] | null; error: { message: string } | null }>;
  remove(
    paths: string[],
  ): PromiseLike<{ error: { message: string } | null }>;
}

export interface StorageLike {
  from(bucket: string): StorageBucketLike;
}

export type PurgeStats = { [key: string]: number | string[] };

export async function purgeUserStorage(
  storage: StorageLike,
  userId: string,
  buckets: readonly string[],
  requestId: string,
): Promise<PurgeStats> {
  const purgeStats: PurgeStats = { errors: [] };

  async function listAllObjectsRecursive(
    bucket: string,
    prefix: string,
  ): Promise<{ paths: string[]; listErrors: string[] }> {
    const objectPaths: string[] = [];
    const listErrors: string[] = [];
    const stack: string[] = [prefix];
    while (stack.length > 0) {
      const current = stack.pop()!;
      let offset = 0;
      while (true) {
        const { data: entries, error } = await storage
          .from(bucket)
          .list(current, { limit: 1000, offset });
        if (error) {
          // Record and move on to the next folder: keep what was listed.
          listErrors.push(`${current}: ${error.message}`);
          break;
        }
        if (!entries || entries.length === 0) break;
        for (const e of entries) {
          const fullPath = current ? `${current}/${e.name}` : e.name;
          if (e.id === null) {
            // Folder entry — recurse into it.
            stack.push(fullPath);
          } else {
            objectPaths.push(fullPath);
          }
        }
        if (entries.length < 1000) break;
        offset += 1000;
      }
    }
    return { paths: objectPaths, listErrors };
  }

  for (const bucket of buckets) {
    try {
      const { paths, listErrors } = await listAllObjectsRecursive(
        bucket,
        userId,
      );
      for (const listError of listErrors) {
        (purgeStats.errors as string[]).push(`${bucket}_list:${listError}`);
        console.warn(
          `[delete-account] request_id=${requestId} storage list error bucket=${bucket} (non-fatal, listed paths still purged):`,
          listError,
        );
      }

      if (paths.length > 0) {
        // Storage .remove() takes a flat array; chunk by 1000 (the
        // Supabase REST batch limit) so large purges don't reject.
        let removed = 0;
        for (let i = 0; i < paths.length; i += 1000) {
          const chunk = paths.slice(i, i + 1000);
          const { error: rmErr } = await storage.from(bucket).remove(chunk);
          if (rmErr) {
            (purgeStats.errors as string[]).push(
              `${bucket}_rm:${rmErr.message}`,
            );
            console.warn(
              `[delete-account] request_id=${requestId} storage remove error bucket=${bucket} (chunk@${i}):`,
              rmErr.message,
            );
            // Don't break — try remaining chunks.
          } else {
            removed += chunk.length;
          }
        }
        purgeStats[bucket] = removed;
        console.log(
          `[delete-account] request_id=${requestId} purged ${removed}/${paths.length} objects from bucket=${bucket} (recursive)`,
        );
      } else {
        purgeStats[bucket] = 0;
        console.log(
          `[delete-account] request_id=${requestId} bucket=${bucket} empty for user`,
        );
      }
    } catch (e) {
      const msg = e instanceof Error ? e.message : String(e);
      (purgeStats.errors as string[]).push(`${bucket}_exception:${msg}`);
      console.warn(
        `[delete-account] request_id=${requestId} storage exception bucket=${bucket} (non-fatal):`,
        e,
      );
    }
  }
  return purgeStats;
}
