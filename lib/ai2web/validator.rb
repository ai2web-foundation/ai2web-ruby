# frozen_string_literal: true

module Ai2Web
  # AI2Web validation + AI Readiness scoring.
  #
  # Port of @ai2web/core validateManifest (spec sections 9 & 11). MUST stay in exact parity with
  # the TypeScript reference and ai2web-spec/conformance/cases.json.
  #
  # {Ai2Web.validate} returns a Hash:
  #   { valid: Boolean, errors: [String], checks: [{ ok:, points:, label:, hint: }],
  #     score: Integer (0..100), tier: "Invalid"|"Basic"|"Standard"|"Enterprise" }
  module Validator
    VERSION_RE = /\A\d+\.\d+(\.\d+)?\z/.freeze

    module_function

    def validate(manifest)
      m = Util.deep_stringify(manifest)
      errors = []
      checks = []
      caps = m["capabilities"].is_a?(Hash) ? m["capabilities"] : {}
      cap = ->(name) { caps[name] }

      errors << "protocol must be 'ai2w'" if m["protocol"] != "ai2w"
      errors << "version missing/invalid" unless VERSION_RE.match?(m["version"].to_s)
      site = m["site"].is_a?(Hash) ? m["site"] : {}
      %w[name url type].each { |k| errors << "site.#{k} missing" unless Util.truthy?(site[k]) }
      errors << "capabilities empty" unless caps.is_a?(Hash) && !caps.empty?

      actions_exist =
        Util.enabled?(cap.call("actions")) ||
        (m["actions"].is_a?(Array) && !m["actions"].empty?) ||
        Util.enabled?(cap.call("commerce")) ||
        Util.enabled?(cap.call("booking"))

      score = 0
      add = lambda do |ok, points, label, hint|
        checks << { ok: ok, points: points, label: label, hint: ok ? nil : hint }
        score += points if ok
      end

      add.call(errors.empty?, 30, "Valid discovery manifest", "fix errors")
      add.call(Util.enabled?(cap.call("content")), 6, "Content", "expose content module")
      add.call(Util.enabled?(cap.call("commerce")) || Util.enabled?(cap.call("booking")) || Util.enabled?(cap.call("services")), 6,
               "Products / services / booking", "expose a commerce/services/booking module")
      add.call(Util.enabled?(cap.call("search")), 4, "Search", "add a search capability")
      add.call(actions_exist, 5, "Actions", "declare actions")
      add.call(Util.enabled?(cap.call("events")), 6, "Events / subscriptions", "publish subscribable events")
      agent_service = m["agent_service"].is_a?(Hash) ? m["agent_service"] : {}
      add.call(Util.truthy?(agent_service["enabled"]), 4, "Agent service (A2A)", "expose /ai2w/agent")

      commerce = cap.call("commerce")
      add.call(!Util.enabled?(commerce) || (commerce.is_a?(Hash) && commerce["checkout"] == true),
               4, "Checkout", "commerce present but checkout missing")

      transports = m["transports"].is_a?(Hash) ? m["transports"] : {}
      mcp = transports["mcp"].is_a?(Hash) ? transports["mcp"] : {}
      rest = transports["rest"].is_a?(Hash) ? transports["rest"] : {}
      add.call(mcp["enabled"] == true, 8, "MCP transport", "expose an MCP endpoint")
      add.call(rest["enabled"] == true || Util.truthy?(transports["feeds"]), 4, "REST / feeds", "expose REST or feeds")

      auth = m["auth"].is_a?(Hash) ? m["auth"] : {}
      oauth2 = auth["oauth2"].is_a?(Hash) ? auth["oauth2"] : {}
      oauth_ok = (auth["methods"] || []).include?("oauth2") && oauth2["pkce"] == true
      consent = m["consent"].is_a?(Hash) ? m["consent"] : {}
      consent_declared = ((consent["requires_user_approval_for"]) || []).length.positive?
      add.call(!actions_exist || oauth_ok, 8, "OAuth2 + PKCE", "protected actions need oauth2+pkce")
      add.call(!actions_exist || consent_declared, 7, "Consent declared", "declare consent for sensitive actions")

      add.call(Util.truthy?(m["identity"]), 4, "Identity", "add identity (legal_name, policies)")
      add.call(Util.truthy?(m["contact"]), 4, "Contact", "add support/security contact")

      score = [100, score].min

      basic = errors.empty?
      standard = basic && Util.truthy?(m["transports"]) && (!actions_exist || consent_declared) && Util.truthy?(m["contact"])
      enterprise = standard && Util.truthy?(m["identity"]) && Util.truthy?(m["auth"]) && Util.truthy?(m["rate_limits"])
      tier = if enterprise then "Enterprise"
             elsif standard then "Standard"
             elsif basic then "Basic"
             else "Invalid"
             end

      { valid: errors.empty?, errors: errors, checks: checks, score: score, tier: tier }
    end
  end

  module_function

  def validate(manifest) = Validator.validate(manifest)
end
