# frozen_string_literal: true

require "uri"

module Ai2Web
  # SSRF guard. Parity with @ai2web/core safety.
  #
  # Blocks the obvious pivots (loopback, private ranges, cloud metadata, link-local, non-http
  # schemes) AND the alternative IP encodings that HTTP clients resolve to those same addresses
  # (decimal / hex / octal / short-form IPv4, and IPv4-mapped IPv6). This is a literal host/IP
  # check - not by itself DNS-rebind safe.
  module Safety
    IPV4_RE = /\A(\d{1,3})\.(\d{1,3})\.(\d{1,3})\.(\d{1,3})\z/.freeze
    IPV4_TAIL = /(\d{1,3}\.\d{1,3}\.\d{1,3}\.\d{1,3})\z/.freeze

    module_function

    # True if a standard dotted-quad is loopback/private/reserved (or has an invalid octet).
    def ipv4_blocked?(host)
      m = IPV4_RE.match(host)
      return false unless m

      parts = m.captures.map(&:to_i)
      return true if parts.any? { |p| p > 255 } # not a real address; refuse

      a, b = parts[0], parts[1]
      return true if [0, 10, 127].include?(a)
      return true if a == 169 && b == 254         # link-local + cloud metadata (169.254.169.254)
      return true if a == 172 && b >= 16 && b <= 31
      return true if a == 192 && b == 168
      return true if a == 100 && b >= 64 && b <= 127 # CGNAT

      false
    end

    def safe_public_url?(raw)
      begin
        u = URI.parse(raw.to_s)
      rescue URI::InvalidURIError
        return false
      end
      return false unless %w[https http].include?(u.scheme)

      host = (u.host || "").downcase.sub(/\A\[/, "").sub(/\]\z/, "")
      return false if host.empty? || host == "localhost" || host.end_with?(".localhost")

      # IPv6 literal.
      if host.include?(":")
        # IPv4-mapped / compat (::ffff:a.b.c.d, ::a.b.c.d): range-check the embedded IPv4.
        m = IPV4_TAIL.match(host)
        return false if m && ipv4_blocked?(m[1])
        return false if host == "::1" || host.start_with?("fc", "fd", "fe80")

        return true
      end

      # Hex-encoded IP (0x7f000001, or a dotted octet like 0x7f): a client resolves these to an IP.
      return false if host.match?(/(^|\.)0x/)

      # Standard dotted-quad IPv4.
      return !ipv4_blocked?(host) if IPV4_RE.match?(host)

      # Any remaining all-numeric host is an alternative IPv4 encoding (decimal integer, octal, or
      # short form like 127.1) that a client resolves to an IP. No real domain looks like this.
      return false unless host.match?(/[a-z]/)

      true
    end

    def assert_safe_public_url!(raw)
      raise ArgumentError, "ai2w: refusing to fetch non-public or unsafe URL: #{raw}" unless safe_public_url?(raw)

      raw
    end

    def same_origin?(a, b)
      pa = URI.parse(a.to_s)
      pb = URI.parse(b.to_s)
      [pa.scheme, pa.host, pa.port] == [pb.scheme, pb.host, pb.port]
    rescue URI::InvalidURIError
      false
    end
  end

  module_function

  # Convenience top-level aliases so callers can use `Ai2Web.safe_public_url?` etc.
  def safe_public_url?(raw) = Safety.safe_public_url?(raw)
  def assert_safe_public_url!(raw) = Safety.assert_safe_public_url!(raw)
  def same_origin?(a, b) = Safety.same_origin?(a, b)
end
