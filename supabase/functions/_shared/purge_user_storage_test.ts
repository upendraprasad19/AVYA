// Deno tests for _shared/purge_user_storage.ts + _shared/user_owned_buckets.ts
// (single-owner audit 2026-09-26, P0 #6): delete-account must erase every
// user-owned object in EVERY bucket the app writes to — nested paths included
// (OI-32) — and a Storage error in one bucket must not stop the others.
//
// Run: deno test --no-check --allow-all --node-modules-dir=none supabase/functions/_shared/purge_user_storage_test.ts

import { assert, assertEquals } from "https://deno.land/std@0.224.0/assert/mod.ts";
import {
  purgeUserStorage,
  type StorageEntry,
  type StorageLike,
} from "./purge_user_storage.ts";
import { USER_OWNED_BUCKETS } from "./user_owned_buckets.ts";

/**
 * In-memory Storage: bucket → set of full object paths. `failListOn` fails
 * every list in that bucket; `failListAt` fails the list of one exact
 * `bucket/path` folder; `failRemoveOn` fails every remove in that bucket.
 */
function fakeStorage(
  objects: Record<string, string[]>,
  failListOn?: string,
  opts: { failListAt?: string; failRemoveOn?: string } = {},
) {
  const store = new Map<string, Set<string>>();
  for (const [b, paths] of Object.entries(objects)) store.set(b, new Set(paths));
  const storage: StorageLike = {
    from(bucket: string) {
      return {
        list(path: string, { limit, offset }: { limit: number; offset: number }) {
          if (bucket === failListOn || `${bucket}/${path}` === opts.failListAt) {
            return Promise.resolve({ data: null, error: { message: "list failed" } });
          }
          const prefix = path ? `${path}/` : "";
          const children = new Map<string, StorageEntry>();
          for (const p of store.get(bucket) ?? []) {
            if (!p.startsWith(prefix)) continue;
            const rest = p.slice(prefix.length);
            const slash = rest.indexOf("/");
            if (slash < 0) children.set(rest, { name: rest, id: `id-${p}` });
            else children.set(rest.slice(0, slash), { name: rest.slice(0, slash), id: null });
          }
          const page = [...children.values()].slice(offset, offset + limit);
          return Promise.resolve({ data: page, error: null });
        },
        remove(paths: string[]) {
          if (bucket === opts.failRemoveOn) {
            return Promise.resolve({ error: { message: "remove failed" } });
          }
          for (const p of paths) store.get(bucket)?.delete(p);
          return Promise.resolve({ error: null });
        },
      };
    },
  };
  return { storage, store };
}

Deno.test("USER_OWNED_BUCKETS names all five buckets the app writes to", () => {
  assertEquals(
    [...USER_OWNED_BUCKETS].sort(),
    ["avatars", "banners", "chat-media", "coach-media", "progress-photos"],
  );
});

Deno.test("purges every user-owned bucket, nested paths included, and nobody else's objects", async () => {
  const me = "user-a";
  const other = "user-b";
  const objects: Record<string, string[]> = {};
  for (const b of USER_OWNED_BUCKETS) {
    objects[b] = [
      `${me}/top.jpg`,
      `${me}/2026/09/nested.jpg`,
      `${other}/keep.jpg`,
    ];
  }
  const { storage, store } = fakeStorage(objects);
  const stats = await purgeUserStorage(storage, me, USER_OWNED_BUCKETS, "req1");

  for (const b of USER_OWNED_BUCKETS) {
    assertEquals([...store.get(b)!], [`${other}/keep.jpg`], `bucket ${b}`);
    assertEquals(stats[b], 2, `bucket ${b} purge count`);
  }
  assertEquals(stats.errors, []);
});

Deno.test("an error in one bucket is recorded and the remaining buckets are still purged", async () => {
  const me = "user-a";
  const objects: Record<string, string[]> = {};
  for (const b of USER_OWNED_BUCKETS) objects[b] = [`${me}/x.jpg`];
  const { storage, store } = fakeStorage(objects, "chat-media");
  const stats = await purgeUserStorage(storage, me, USER_OWNED_BUCKETS, "req2");

  assert((stats.errors as string[]).some((e) => e.startsWith("chat-media_list:")));
  for (const b of USER_OWNED_BUCKETS) {
    if (b === "chat-media") continue;
    assertEquals(store.get(b)!.size, 0, `bucket ${b} should still be purged`);
  }
});

Deno.test("an empty bucket reports 0, not an error", async () => {
  const { storage } = fakeStorage({});
  const stats = await purgeUserStorage(storage, "user-a", ["avatars"], "req3");
  assertEquals(stats.avatars, 0);
  assertEquals(stats.errors, []);
});

// Hermes 2026-09-26, L37-F1: a failed list must lose only what it could not
// list. Before, one failed subfolder threw out of the listing and discarded
// every path already collected, so a public avatar listed fine was never
// removed while the deletion still reported success.
Deno.test("a failed subfolder list still removes every path that WAS listed", async () => {
  const me = "user-a";
  const { storage, store } = fakeStorage(
    { avatars: [`${me}/avatar.jpg`, `${me}/2026/old.jpg`, "user-b/keep.jpg"] },
    undefined,
    { failListAt: `avatars/${me}/2026` },
  );
  const stats = await purgeUserStorage(storage, me, ["avatars"], "req4");

  assertEquals(
    [...store.get("avatars")!].sort(),
    [`${me}/2026/old.jpg`, "user-b/keep.jpg"],
    "the listed avatar is gone; only the unlistable folder's file remains",
  );
  assertEquals(stats.avatars, 1);
  assertEquals(stats.errors, [`avatars_list:${me}/2026: list failed`]);
});

Deno.test("a remove error is recorded, not counted, and other buckets still purge", async () => {
  const me = "user-a";
  const { storage, store } = fakeStorage(
    { avatars: [`${me}/a.jpg`], banners: [`${me}/b.jpg`] },
    undefined,
    { failRemoveOn: "avatars" },
  );
  const stats = await purgeUserStorage(storage, me, ["avatars", "banners"], "req5");

  assertEquals(stats.avatars, 0, "a failed remove removed nothing");
  assertEquals(stats.banners, 1);
  assertEquals(store.get("banners")!.size, 0);
  assertEquals(stats.errors, ["avatars_rm:remove failed"]);
});

Deno.test("a folder of exactly 1000 and one of 1001 are purged across pages", async () => {
  const me = "user-a";
  const exact = Array.from({ length: 1000 }, (_, i) => `${me}/exact/${i}.jpg`);
  const over = Array.from({ length: 1001 }, (_, i) => `${me}/over/${i}.jpg`);
  const { storage, store } = fakeStorage({ "progress-photos": [...exact, ...over] });
  const stats = await purgeUserStorage(storage, me, ["progress-photos"], "req6");

  assertEquals(store.get("progress-photos")!.size, 0);
  assertEquals(stats["progress-photos"], 2001);
  assertEquals(stats.errors, []);
});
