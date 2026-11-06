# Optional actual batch output — 2026-10-30

Approved Open bands implementation, in an isolated local candidate. Includes the
complete preceding Fresh Searches working snapshot (including its staged changes),
not just HEAD. No release or installed-app replacement is authorized by this change.

## Behavior

- AFK Weight's Needed batch always shows Actually made. No collapse control.
- Matching flat ingredient/output bands use real 36px artwork, 14px names and
  16px quantities. All existing themes are supported. Ingredient scrolling stays
  separate from the fixed output field and completion controls; larger recipes
  receive more height within the existing viewport limit.
- Blank or zero uses the existing estimated main output. A positive whole amount
  overrides only this batch's main item. German grouped integers are accepted;
  invalid, fractional, negative or >12-digit amounts never silently become valid.
- Below 80% of this batch's unrounded expected main output asks for confirmation
  on Done/Next only. Back preserves the draft; Keep amount explicitly accepts it.
  Editing again clears confirmation. Enter finishes editing, never the batch.
- A changed recipe, goal, remaining amount, completed batch or load capacity clears
  the draft. Successful completion and Undo also clear it. Drafts are not persisted.
- Actual output enters the existing atomic inventory/credit/progress/Undo receipt.
  Ingredients are still consumed for the crafts performed, not scaled to output.
  Actual shortfalls remain queued; extra output is retained. No global forecast,
  mastery, yield, market, profile, schema or ingredient-selection rule changes.
- Existing stale-click, freeze/restart and Undo conflict guards remain in force.
  Main and Bonus use the same completion path, retaining their separate contexts.

## Verification and limits

Actual Flutter application tests use disposable synthetic state, never personal
profiles. Nine full-application cases cover three themes at 1200x752, 960x600 and
200% text, with exact output, low confirmation/cancel, zero/default, invalid
input, capacity-change reset and Undo. Real cooking/alchemy catalog checks cover
ordinary/enlarged multi-ingredient layouts and unchanged mastery forecasts.
Controller tests cover shortfalls, overproduction, ignore-owned modes, shared
inventory, intermediate queues, reload, stale clicks, frozen mutations and Undo.

Focused static analysis and a separate Windows Release build pass. The wider
default Planner suite has 18 pre-existing failures across inventory-input,
NPC-recipe-workflow, owned-trial and content-size tests. All 18 reproduce with the
same identities on a hash-verified independent copy of Fresh Searches. Those four
files were not changed here; their failures are not claimed fixed. The remaining
regression run and final counts are recorded in the audit result. Existing
Gathering/Recipe Book findings from previous candidates also remain out of scope.
Actual in-game calibration and secondary/byproduct tracking are not implemented.

## Preservation and delivery

Source: `[private-source]/Actual Batch Output 20261030`
Branch: `codex/actual-batch-output`; full staged working tree is the candidate.
Runnable: `build/windows/x64/runner/Release/BlackSpiritLife.exe` (keep its full folder).
Previous source and full runnable were copied and hash-verified at
`[private-source]/Protected Rollback/prior-actual-batch-20261030-OECz7A`.
Baseline manifest SHA-256:
`6BB0E4589F5AD15B3584D33D4FEB2A0F94348ED389F595BC2A03369CE547F3EF`.
The original was freshly reverified unchanged after implementation.

Workspace audit: `audit/actual-batch-output-20261030`.
Actual-app captures: `work/visuals/actual-batch-output`.
No visible application launch, profile access, shortcut change, installed-app
replacement, Live Release handoff or GitHub publication. User review remains
separate. Publishing still belongs to Live Release under the release contract.
