# frozen_string_literal: true

module Ai2Web
  # Framework-agnostic AI2Web request handler. Port of @ai2web/server.
  #
  # Returns a Hash { status:, headers:, body: }; adapt it to Rails / Sinatra / Rack / etc. `body`
  # is a Ruby Hash (serialize to JSON in your adapter) or a String for text responses.
  module Server
    CORS = {
      "access-control-allow-origin" => "*",
      "access-control-allow-methods" => "GET, POST, OPTIONS",
      "access-control-allow-headers" => "content-type, authorization"
    }.freeze

    ACTION_RE = %r{\A/ai2w/actions/([a-z0-9_-]+)\z}i.freeze
    MODULE_RE = %r{\A/ai2w/([a-z0-9_-]+)\z}i.freeze

    module_function

    def json(status, body)
      { status: status, headers: { "content-type" => "application/json; charset=utf-8" }.merge(CORS), body: body }
    end

    def error(status, code, message, retryable: false)
      json(status, { "error" => { "code" => code, "message" => message, "retryable" => retryable } })
    end

    def text(status, content_type, body)
      { status: status, headers: { "content-type" => content_type }.merge(CORS), body: body }
    end

    def opt(opts, key)
      opts[key] || opts[key.to_s]
    end

    def lookup(table, name)
      table[name] || table[name.to_sym]
    end

    def handle(opts, method, path, body = nil, origin = nil)
      manifest = Util.deep_stringify(opt(opts, :manifest))
      modules = opt(opts, :modules) || {}
      actions = opt(opts, :actions) || {}
      validate_input = opts.key?(:validate_input) || opts.key?("validate_input") ? opt(opts, :validate_input) : true
      declared_actions = {}
      (manifest["actions"] || []).each { |a| declared_actions[a["name"]] = a if a.is_a?(Hash) }

      trimmed = path.to_s.gsub(%r{\A/+|/+\z}, "")
      path = trimmed.empty? ? "/" : "/#{trimmed}"
      method = method.to_s.upcase

      return { status: 204, headers: CORS.dup, body: nil } if method == "OPTIONS"

      if path == "/.well-known/ai2w"
        return json(200, { "ai2w" => "#{Util.trim_url(origin)}/ai2w" }) if origin && !origin.to_s.empty?

        return json(200, manifest)
      end

      if ["/ai2w", "/ai", "/.ai"].include?(path)
        return error(405, "invalid_request", "Use GET for the manifest.") if method != "GET"

        return json(200, manifest)
      end

      # Multi-surface projections (RFC-0015): the one canonical manifest, emitted in other discovery
      # formats so agents that speak llms.txt or agent.json need not parse ai2w first.
      if path == "/llms.txt"
        return error(405, "invalid_request", "Use GET for llms.txt.") if method != "GET"

        return text(200, "text/plain; charset=utf-8", Ai2Web.to_llms_txt(manifest))
      end
      if ["/.well-known/agent.json", "/agent.json"].include?(path)
        return error(405, "invalid_request", "Use GET for agent.json.") if method != "GET"

        return json(200, Ai2Web.to_agent_json(manifest))
      end

      if path == "/ai2w/negotiate"
        b = body.is_a?(Hash) ? Util.deep_stringify(body) : {}
        agent = b["agent"].is_a?(Hash) ? b["agent"] : {}
        supports = agent["supports"] || b["supports"] || b
        supports = {} unless supports.is_a?(Hash)
        return json(200, Ai2Web.negotiate(manifest, supports))
      end

      if (m = ACTION_RE.match(path))
        name = m[1].tr("-", "_")
        fn = lookup(actions, name)
        return error(404, "unsupported_capability", "Unknown action '#{name}'.") unless fn

        declared = declared_actions[name]
        if Util.truthy?(validate_input) && declared && declared["input_schema"]
          result = Ai2Web.validate_schema(body.nil? ? {} : body, declared["input_schema"])
          unless result.valid
            return error(400, "invalid_request",
                         "Request does not match the declared input schema: #{result.errors.join("; ")}.")
          end
        end
        return json(200, fn.call(body))
      end

      if (m = MODULE_RE.match(path))
        name = m[1]
        fn = lookup(modules, name)
        return error(404, "unsupported_capability", "Module '#{name}' not exposed.") unless fn

        return json(200, fn.call(body))
      end

      error(404, "invalid_request", "No AI2Web route for #{path}.")
    end
  end

  module_function

  def handle(opts, method, path, body = nil, origin = nil) = Server.handle(opts, method, path, body, origin)
end
