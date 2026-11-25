# Power Home Coach 94.1.2 — simple AI composer

The coach program builder now starts with an athlete selector and two choices: write manually or write with AI. Both modes stay available; switching methods preserves the manual plan and keeps an opened AI form mounted. Changing athlete or starting a new cycle resets the choice and binds the form to that athlete.

AI begins with a short coach brief: program sections, intake age/height/weight, goal, sessions, split, training system, day titles, equipment, meals and optional calories, health restrictions, and selected body photos. Existing detailed controls remain under optional advanced settings. No generation starts until the coach presses Start. Outputs remain reviewable drafts and require explicit approval before transfer into the manual editor; publication still uses the existing Send action.

Intake body photographs are now available alongside existing progress photographs. Receipts, labs and other athletes' uploads are excluded. Existing separate athlete consent gates remain in force. Names are shown in the coach UI; the provider receives the selected athletic profile, not contact details.

API connection can be configured under Program Builder > AI > Connection and API key. The key is encrypted at rest using the existing server encryption mechanism. Authenticated, same-origin writes only; responses expose configuration flags and model, never the key. Empty key preserves a previously stored key when changing the model. Existing environment configuration remains the fallback. A generation captures its key/model before sending, so connection edits cannot silently change its model mid-request. Model pricing, monthly limits and enablement remain coach controlled; no paid calls were made for validation.

Adds an opt-in additive ai_credentials table. Deployment must back up the current SQLite DB and source before activation. Existing manual builder, PlanPrint and PDF exporter are unchanged. Existing 147 reviewed exercise mappings and 318 clips are retained; this release adds no new video assets.

Validation: production build and all 181 tests passed, including encryption/no-readback, authorization/CSRF, model-only credential updates, scoped intake/photo selection and draft/manual-state preservation. Browser visual QA is pending access to a reachable preview; the browser could not reach the local test server. Production deployment is pending renewed hosting authentication; do not describe this release as installed until the live release marker is verified.
