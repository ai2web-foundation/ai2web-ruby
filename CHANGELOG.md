# Changelog

All notable changes to the AI2Web Ruby SDK are documented here. Versioning is independent per
language SDK; this SDK targets the AI2Web **v0.2** manifest and mirrors `@ai2web/core`.

## [0.1.0] - 2026-07-19

Initial release. Full parity with the Python/TypeScript reference SDKs, verified against the shared
conformance contract (`test/conformance_cases.json`).

- Fluent manifest builder (`Ai2Web.ai2web`) incl. the v0.2 optional modules (`governance`,
  `usage_policy`, `legal`, `agent_identity`, `knowledge`) and action `intent` / `bindings`.
- AI Readiness validator + scorer (`Ai2Web.validate`), spec §9/§11.
- Capability negotiation (`Ai2Web.negotiate`), spec §5.
- Framework-agnostic request handler (`Ai2Web.handle`) with action input-schema validation.
- SSRF guard (`Ai2Web.safe_public_url?` / `.assert_safe_public_url!` / `.same_origin?`).
- JSON-Schema-subset validator (`Ai2Web.validate_schema`).
- `llms.txt` and `agent.json` projections (`Ai2Web.to_llms_txt` / `.to_agent_json`), RFC-0015.
- Zero runtime dependencies; requires Ruby 3.0+.
