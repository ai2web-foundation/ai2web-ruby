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
  end

  module_function

  def to_llms_txt(manifest) = Export.to_llms_txt(manifest)
  def to_agent_json(manifest) = Export.to_agent_json(manifest)
end
