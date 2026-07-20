# frozen_string_literal: true

require "openssl"
require "digest"
require "base64"
require "json"
require "securerandom"

module Ai2Web
  # AP2 (Agent Payments Protocol, Google - v0.2.0) merchant primitives.
  #
  # AP2 is mandate-based: the merchant prices a buyer agent's Intent Mandate as a CartContents
  # (a W3C PaymentRequest, amounts in decimal major units) and digitally signs it into a
  # CartMandate - a short-lived guarantee of items and price - then settles a user-signed Payment
  # Mandate. This module provides the reusable, app-agnostic core: build the mandate objects, sign
  # a CartContents as an RS256 JWT (cart_hash over the canonical contents), publish the public key
  # as a JWKS, verify a Cart Mandate, and parse a Payment Mandate. Signing uses the OpenSSL
  # standard library, so the SDK keeps zero third-party dependencies.
  module Ap2
    EXTENSION_URI = "https://github.com/google-agentic-commerce/ap2/v1"
    VERSION = "0.2.0"
    DEFAULT_TTL = 900

    module_function

    # The transports.ap2 advertisement to merge into a manifest.
    def transport(overrides = {})
      {
        "enabled" => true,
        "version" => VERSION,
        "extension" => EXTENSION_URI,
        "agent_card" => "/ai2w/ap2/agent-card",
        "cart" => "/ai2w/ap2/cart",
        "payment" => "/ai2w/ap2/payment",
        "jwks" => "/ai2w/ap2/jwks"
      }.merge(overrides.each_with_object({}) { |(k, v), o| o[k.to_s] = v })
    end

    # Build an AP2 IntentMandate (classic v0.2.0 shape).
    def intent_mandate(description, merchants: nil, skus: nil, items: nil, requires_refundability: false,
                       user_cart_confirmation_required: true, expires_in: DEFAULT_TTL, now: nil)
      ts = now || Time.now.to_i
      m = {
        "natural_language_description" => description,
        "intent_expiry" => iso(ts + expires_in),
        "user_cart_confirmation_required" => user_cart_confirmation_required
      }
      m["merchants"] = merchants if merchants && !merchants.empty?
      m["skus"] = skus if skus && !skus.empty?
      m["items"] = items if items && !items.empty?
      m["requires_refundability"] = true if requires_refundability
      m
    end

    # AP2 PaymentCurrencyAmount: decimal major units, ISO 4217.
    def amount(value, currency)
      { "currency" => currency.upcase, "value" => value.round(2) }
    end

    # Build a CartContents (W3C PaymentRequest) from line items. Each item is
    # { label:, unit_amount:, quantity: 1 } (string or symbol keys).
    def cart_contents(items, currency, merchant_name, id: nil, payment_details_id: nil, expires_in: DEFAULT_TTL, now: nil)
      ts = now || Time.now.to_i
      display = []
      total = 0.0
      items.each do |it|
        qty = [(it[:quantity] || it["quantity"] || 1).to_i, 1].max
        unit = (it[:unit_amount] || it["unit_amount"] || it[:amount] || it["amount"] || 0).to_f
        line = unit * qty
        label = (it[:label] || it["label"] || "Item").to_s
        label = "#{label} x#{qty}" if qty > 1
        display << { "label" => label, "amount" => amount(line, currency) }
        total += line
      end
      {
        "id" => id || "cart_#{SecureRandom.hex(10)}",
        "user_cart_confirmation_required" => true,
        "payment_request" => {
          "method_data" => [{ "supported_methods" => "card", "data" => {} }],
          "details" => {
            "id" => payment_details_id || "pr_#{SecureRandom.hex(10)}",
            "display_items" => display,
            "total" => { "label" => "Total", "amount" => amount(total, currency) }
          },
          "options" => { "request_shipping" => true }
        },
        "cart_expiry" => iso(ts + expires_in),
        "merchant_name" => merchant_name
      }
    end

    # The merchant_authorization JWT (RS256) over the canonical CartContents.
    def sign_cart(contents, private_key_pem, kid: nil, iss: nil, aud: "ap2-network", expires_in: DEFAULT_TTL, now: nil)
      key = OpenSSL::PKey::RSA.new(private_key_pem)
      ts = now || Time.now.to_i
      header = { "alg" => "RS256", "typ" => "JWT", "kid" => kid || kid_of(key) }
      claims = {
        "iss" => iss || contents["merchant_name"] || "",
        "sub" => contents["id"] || "",
        "aud" => aud,
        "iat" => ts,
        "exp" => ts + expires_in,
        "jti" => SecureRandom.hex(12),
        "cart_hash" => b64url(Digest::SHA256.digest(canonical(contents)))
      }
      signing_input = "#{b64url(canonical(header))}.#{b64url(canonical(claims))}"
      sig = key.sign(OpenSSL::Digest.new("SHA256"), signing_input)
      "#{signing_input}.#{b64url(sig)}"
    end

    # Sign CartContents into a CartMandate (contents + merchant_authorization).
    def cart_mandate(contents, private_key_pem, **opts)
      { "contents" => contents, "merchant_authorization" => sign_cart(contents, private_key_pem, **opts) }
    end

    # JWKS publishing the cart-signing public key, for verifiers.
    def jwks(private_key_pem, kid: nil)
      key = OpenSSL::PKey::RSA.new(private_key_pem)
      pub = key.public_key
      {
        "keys" => [{
          "kty" => "RSA",
          "use" => "sig",
          "alg" => "RS256",
          "kid" => kid || kid_of(key),
          "n" => b64url(pub.n.to_s(2)),
          "e" => b64url(pub.e.to_s(2))
        }]
      }
    end

    # Verify a CartMandate's signature (against a public or private PEM) and its cart_hash binding,
    # and that it has not expired.
    def verify_cart_mandate(mandate, key_pem)
      parts = mandate["merchant_authorization"].to_s.split(".")
      return false unless parts.length == 3

      key = begin
        OpenSSL::PKey::RSA.new(key_pem)
      rescue StandardError
        return false
      end
      sig = begin
        b64url_decode(parts[2])
      rescue StandardError
        return false
      end
      return false unless key.verify(OpenSSL::Digest.new("SHA256"), sig, "#{parts[0]}.#{parts[1]}")

      claims = begin
        JSON.parse(b64url_decode(parts[1]))
      rescue StandardError
        return false
      end
      ch = claims["cart_hash"].to_s
      return false if ch.empty?
      return false if claims["exp"] && Time.now.to_i > claims["exp"].to_i

      expected = b64url(Digest::SHA256.digest(canonical(mandate["contents"] || {})))
      ch == expected
    end

    # Extract the salient fields of a PaymentMandate for settlement.
    def payment_details(payment_mandate)
      c = payment_mandate["payment_mandate_contents"] || {}
      resp = c["payment_response"] || {}
      total = c["payment_details_total"] || {}
      {
        "payment_mandate_id" => c["payment_mandate_id"],
        "payment_details_id" => c["payment_details_id"],
        "total" => total["amount"],
        "method" => resp["method_name"],
        "payer_email" => resp["payer_email"],
        "payer_name" => resp["payer_name"]
      }
    end

    # --- helpers ---

    def canonical(value)
      JSON.generate(value)
    end

    def b64url(bin)
      Base64.urlsafe_encode64(bin, padding: false)
    end

    def b64url_decode(str)
      Base64.urlsafe_decode64(str + ("=" * ((4 - (str.length % 4)) % 4)))
    end

    def iso(timestamp)
      Time.at(timestamp).utc.strftime("%Y-%m-%dT%H:%M:%S+00:00")
    end

    def kid_of(key)
      pub = key.public_key
      Digest::SHA256.hexdigest(pub.n.to_s(2) + pub.e.to_s(2))[0, 16]
    end
  end
end
