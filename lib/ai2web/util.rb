# frozen_string_literal: true

module Ai2Web
  # Small shared helpers. AI2Web manifests are JSON documents, so the SDK works internally with
  # string-keyed hashes; +deep_stringify+ lets callers pass symbol keys and still get parity.
  module Util
    module_function

    # Recursively convert every Hash key to a String (values untouched). Idempotent.
    def deep_stringify(obj)
      case obj
      when Hash then obj.each_with_object({}) { |(k, v), h| h[k.to_s] = deep_stringify(v) }
      when Array then obj.map { |e| deep_stringify(e) }
      else obj
      end
    end

    # Mirror of @ai2web/core `_has`: a capability/transport is on when it is `true` or an
    # object with `enabled: true`.
    def enabled?(value)
      value == true || (value.is_a?(Hash) && value["enabled"] == true)
    end

    # Python-style truthiness, used only where the reference validator relies on `bool(...)`
    # (empty hash/array/string are falsy). Keeps exact scoring/tier parity with the other SDKs.
    def truthy?(value)
      case value
      when nil, false then false
      when Hash, Array, String then !value.empty?
      when Numeric then value != 0
      else true
      end
    end

    # Strip trailing slashes from a URL/base.
    def trim_url(url)
      url.to_s.sub(%r{/+\z}, "")
    end
  end
end
