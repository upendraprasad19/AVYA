---
branch: oi-451-dead-catch
date: 2026-11-03
blast_radius: platform
review_rounds: 2
ground_truth_verified: true
verdict: converged
bpass: accepted
bpass_review: docs/reviews/faa07178cc51-review.md
---

# Plan-review record — OI-451, delete the unreachable catch in land_pr.dart `_out` / `_err`

Plan: option (a) of the OI. Ground truth: a probe (closed stdout, broken pipe, `/dev/full`) showed `stdout.writeln`
never throws synchronously; the failure is an unhandled async `FileSystemException`.

Round 1 (call sites, tests, docs): no P0/P1; widened the residual wording. Round 2 (Dart SDK sink source, board
integrity): no P1; found the flush `_isBound` window, verified in `io_sink.dart`, documented as an accepted residual.
Both rounds ran on the post-previous-round diff. Mutation: restoring the catch in `_out` reddens the new pin.
