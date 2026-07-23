# frozen_string_literal: true

module Ai2Web
  # Export adapters (RFC-0015): project the one canonical AI2Web manifest into other wire formats
  # and discovery surfaces. Port of @ai2web/core export.ts.
  #
  # Each export is a best-effort projection; where a target cannot represent a field, it is omitted
  # rather than misstated. The canonical /ai2w manifest stays authoritative for execution.
  module Export
    module_function

    def enabled_capabilities(m)
      caps = m["capabilities"].is_a?(Hash) ? m["capabilities"] : {}
      caps.select { |_k, v| Util.enabled?(v) }.keys
    end

    # Project the manifest to an `llms.txt` document: a plain-text summary and set of links a model
    # can read for content and guidance. Reads only; no actions are exposed here.
    def to_llms_txt(manifest)
      m = Util.deep_stringify(manifest)
      site = m["site"].is_a?(Hash) ? m["site"] : {}
      base = Util.trim_url(site["url"].to_s)
      lines = ["# #{site["name"]}"]
      lines += ["", "> #{site["description"]}"] if Util.truthy?(site["description"])

      caps = enabled_capabilities(m)
      lines += ["", "## Capabilities", *caps.map { |c| "- #{c}" }] unless caps.empty?

      knowledge = m["knowledge"].is_a?(Array) ? m["knowledge"] : []
      unless knowledge.empty?
        lines << ""
        lines << "## Knowledge"
        knowledge.each do |k|
          ref = k["ref"].to_s
          ref = base + (ref.start_with?("/") ? "" : "/") + ref unless ref.start_with?("http")
          lines << "- [#{k["name"] || k["id"]}](#{ref})"
        end
      end

      actions = m["actions"].is_a?(Array) ? m["actions"] : []
      unless actions.empty?
        lines << ""
        lines << "## Actions"
        actions.each { |a| lines << "- #{a["name"]}: #{a["description"]}" }
      end

      lines += ["", "## Discovery", "- Manifest: #{base}/ai2w"]
      "#{lines.join("\n")}\n"
    end

    # Project the manifest to a generic `agent.json` style capability document. Best-effort,
    # format-neutral projection of identity, capabilities, actions (with bindings), knowledge and
    # policies. Consent/governance a target cannot express are carried as a `policies` object
    # rather than dropped silently.
    def to_agent_json(manifest)
      m = Util.deep_stringify(manifest)
      site = m["site"].is_a?(Hash) ? m["site"] : {}
      actions = m["actions"].is_a?(Array) ? m["actions"] : []
      consent = m["consent"].is_a?(Hash) ? m["consent"] : {}
      {
        "schema" => "agent-capabilities",
        "name" => site["name"],
        "description" => site["description"],
        "url" => site["url"],
        "identity" => m["identity"],
        "capabilities" => enabled_capabilities(m),
        "actions" => actions.map do |a|
          bindings = a["bindings"].is_a?(Array) && !a["bindings"].empty? ? a["bindings"] : [{ "kind" => "rest", "ref" => a["endpoint"] }]
          {
            "name" => a["name"],
            "intent" => a["intent"],
            "description" => a["description"],
            "risk" => a["risk"],
            "requires_consent" => a["requires_user_approval"],
            "requires_auth" => a["requires_auth"],
            "input_schema" => a["input_schema"],
            "bindings" => bindings
          }
        end,
        "knowledge" => m["knowledge"],
        "transports" => m["transports"],
        "policies" => {
          "consent" => consent["requires_user_approval_for"],
          "governance" => m["governance"],
          "usage" => m["usage_policy"],
          "legal" => m["legal"]
        }
      }
    end

    # OAuth 2.0 Protected Resource metadata (RFC 9728), for
    # /.well-known/oauth-protected-resource. MCP clients read this to discover which
    # authorization server guards the resource before starting a flow.
    #
    # Returns nil when the site does not advertise oauth2, so an auth surface the site cannot
    # honour is never published.
    def to_oauth_protected_resource(manifest)
      m = Util.deep_stringify(manifest)
      auth = m["auth"].is_a?(Hash) ? m["auth"] : {}
      return nil unless Array(auth["methods"]).include?("oauth2")

      site = m["site"].is_a?(Hash) ? m["site"] : {}
      base = Util.trim_url(site["url"].to_s)
      oauth2 = auth["oauth2"].is_a?(Hash) ? auth["oauth2"] : {}
      issuer = base
      authz = oauth2["authorization_url"].to_s
      unless authz.empty?
        begin
          u = URI.parse(authz)
          issuer = "#{u.scheme}://#{u.host}#{u.port && ![80, 443].include?(u.port) ? ":#{u.port}" : ""}" if u.scheme && u.host
        rescue URI::InvalidURIError
          # keep the site base as issuer
        end
      end
      doc = {
        "resource" => "#{base}/ai2w",
        "authorization_servers" => [issuer],
        "bearer_methods_supported" => ["header"]
      }
      scopes = oauth2["scopes"]
      doc["scopes_supported"] = Array(scopes) if scopes && !Array(scopes).empty?
      doc
    end

    # Map usage_policy onto Content Signals tokens. `search` stays yes because AI2Web exists to
    # be discoverable; the AI signals are only asserted when the manifest states them, so an
    # unset policy is never reported as a refusal. Nil when no policy is declared.
    def to_content_signals(manifest)
      m = Util.deep_stringify(manifest)
      p = m["usage_policy"]
      return nil unless p.is_a?(Hash) && !p.empty?

      signals = ["search=yes"]
      signals << "ai-input=#{p["content_reproduction"] ? "yes" : "no"}" if [true, false].include?(p["content_reproduction"])
      signals << "ai-train=#{p["model_training"] ? "yes" : "no"}" if [true, false].include?(p["model_training"])
      signals.join(", ")
    end

    # A robots.txt FRAGMENT carrying the usage policy and a pointer to the manifest. Append it to
    # an existing robots.txt; it is never a replacement, and emits no Disallow rules.
    def to_robots_txt(manifest)
      m = Util.deep_stringify(manifest)
      site = m["site"].is_a?(Hash) ? m["site"] : {}
      base = Util.trim_url(site["url"].to_s)
      lines = ["# AI2Web usage policy, projected from #{base}/ai2w", "User-agent: *"]
      signals = to_content_signals(m)
      lines << "Content-Signal: #{signals}" unless signals.nil?
      lines << "# bulk_extraction: false - please use the /ai2w endpoints instead of crawling" if
        m["usage_policy"].is_a?(Hash) && m["usage_policy"]["bulk_extraction"] == false
      lines << "# AI2Web-Manifest: #{base}/ai2w"
      "#{lines.join("\n")}\n"
    end

    # Value for an HTTP Link header advertising the manifest to non-HTML clients.
    def to_discovery_link_header(manifest)
      m = Util.deep_stringify(manifest)
      site = m["site"].is_a?(Hash) ? m["site"] : {}
      "<#{Util.trim_url(site["url"].to_s)}/ai2w>; rel=\"ai2w\""
    end
  end

  module_function

  def to_llms_txt(manifest) = Export.to_llms_txt(manifest)
  def to_agent_json(manifest) = Export.to_agent_json(manifest)
  def to_oauth_protected_resource(manifest) = Export.to_oauth_protected_resource(manifest)
  def to_content_signals(manifest) = Export.to_content_signals(manifest)
  def to_robots_txt(manifest) = Export.to_robots_txt(manifest)
  def to_discovery_link_header(manifest) = Export.to_discovery_link_header(manifest)
end
