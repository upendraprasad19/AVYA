import { assertEquals, assertStringIncludes } from "https://deno.land/std@0.224.0/testing/asserts.ts";
import { composeCongrats } from "./congrats.ts";

const CTX = {
  full_name: "Rahul Sharma",
  total_workouts_done: 34,
  current_streak_weeks: 6,
  primary_goal: "build_muscle",
};

Deno.test("composeCongrats: variant 0 uses the approved copy, interpolated", () => {
  const msg = composeCongrats(CTX, "LS", 0);
  assertEquals(
    msg,
    "Rahul — you've been promoted to Leading Seaman. 34 sessions and a 6-week streak got you here. Every rung on this ladder is earned, not given. Keep training toward muscle gain — the next rank is already waiting.",
  );
});

Deno.test("composeCongrats: variant 1 uses the approved copy", () => {
  const msg = composeCongrats(CTX, "LS", 1);
  assertStringIncludes(msg, "Well earned, Rahul. Leading Seaman now");
});

Deno.test("composeCongrats: variant 2 uses the approved copy (with the founder's edit applied)", () => {
  const msg = composeCongrats(CTX, "LS", 2);
  assertStringIncludes(msg, "Rahul, your new rank: Leading Seaman.");
  // The approved edit dropped the word "report" — pin its absence so a
  // regression can't silently reintroduce the pre-edit wording.
  if (msg.includes("report your new rank")) {
    throw new Error("expected the approved edit (dropped 'report') to be present");
  }
});

Deno.test("composeCongrats: unknown rank code falls back to the raw code as the label", () => {
  const msg = composeCongrats(CTX, "ZZZ", 0);
  assertStringIncludes(msg, "promoted to ZZZ");
});

Deno.test("composeCongrats: null full_name falls back to 'soldier'", () => {
  const msg = composeCongrats({ ...CTX, full_name: null }, "LS", 0);
  assertStringIncludes(msg, "soldier —");
});

Deno.test("composeCongrats: with no variantIndex given, still returns one of the 3 approved variants deterministically", () => {
  const a = composeCongrats(CTX, "LS");
  const b = composeCongrats(CTX, "LS");
  assertEquals(a, b, "same ctx + rankCode with no explicit variantIndex must be deterministic, not random per call");
});

Deno.test("proactive-coach-promotion no longer calls Gemini — no fetch to generativelanguage.googleapis.com", async () => {
  const src = await Deno.readTextFile(new URL("./index.ts", import.meta.url));
  if (src.includes("generativelanguage.googleapis.com")) {
    throw new Error("expected the raw Gemini fetch endpoint to be gone from proactive-coach-promotion/index.ts");
  }
  if (src.includes("GEMINI_API_KEY")) {
    throw new Error("expected the now-unused GEMINI_API_KEY reference to be removed");
  }
});

Deno.test("the ai_coach_interactions insert no longer mislabels model_used as gemini-2.5-flash, since composeCongrats is now template-only", async () => {
  const src = await Deno.readTextFile(new URL("./index.ts", import.meta.url));
  if (src.includes('model_used: "gemini-2.5-flash"')) {
    throw new Error(
      'expected model_used: "gemini-2.5-flash" to be gone — composeCongrats no longer calls ' +
        "Gemini, so this mislabels every promotion event in any future audit that greps model_used",
    );
  }
  if (!src.includes('model_used: "congrats_template"')) {
    throw new Error(
      'expected model_used: "congrats_template" — matching the sibling convention in ' +
        'evaluate-rank-promotions ("ceremony_template") and i-see-you-callout ("i_see_you_template")',
    );
  }
});

// ── 8b1f3d: the floor rung is never announced (behavioural, via handler seam) ──
// Importing index.ts binds no server (serve() sits under import.meta.main) and
// reads no env at module scope. Auth is the real isAuthorizedCronCall: the
// CRON_SECRET escape hatch, set per test and restored.
import { handler } from "./index.ts";

const SECRET = "test-cron-secret-promo-1234567890abcdef";

// deno-lint-ignore no-explicit-any
function fakeAdmin(): { admin: any; inserts: Array<{ table: string; row: any }> } {
  // deno-lint-ignore no-explicit-any
  const inserts: Array<{ table: string; row: any }> = [];
  const admin = {
    from(table: string) {
      // deno-lint-ignore no-explicit-any
      const b: any = {};
      b.select = () => b;
      b.eq = () => b;
      b.maybeSingle = () => Promise.resolve({ data: null, error: null });
      b.insert = (row: unknown) => {
        inserts.push({ table, row });
        return Promise.resolve({ error: null });
      };
      return b;
    },
  };
  return { admin, inserts };
}

async function call(rankCode: string) {
  const prev = Deno.env.get("CRON_SECRET");
  Deno.env.set("CRON_SECRET", SECRET);
  const { admin, inserts } = fakeAdmin();
  let adminCreated = 0;
  let prefsRead = 0;
  const pushes: string[] = [];
  const origLog = console.log;
  console.log = () => {};
  try {
    const res = await handler(
      new Request("https://example.test/fn", {
        method: "POST",
        headers: { Authorization: `Bearer ${SECRET}` },
        body: JSON.stringify({ user_id: "u-1", rank_code: rankCode }),
      }),
      {
        createAdmin: () => {
          adminCreated++;
          return admin;
        },
        fetchPrefs: (() => {
          prefsRead++;
          return Promise.resolve(new Map());
          // deno-lint-ignore no-explicit-any
        }) as any,
        sendPush: (_u: string, code: string) => {
          pushes.push(code);
          return Promise.resolve();
        },
      },
    );
    return { status: res.status, body: await res.json(), inserts, adminCreated, prefsRead, pushes };
  } finally {
    console.log = origLog;
    if (prev === undefined) Deno.env.delete("CRON_SECRET");
    else Deno.env.set("CRON_SECRET", prev);
  }
}

Deno.test("8b1f3d: a floor (SD2) payload -> 200 skipped, no client, no prefs read, no chat row, no push", async () => {
  const r = await call("SD2");
  assertEquals(r.status, 200);
  assertEquals(r.body, { ok: true, skipped: "floor" });
  assertEquals(r.adminCreated, 0);
  assertEquals(r.prefsRead, 0);
  assertEquals(r.inserts.filter((i) => i.table === "ai_coach_interactions").length, 0);
  assertEquals(r.pushes, []);
});

Deno.test("8b1f3d mirror: an SD1 payload -> one chat row + one push", async () => {
  const r = await call("SD1");
  assertEquals(r.status, 200);
  assertEquals(r.body, { ok: true });
  const chat = r.inserts.filter((i) => i.table === "ai_coach_interactions");
  assertEquals(chat.length, 1);
  assertEquals(chat[0].row.tool_calls.rank_code, "SD1");
  assertEquals(r.pushes, ["SD1"]);
});

Deno.test("8b1f3d: an unauthenticated floor payload is still a 401 (auth runs first)", async () => {
  const res = await handler(
    new Request("https://example.test/fn", {
      method: "POST",
      body: JSON.stringify({ user_id: "u-1", rank_code: "SD2" }),
    }),
    {
      createAdmin: () => {
        throw new Error("must not be called");
      },
      // deno-lint-ignore no-explicit-any
      fetchPrefs: (() => Promise.reject(new Error("must not be called"))) as any,
      sendPush: () => Promise.reject(new Error("must not be called")),
    },
  );
  assertEquals(res.status, 401);
});
