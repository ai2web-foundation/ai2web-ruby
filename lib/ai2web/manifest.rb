# frozen_string_literal: true

require "json"

module Ai2Web
  # Fluent AI2Web (ai2w) manifest builder - "describe your website once".
  #
  # Every setter returns self, so calls chain. Inputs may use symbol or string keys; the builder
  # stores string keys internally so the result round-trips cleanly as JSON.
  #
  #   manifest = Ai2Web.ai2web(name: "Store", url: "https://store.example", type: "ecommerce")
  #     .capability("content")
  #     .capability("commerce", endpoint: "/ai2w/products", checkout: true)
  #     .contact(support: "help@store.example")
  #     .build
  class Manifest
    def initialize(site)
      @m = { "protocol" => "ai2w", "version" => "0.2", "site" => Util.deep_stringify(site), "capabilities" => {} }
    end

    def self.for_site(name:, url:, type:, **extra)
      new({ "name" => name, "url" => url, "type" => type }.merge(Util.deep_stringify(extra)))
    end

    def capability(name, value = true)
      value = { "enabled" => true }.merge(Util.deep_stringify(value)) if value.is_a?(Hash)
      @m["capabilities"][name.to_s] = value
      self
    end

    def transports(t)
      (@m["transports"] ||= {}).merge!(Util.deep_stringify(t))
      self
    end

    def auth(a)
      @m["auth"] = Util.deep_stringify(a)
      self
    end

    def consent(c)
      @m["consent"] = Util.deep_stringify(c)
      self
    end

    def action(a)
      (@m["actions"] ||= []) << Util.deep_stringify(a)
      capability("actions", "endpoint" => "/ai2w/actions")
      self
    end

    def events(e)
      e = Util.deep_stringify(e)
      @m["events"] = e
      capability("events", "endpoint" => e["endpoint"] || "/ai2w/events")
      self
    end

    def agent_service(s)
      @m["agent_service"] = Util.deep_stringify(s)
      self
    end

    def identity(i)
      @m["identity"] = Util.deep_stringify(i)
      self
    end

    def contact(c)
      @m["contact"] = Util.deep_stringify(c)
      self
    end

    # --- v0.2 optional modules (all additive; a minimal manifest stays valid without them). ---
    def governance(g)
      @m["governance"] = Util.deep_stringify(g)
      self
    end

    def usage_policy(u)
      @m["usage_policy"] = Util.deep_stringify(u)
      self
    end

    def legal(l)
      @m["legal"] = Util.deep_stringify(l)
      self
    end

    def agent_identity(a)
      base = @m["identity"].is_a?(Hash) ? @m["identity"] : {}
      @m["identity"] = base.merge("agent" => Util.deep_stringify(a))
      self
    end

    def knowledge(k)
      @m["knowledge"] = Util.deep_stringify(k)
      self
    end

    # Attach a vendor extension. The key is namespaced with `x-` if not already.
    def extension(key, value)
      key = key.to_s
      key = "x-#{key}" unless key.start_with?("x-")
      @m[key] = Util.deep_stringify(value)
      self
    end

    def build = @m
    def to_h = @m

    # Serialize to a JSON string. Pretty-printed by default; pass `indent: 0` for compact output.
    # Accepts (and ignores) a JSON generator state so the object still works when nested inside
    # another `JSON.generate` call.
    def to_json(*_args, indent: 2)
      indent.to_i.positive? ? JSON.pretty_generate(@m) : JSON.generate(@m)
    end
  end

  module_function

  def ai2web(site) = Manifest.new(site)
  def manifest(site) = Manifest.new(site)
end
