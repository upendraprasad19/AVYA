---
title: supabase_flutter functions.invoke throws on non-2xx
category: bug-classes
source_memory: feedback_function_exception_class.md
last_reviewed: 2026-05-28
---

# supabase_flutter functions.invoke throws on non-2xx

## The class

In `supabase_flutter ^2.12.0` (and its 2.x line), `SupabaseClient.functions.invoke()` THROWS `FunctionException` for any non-2xx HTTP response. Control jumps to the catch block; the `FunctionResponse` returned to the try block is only populated for 2xx responses.

**Consequence:** inline `if (resp.status == X)` checks inside the try block are DEAD CODE for non-2xx paths. Detection must move to the catch block, parsing `e.status` and `e.details`.

## How to detect

- Edge Function logs prove the function returned a non-2xx status with a meaningful body.
- User still sees the generic "Couldn't start payment" / "Something went wrong" toast.
- Tracing the catch block reveals it ran generic error handling, ignoring the function's specific status code.
- Inline non-2xx branches inside the try block have never executed (test their reachability via debug print or coverage).

## Prevention

1. **In the catch block, detect FunctionException specifically:**

   ```dart
   try {
     final resp = await SupabaseService.instance.callFunction('fn', body: {...});
     if (resp.status != 200) { /* may be unreachable in practice */ }
   } catch (e) {
     if (e is FunctionException) {
       final status = e.status;
       final details = e.details; // dynamic — usually Map of the JSON body
       // Branch on status + details fields here.
     }
     // Fall through to generic error handling.
   }
   ```

2. **Audit every callsite** of `client.functions.invoke()` (or wrapping `SupabaseService.callFunction()`) for inline non-2xx checks inside the try block. Known callsites to sweep:

   - `lib/core/services/razorpay_service.dart` (order creation, verify-payment polling).
   - `lib/core/services/ai_service.dart` (chat, food analysis).
   - `validate-promo` callers.
   - `redeem-referral` caller.
   - `verify-subscription` (`subscription_service.dart`).

3. **Regression test pattern** — for every Edge Function that returns documented non-200 status codes (409 already_pro, 429 rate-limit, 401 auth), add a contract test asserting the client's catch block parses `FunctionException` for those statuses. Template: `test/contracts/razorpay_409_already_pro_test.dart`.

4. **Wrapper concerns** — `SupabaseService.callFunction` does not currently wrap or normalize this behavior; it just returns / throws whatever `client.functions.invoke()` does. If the wrapper is ever standardized to convert `FunctionException` into `FunctionResponse-with-status`, every existing catch block needs audit too.

## Instances

`create-razorpay-order` Edge Function's 409 already_pro path had been deployed with a client-side handler at `razorpay_service.dart:105` (`if (resp.status == 409)`). Server logs proved the function was returning 409 correctly. The user still got the generic "Couldn't start payment" toast. Tracing the catch block at line 153 caught the `FunctionException`, ran `_showOrderCreationFailure`. The 409 branch had been DEAD CODE for ~2 weeks. The user paid 4 times in 24h because the misleading toast told him to "check connection and try again" while the server kept correctly blocking.

## References

- Related: [`writer-reader-drift.md`](writer-reader-drift.md) (this is a writer-to-client-contract variant — server emits a documented status, client never reads it).
