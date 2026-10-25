# Replaceable ORYUKDO LSQ

`oryukdo_scheduler.CUSTOM_LSQ` defaults to `0`: the existing `oryukdo_memory`
implementation handles internal forwarding, ordered publication and recovery.
Set it to `1` to instantiate **only** `oryukdo_custom_lsq` in its place.
This is a memory-engine replacement, not a bypass of ordering or recovery.

Copy `gen2/examples/custom_lsq/oryukdo_custom_lsq.sv` into your build. It is a
working starter that delegates to the built-in engine. Replace its body with
your RTL or an adapter to your own module. Compile exactly one definition of
`oryukdo_custom_lsq`; the starter is outside `src/RTL` deliberately. No custom
module is needed with `CUSTOM_LSQ=0`. The original EULSUKDO modules are unchanged.

## Interface contract

The starter contains the complete parameter/port declarations. `DEPTH` is the
frontier slot count, not a mandatory size for your internal queue. Tokens are
`{generation, slot}`, with `SLOT_W=max(1,clog2(DEPTH))`. Never truncate generation.

* `i_reserve` previews the pending decode bundle, in lane/program order.
  `i_memory/i_store` classify its lanes. Return `o_allocate_ready` only if the
  entire selected bundle can be accepted. This is **not** an allocation event.
  Capacity must accommodate at least one legal decode bundle to make progress.
* `i_allocate` marks actual acceptance on the clock edge. Record only these
  lanes, using `i_token`; it includes non-memory instructions as well. Tokens
  are valid for allocation only: **do not derive readiness from `i_allocate`
  or `i_token`**, as they depend on admission. Readiness may depend on preview
  classes and registered capacity. Keep preview free of side effects.
* Allocation backpressure also seals an existing partial window, letting older
  instructions retire and free capacity. The decode buffer holds the next
  bundle. A flush cancels both that bundle and speculative LSQ entries.
* AGU acceptance is `i_agu_valid && o_agu_ready`. Valid remains visible while
  the user LSQ stalls; the scheduler filters stale/unissued/already-queued tokens.
  Accept once and preserve address/data/mask, nonspec flag and fault/cause.
* Report non-speculative access classification on `o_serial_valid/token` at
  AGU acceptance. Side-effecting loads and MMIO must wait for the ordered head
  (`i_head_valid/token`). Keep the bus transaction serialized: the external
  response interface has no transaction IDs.
* Hold `o_complete_valid/token/data/fault/cause` until `i_complete_accept`.
  A normal store completes internally before publication; this lets frontier
  validate the window. Publish stores only with the matching
  `i_commit_valid && i_commit_store` authorization. `o_commit_ready` permits
  retirement after publication succeeds; it must not obstruct non-store
  retirement. Non-speculative stores may execute at the ordered head before
  completion, following the built-in protocol. `i_retire/i_commit_token` frees
  the retired entry.
* Preserve load/store order and byte forwarding semantics. On store bus error,
  report `o_store_fault/token/cause` precisely; do not publish a failed store.
  The memory system must not partially expose a faulting store.
* Hold bus requests/payload while stalled. Consume responses with
  `i_response_valid && o_response_ready`. On flush, invalidate speculative work
  but drain outstanding bus transactions without confusing their responses
  with a new generation. Never write a canceled result or repeat a store.

The custom interface deliberately replaces the whole memory service. A simple
FIFO-only LSQ needs an adapter implementing these obligations.

## Validation

`python3 gen2/src/TB/run_oryukdo.py` exercises both built-in and custom modes.
The test-only custom module wraps the reference implementation and injects
allocation/AGU stalls, checks window draining, WBC during a stall, and flush of
unallocated work. The full recovery, forwarding, MMIO, fault, stale-response,
CSR and register-wakeup regression runs through both choices and predictors.
Do not compile the test module and the example starter together.

Existing 70 MHz FPGA results belong to commit `844267f`; they are historical
measurements, not timing validation of this hook or any user implementation.
