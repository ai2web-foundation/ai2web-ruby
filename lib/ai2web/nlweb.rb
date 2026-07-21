# frozen_string_literal: true

require "securerandom"

module Ai2Web
  # NLWeb (nlweb.ai) interop primitives.
  #
  # NLWeb turns a site's content into a natural-language, schema.org-flavoured query endpoint (its
  # `ask` API). These helpers let an AI2Web site advertise an NLWeb surface in its manifest and
  # serve a minimal, NLWeb-compatible `ask` response over its own content, so agents that speak
  # NLWeb can query the site without it deploying the full NLWeb stack.
  #
  # The search itself is application-specific (a pure toolkit): the app finds the matching content
  # items and passes them in; #ask_response shapes them into NLWeb's result envelope (list mode,
  # schema.org Item results; pass an answer for generate mode). NLWeb defines no discovery file, so
  # #transport is an AI2Web convention pointing at the site's `/ask` (and `/mcp`) URLs.
  module Nlweb
    VERSION = "0.55"
    DEFAULT_ASK = "/ai2w/nlweb/ask"
    DEFAULT_MCP = "/ai2w/nlweb/mcp"

    module_function

    # The transports.nlweb advertisement to merge into a manifest.
    def transport(overrides = {})
      {
        "enabled" => true,
        "version" => VERSION,
        "ask" => DEFAULT_ASK,
        "mcp" => DEFAULT_MCP,
        "modes" => ["list"]
      }.merge(overrides.each_with_object({}) { |(k, v), o| o[k.to_s] = v })
    end

    # Wrap one content item into an NLWeb result Item.
    def item(content, site: nil, site_url: nil)
      c = stringify(content)
      schema = c["schema_object"].is_a?(Hash) ? c["schema_object"] : schema_object(c)
      {
        "@type" => "Item",
        "url" => (c["url"] || "").to_s,
        "name" => (c["name"] || c["title"] || "").to_s,
        "site" => (c["site"] || site || "").to_s,
        "siteUrl" => (c["siteUrl"] || site_url || "").to_s,
        "score" => c.key?("score") ? c["score"].to_i : 100,
        "description" => (c["description"] || "").to_s,
        "schema_object" => schema
      }
    end

    # Build a minimal buffered NLWeb ask response (list mode) from matched content items.
    def ask_response(query, items, site: nil, site_url: nil, query_id: nil, answer: nil)
      results = items.map { |it| item(it.is_a?(Hash) ? it : {}, site: site, site_url: site_url) }
      resp = {
        "query" => query,
        "query_id" => query_id || "q_#{SecureRandom.hex(8)}",
        "message_type" => "result",
        "results" => results
      }
      resp["answer"] = { "@type" => "GeneratedAnswer", "answer" => answer.to_s, "items" => results } if answer && !answer.to_s.empty?
      resp
    end

    def schema_object(content)
      c = stringify(content)
      obj = { "@type" => (c["type"] || "Thing").to_s }
      name = c["name"] || c["title"]
      obj["name"] = name if name
      obj["url"] = c["url"] if c["url"]
      obj["description"] = c["description"] if c["description"]
      obj
    end

    def stringify(hash)
      return {} unless hash.is_a?(Hash)

      hash.each_with_object({}) { |(k, v), o| o[k.to_s] = v }
    end
  end
end
