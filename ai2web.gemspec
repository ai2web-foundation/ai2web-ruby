# frozen_string_literal: true

require_relative "lib/ai2web/version"

Gem::Specification.new do |spec|
  spec.name = "ai2web"
  spec.version = Ai2Web::VERSION
  spec.authors = ["AI2Web Foundation"]

  spec.summary = "AI2Web (ai2w) Ruby SDK - capability model, manifest builder, validator, negotiation, server handler."
  spec.description = "The Ruby implementation of the AI2Web protocol - describe your website once and make it " \
                     "understandable and actionable to any AI agent. Fluent manifest builder, AI Readiness " \
                     "validator/scorer, capability negotiation, a framework-agnostic request handler for " \
                     "Rails/Sinatra/Rack, an SSRF guard, and llms.txt / agent.json projections (RFC-0015). " \
                     "Mirrors @ai2web/core. Zero runtime dependencies."
  spec.homepage = "https://ai2web.dev"
  spec.license = "MIT"
  spec.required_ruby_version = ">= 3.0"

  spec.metadata = {
    "homepage_uri" => "https://ai2web.dev",
    "source_code_uri" => "https://github.com/ai2web-foundation/ai2web-ruby",
    "changelog_uri" => "https://github.com/ai2web-foundation/ai2web-ruby/blob/main/CHANGELOG.md",
    "bug_tracker_uri" => "https://github.com/ai2web-foundation/ai2web-ruby/issues",
    "documentation_uri" => "https://ai2web.dev/docs",
    "rubygems_mfa_required" => "true"
  }

  spec.files = Dir["lib/**/*.rb", "README.md", "LICENSE", "CHANGELOG.md"]
  spec.require_paths = ["lib"]
end
