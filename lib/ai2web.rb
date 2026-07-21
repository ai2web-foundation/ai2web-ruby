# frozen_string_literal: true

# AI2Web (ai2w) Ruby SDK.
#
# Describe your website once. AI2Web makes it understandable to every AI.
#
# Top-level API (all also reachable via their modules):
#   Ai2Web.ai2web(site)                 -> Ai2Web::Manifest   (fluent builder)
#   Ai2Web.validate(manifest)           -> Hash               (AI Readiness score + tier)
#   Ai2Web.negotiate(manifest, agent)   -> Hash               (capability negotiation)
#   Ai2Web.handle(opts, method, path, body, origin) -> Hash   (framework-agnostic router)
#   Ai2Web.validate_schema(value, schema) -> Ai2Web::SchemaResult
#   Ai2Web.safe_public_url?(url) / .assert_safe_public_url!(url) / .same_origin?(a, b)
#   Ai2Web.to_llms_txt(manifest) / .to_agent_json(manifest)   (RFC-0015 projections)
require_relative "ai2web/version"
require_relative "ai2web/util"
require_relative "ai2web/safety"
require_relative "ai2web/schema"
require_relative "ai2web/validator"
require_relative "ai2web/negotiator"
require_relative "ai2web/export"
require_relative "ai2web/manifest"
require_relative "ai2web/server"
require_relative "ai2web/ap2"
require_relative "ai2web/nlweb"
