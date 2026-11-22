#94.1.0 — integrated AI Coach and student presentation fixes

Owner approved production installation2026-11-22. Manual builder and existing videos remain. AI module requires secure server API key/model and coach enablement/pricing before generation; no paid provider call was made during validation.

Video modal is centered and capped at640px width with video height capped at40dvh/340px (36dvh on narrow screens). This overrides the old global dialog max-width100% rule that made94.0.1 too wide. Close button and safe-area positioning remain shared.

Student exercise technique panel and stats occupy full independent grid rows. Four readable stats on desktop, two columns on mobile; long reps/rest values wrap. Shared StudentExerciseStats is used by the portal and the synthetic responsive QA route.

97 reviewed male clip mappings (up from57), including Standing EZ-Bar Curl. Other exercises without an exact supplied male asset retain their original images; no wrong-equipment fallback is assigned. All290 assets retained.

PDF/PlanPrint rendering files are unchanged. New program layout rules are screen-only. No videos added to PDFs.

Validation: production build passed;177tests passed. Real paid AI quality/latency/billing tests not performed. AI only creates drafts; explicit coach approval/manual transfer retained. Additive8table migration tested on disposable copy before live application. Rollback restores old compose/image, retaining AI audit tables; no down migration is executed.
