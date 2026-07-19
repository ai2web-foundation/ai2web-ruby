# frozen_string_literal: true

module Ai2Web
  # Capability negotiation (spec section 5). Port of @ai2web/core negotiate().
  module Negotiator
    module_function

    def endpoint_of(name, value)
      return value["endpoint"] if value.is_a?(Hash) && value["endpoint"].is_a?(String)

      "/ai2w/#{name}"
    end

    def negotiate(manifest, agent = nil)
      m = Util.deep_stringify(manifest)
      agent = Util.deep_stringify(agent || {})
      caps = m["capabilities"].is_a?(Hash) ? m["capabilities"] : {}
      site_caps = caps.select { |_k, v| Util.enabled?(v) }.keys

      want_caps = agent.key?("capabilities") ? (agent["capabilities"] || []) : site_caps
      capabilities = site_caps.select { |c| want_caps.include?(c) }
      unsupported = want_caps.reject { |c| site_caps.include?(c) }

      # Only transports explicitly enabled are negotiable.
      transports = m["transports"].is_a?(Hash) ? m["transports"] : {}
      site_transports = transports.select { |_k, v| v.is_a?(Hash) && v["enabled"] == true }.keys
      want_transports = agent.key?("transports") ? (agent["transports"] || []) : site_transports
      transport = want_transports.find { |t| site_transports.include?(t) }

      auth_block = m["auth"].is_a?(Hash) ? m["auth"] : {}
      site_auth = auth_block["methods"] || ["none"]
      want_auth = agent.key?("auth") ? (agent["auth"] || []) : site_auth
      auth =
        if site_auth.include?("oauth2") && want_auth.include?("oauth2")
          "oauth2"
        else
          picked = want_auth.find { |a| site_auth.include?(a) }
          picked.nil? && site_auth.include?("none") ? "none" : picked
        end

      endpoints = {}
      capabilities.each { |c| endpoints[c] = endpoint_of(c, caps[c]) }
      if !transport.nil? && transports[transport].is_a?(Hash) && transports[transport]["endpoint"]
        endpoints[transport] = transports[transport]["endpoint"]
      end

      {
        negotiated: { transport: transport, capabilities: capabilities, auth: auth, endpoints: endpoints },
        unsupported: unsupported
      }
    end
  end

  module_function

  def negotiate(manifest, agent = nil) = Negotiator.negotiate(manifest, agent)
end
