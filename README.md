<div align="center">
  <a href="https://ai2web.dev">
    <picture>
      <source media="(prefers-color-scheme: dark)" srcset="https://raw.githubusercontent.com/ai2web-foundation/.github/main/profile/ai2web-logo-white.svg">
      <img alt="AI2Web" src="https://raw.githubusercontent.com/ai2web-foundation/.github/main/profile/ai2web-logo-black.svg" width="200">
    </picture>
  </a>
</div>

# AI2Web Ruby SDK (`ai2web`)

[![CI](https://github.com/ai2web-foundation/ai2web-ruby/actions/workflows/ci.yml/badge.svg)](https://github.com/ai2web-foundation/ai2web-ruby/actions/workflows/ci.yml)
[![Gem Version](https://img.shields.io/gem/v/ai2web)](https://rubygems.org/gems/ai2web)

The Ruby reference implementation of the [AI2Web protocol](https://github.com/ai2web-foundation/ai2web-spec) - for Rails, Sinatra, Rack, or plain Ruby. Mirrors `@ai2web/core`.

```bash
gem install ai2web
# or add to your Gemfile:
gem "ai2web"
```

```ruby
require "ai2web"

manifest = Ai2Web.ai2web(name: "Example Store", url: "https://example.com", type: "ecommerce")
  .capability("content")
  .capability("commerce", endpoint: "/ai2w/products", checkout: true)
  .transports(mcp: { enabled: true, endpoint: "/ai2w/mcp" }, rest: { enabled: true })
  .auth(methods: %w[none oauth2], oauth2: { pkce: true, scopes: ["checkout"] })
  .consent(requires_user_approval_for: ["purchase"])
  .contact(support: "help@example.com")
  .build

result = Ai2Web.validate(manifest)   # { score: 90+, tier: "Standard", ... }

# Serve every AI2Web route from one call (framework-agnostic):
res = Ai2Web.handle({ manifest: manifest }, request.method, request.path, body, origin)
# => { status:, headers:, body: }  -- render body as JSON (or text for /llms.txt)
```

Inputs may use **symbol or string keys** - the builder normalises to the string-keyed JSON the
spec defines, so `validate` also works directly on a `JSON.parse`d manifest.

## Modules

| Module | Entry points |
| --- | --- |
| `Ai2Web::Manifest` | `Ai2Web.ai2web(site)` - fluent capability-model builder |
| `Ai2Web::Validator` | `Ai2Web.validate(manifest)` + AI Readiness scoring (spec §9/§11) |
| `Ai2Web::Negotiator` | `Ai2Web.negotiate(manifest, agent)` capability negotiation (spec §5) |
| `Ai2Web::Server` | `Ai2Web.handle(opts, method, path, body, origin)` framework-agnostic router |
| `Ai2Web::Safety` | `Ai2Web.safe_public_url?(url)` / `.assert_safe_public_url!(url)` SSRF guard |
| `Ai2Web::Schema` | `Ai2Web.validate_schema(value, schema)` action input validation |
| `Ai2Web::Export` | `Ai2Web.to_llms_txt(m)` / `.to_agent_json(m)` projections (RFC-0015) |

The builder also carries the v0.2 optional modules - `.governance(...)`, `.usage_policy(...)`,
`.legal(...)`, `.agent_identity(...)`, `.knowledge(...)` - and actions accept `intent` and
`bindings`. All are additive: a minimal manifest stays valid without them.

### Serving from Rack / Sinatra

```ruby
res = Ai2Web.handle({ manifest: MANIFEST, actions: { "track_order" => ->(body) { track(body) } } },
                    env["REQUEST_METHOD"], env["PATH_INFO"], parsed_body, request_origin)

body = res[:body].is_a?(String) ? res[:body] : JSON.generate(res[:body])
[res[:status], res[:headers], [body]]
```

`handle` routes `/ai2w`, `/.well-known/ai2w`, `/llms.txt`, `/.well-known/agent.json` (+ `/agent.json`),
`/ai2w/negotiate`, `/ai2w/actions/:name` and capability modules `/ai2w/:name`, validating action
input against each action's declared `input_schema` unless you pass `validate_input: false`.

## Test

```bash
ruby test/run.rb     # dependency-free; includes the shared conformance contract
```

Requires **Ruby 3.0+**. Zero runtime dependencies.

## Licence

MIT.
