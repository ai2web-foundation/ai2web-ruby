# frozen_string_literal: true

# AI2Web Ruby SDK tests. Dependency-free - run with `ruby test/run.rb`.
#
# Includes the shared conformance contract (conformance_cases.json, a copy of the spec's
# cases.json) to prove Ruby parity with the TS/Python/PHP reference validators.

$LOAD_PATH.unshift File.expand_path("../lib", __dir__)

require "json"
require "ai2web"

include Ai2Web # rubocop:disable Style/MixinUsage - convenience for the test script only

$failures = 0

def check(cond, label, detail = nil)
  puts((cond ? "PASS" : "FAIL") + "  " + label)
  return if cond

  $failures += 1
  puts "      got: #{detail.inspect}" unless detail.nil?
end

# --- builder + validate ---
m = ai2web(name: "Example Store", url: "https://store.example.com", type: "ecommerce")
    .capability("content")
    .capability("commerce", endpoint: "/ai2w/products", checkout: true)
    .capability("search", endpoint: "/ai2w/search")
    .transports(mcp: { enabled: true, endpoint: "/ai2w/mcp" }, rest: { enabled: true, base: "/ai2w" })
    .auth(methods: %w[none oauth2], oauth2: { pkce: true, scopes: ["checkout"] })
    .consent(requires_user_approval_for: ["purchase"])
    .events(endpoint: "/ai2w/events", types: %w[order.shipped price.drop])
    .action(name: "track_order", description: "Track", method: "POST", endpoint: "/ai2w/actions/track-order",
            requires_auth: true, requires_user_approval: false, risk: "medium", input_schema: { type: "object" })
    .identity(legal_name: "Example Store Ltd")
    .contact(support: "help@store.example.com")
    .build

check(m["protocol"] == "ai2w", "builder sets protocol ai2w")

v = validate(m)
check(v[:valid] == true, "manifest is valid", v[:errors])
check(v[:score] >= 90, "AI Readiness score >= 90", v[:score])
check(%w[Standard Enterprise].include?(v[:tier]), "tier Standard/Enterprise", v[:tier])

# --- negotiate ---
neg = negotiate(m, transports: %w[mcp rest], capabilities: %w[content commerce flying], auth: ["oauth2"])
check(neg[:negotiated][:transport] == "mcp", "negotiate picks mcp", neg[:negotiated][:transport])
check(neg[:negotiated][:capabilities] == %w[content commerce], "negotiate intersects caps", neg[:negotiated][:capabilities])
check(neg[:unsupported] == ["flying"], "negotiate reports unsupported", neg[:unsupported])
check(neg[:negotiated][:auth] == "oauth2", "negotiate selects oauth2", neg[:negotiated][:auth])

# --- server routing ---
home = handle({ manifest: m }, "GET", "/ai2w")
check(home[:status] == 200 && home[:body]["protocol"] == "ai2w", "server serves manifest at /ai2w")
wk = handle({ manifest: m }, "GET", "/.well-known/ai2w", nil, "https://store.example.com")
check(wk[:body]["ai2w"] == "https://store.example.com/ai2w", "well-known returns pointer", wk[:body])
notget = handle({ manifest: m }, "POST", "/ai2w")
check(notget[:status] == 405, "manifest is GET-only (405 on POST)")
act = handle({ manifest: m, actions: { "track_order" => ->(b) { { "ok" => true, "echo" => b } } } },
             "POST", "/ai2w/actions/track-order", { "order_id" => "A1" })
check(act[:body]["ok"] == true, "server dispatches action handler", act[:body])

# --- SSRF guard ---
check(safe_public_url?("https://store.example.com") == true, "ssrf allows public https")
check(safe_public_url?("http://169.254.169.254/latest") == false, "ssrf blocks metadata ip")
check(safe_public_url?("http://localhost:8080") == false, "ssrf blocks localhost")
check(safe_public_url?("https://10.0.0.5/x") == false, "ssrf blocks private range")

# --- conformance contract (parity with the spec) ---
cases = JSON.parse(File.read(File.join(__dir__, "conformance_cases.json")))
cases.each do |c|
  r = validate(c["manifest"])
  e = c["expect"]
  probs = []
  probs << "valid=#{r[:valid]}" if e.key?("valid") && r[:valid] != e["valid"]
  probs << "tier=#{r[:tier]} (want #{e["tier"]})" if e.key?("tier") && r[:tier] != e["tier"]
  probs << "score=#{r[:score]} < #{e["minScore"]}" if e.key?("minScore") && r[:score] < e["minScore"]
  if e.key?("errorsContain") && r[:errors].none? { |x| x.include?(e["errorsContain"]) }
    probs << "errors missing '#{e["errorsContain"]}'"
  end
  if e.key?("warns")
    e["warns"].each do |w|
      chk = r[:checks].find { |c2| c2[:label] == w }
      probs << "expected warn '#{w}'" if chk.nil? || chk[:ok]
    end
  end
  check(probs.empty?, "conformance: #{c["name"]}", probs.empty? ? nil : probs)
end

# --- request validation (validate_schema + server) ---
s = { type: "object", properties: { order_id: { type: "string" }, qty: { type: "integer" } }, required: ["order_id"] }
check(validate_schema({ "order_id" => "A1", "qty" => 2 }, s).valid, "schema: valid input passes")
check(!validate_schema({ "qty" => 2 }, s).valid, "schema: missing required fails")
check(!validate_schema({ "order_id" => 5 }, s).valid, "schema: wrong type fails")
check(!validate_schema({ "order_id" => "A1", "qty" => 1.5 }, s).valid, "schema: non-integer fails")
check(validate_schema({ "anything" => 1 }, {}).valid, "schema: empty schema accepts anything")

man = {
  "protocol" => "ai2w", "version" => "0.1",
  "site" => { "name" => "S", "url" => "https://s.example", "type" => "ecommerce" },
  "capabilities" => { "actions" => { "enabled" => true } },
  "actions" => [{
    "name" => "track_order", "method" => "POST", "endpoint" => "/ai2w/actions/track-order",
    "requires_auth" => false, "requires_user_approval" => false, "risk" => "low",
    "input_schema" => { "type" => "object", "properties" => { "order_id" => { "type" => "string" } }, "required" => ["order_id"] }
  }]
}
acts = { "track_order" => ->(_b) { { "ok" => true } } }
ok = handle({ manifest: man, actions: acts }, "POST", "/ai2w/actions/track-order", { "order_id" => "A1" })
bad = handle({ manifest: man, actions: acts }, "POST", "/ai2w/actions/track-order", {})
off = handle({ manifest: man, actions: acts, validate_input: false }, "POST", "/ai2w/actions/track-order", {})
check(ok[:status] == 200, "server: valid body -> 200", ok)
check(bad[:status] == 400 && bad[:body]["error"]["code"] == "invalid_request", "server: missing required -> 400 invalid_request", bad[:body])
check(off[:status] == 200, "server: validate_input=false opt-out passes through", off)

# --- v0.2 modules + export adapters (parity with @ai2web/core) ---
m2 = ai2web(name: "Example Bistro", url: "https://bistro.example", type: "restaurant",
            description: "Italian, terrace dining.")
     .capability("content")
     .capability("commerce", endpoint: "/ai2w/products")
     .capability("search", endpoint: "/ai2w/search")
     .action(name: "book_table", description: "Reserve a table.", method: "POST",
             endpoint: "/ai2w/actions/book-table", requires_auth: false, requires_user_approval: true,
             risk: "medium", intent: "reserve_table",
             input_schema: { type: "object", properties: { date: { type: "string" }, party: { type: "integer" } },
                             required: %w[date party] },
             bindings: [{ kind: "mcp", ref: "book_table", priority: 1 },
                        { kind: "redirect", ref: "/reserve", priority: 9, fallback_only: true }])
     .knowledge([{ id: "menu", name: "Menu", kind: "catalog", ref: "/ai2w/products", format: "json" }])
     .governance(rate_limits: { requests: 60, window_seconds: 60 }, consent_mode: { book_table: "explicit" })
     .usage_policy(bulk_extraction: false, model_training: false)
     .legal(jurisdiction: "EU", ai_transparency: true, ai_risk_classification: "limited")
     .agent_identity(required: false, allow_anonymous: true, methods: ["http_message_signatures"])
     .contact(support: "hi@bistro.example")
     .build

check(m2["version"] == "0.2", "builder defaults to version 0.2", m2["version"])
check(m2["governance"]["rate_limits"]["requests"] == 60, "builder: governance")
check(m2["usage_policy"]["model_training"] == false, "builder: usage_policy")
check(m2["legal"]["ai_risk_classification"] == "limited", "builder: legal")
check(m2["identity"]["agent"]["methods"][0] == "http_message_signatures", "builder: agent identity")
check(m2["knowledge"][0]["id"] == "menu", "builder: knowledge")
check(m2["actions"][0]["intent"] == "reserve_table", "action: intent")
check(m2["actions"][0]["bindings"].length == 2, "action: bindings")
check(m2["actions"][0]["bindings"][1]["fallback_only"] == true, "action: fallback_only binding")

txt = to_llms_txt(m2)
check(txt.start_with?("# Example Bistro"), "llms.txt: title")
check(txt.include?("## Capabilities") && txt.include?("- commerce"), "llms.txt: capabilities")
check(txt.include?("## Knowledge") && txt.include?("Menu"), "llms.txt: knowledge")
check(txt.include?("book_table: Reserve a table."), "llms.txt: action")
check(txt.include?("https://bistro.example/ai2w"), "llms.txt: discovery link")

aj = to_agent_json(m2)
check(aj["name"] == "Example Bistro", "agent.json: name")
check(aj["capabilities"].include?("commerce"), "agent.json: capabilities")
check(aj["actions"][0]["intent"] == "reserve_table", "agent.json: action intent")
check(aj["actions"][0]["bindings"].length == 2, "agent.json: bindings preserved")
check(aj["policies"]["legal"]["jurisdiction"] == "EU", "agent.json: legal in policies")
check(aj["policies"]["governance"]["consent_mode"]["book_table"] == "explicit", "agent.json: governance carried")
# action without explicit bindings falls back to a rest binding on its endpoint
aj_default = to_agent_json(ai2web(name: "X", url: "https://x.example", type: "site")
                           .action(name: "a", description: "d", method: "POST", endpoint: "/ai2w/actions/a",
                                   requires_auth: false, requires_user_approval: false, risk: "low").build)
check(aj_default["actions"][0]["bindings"][0]["kind"] == "rest", "agent.json: default rest binding")

# --- multi-surface serving (llms.txt + agent.json) ---
srv = { manifest: m2 }
llms = handle(srv, "GET", "/llms.txt")
check(llms[:status] == 200 && llms[:headers]["content-type"].start_with?("text/plain"), "server: /llms.txt text/plain", llms[:status])
check(llms[:body].is_a?(String) && llms[:body].start_with?("# Example Bistro"), "server: /llms.txt body")
ajr = handle(srv, "GET", "/.well-known/agent.json")
check(ajr[:status] == 200 && ajr[:body]["name"] == "Example Bistro", "server: /.well-known/agent.json", ajr[:status])
ajr2 = handle(srv, "GET", "/agent.json")
check(ajr2[:status] == 200 && ajr2[:body]["policies"]["governance"]["rate_limits"]["requests"] == 60, "server: /agent.json alias + governance")
llpost = handle(srv, "POST", "/llms.txt")
check(llpost[:status] == 405, "server: /llms.txt POST -> 405")

# AP2 (Agent Payments Protocol) merchant primitives
ap2_key = <<~PEM
  -----BEGIN PRIVATE KEY-----
  MIIEvgIBADANBgkqhkiG9w0BAQEFAASCBKgwggSkAgEAAoIBAQC7/yKHuyEHpcRo
  Zahdi0IJeDyBoy7jV73flum/ysm3H3nK1lh7WHPNV1r27rOodKAIiJH/yVrKcAeR
  qRyDgJ8ftAIla/qj9zDu3h5rR40wRDM60DhpkjMoHa2aQ3Lh93wH004k40HxvWOA
  FORAZPrxo4JJTA7Qayak4VwWH2zepeSpmqO3kovZR4DDeDRJf/UnWC5fDAvQno+W
  c2lVdbzeErLS1TvbmVDVfIwPkE008gZWEhQ/qK3RSoQEUxqeqaA8BM/WYdQr+PDv
  EJgT0MfECcV+6ACMNHTCzspVRkE3pPcM2PVJekbGlirzxYMn2i0Hs0xgz1lwjEAb
  /pIA3Vh1AgMBAAECggEAGRI5ZKiMCx0MSG/mODNuJx0l1JQSmLcG116k5bMBm65S
  674SJsDxEJ1pwCytQPXssbak4dvUg9LU75QB/XeVwQCcmKkB0AQTPofYvq3YImu1
  +U3zeADLWbo7gKsmEwSSQejoLvsvvDFpp5chqYTOApOvuF6wSxM/IBX91eVy+24h
  sQgxxwmYtwaFqiW56oNcF+8OZVCenZF4NWGfJ6vDxyIgkfvlhPSzQl8BimzIB2j+
  hs5S4TYY1fE7pcuI91zk2dGpK9E1nxl3e57gZJ19w+YrhOXvatOSX++QeBrv2Vik
  kU1SbJq5K3fcGvjkEYXRqth0loTbZl3HxOgef4QksQKBgQDlxWxaQFrsa5pFP1a2
  iklsuIbKr/0DgHuENzlZtrUPzbzCYBQT28ADa+3HZIvXvNo4bUbHayrrwQh6nFWl
  n0JUVl3JzUcGJO6nJH/4uLI/G4NkMz/BW5G1fMnfpEBc2LAWbGYE0tgFxL/uvTeL
  o5zTI3ElZX5FsMb/KAoU5J8TYwKBgQDRdPA5ydXMoooQQ3mYc/UUdnVZPtiN0G1j
  +v/QyH5+0SEbj5AUaIbuTblNANRZsiz0OjJ4i5ZrXLRXOwYL0WvcC2we1KnRaomv
  dNmdQwu31YRnxEq97/3dSBJC7K0VkiRjrLIZD/dDDUnjFjBD1fa51AcedXmPJNjf
  3RyTYcKoRwKBgQDh8x2VNtnyyfHADQQ5p42C04cBxMSbb/qGz0OffHNbIidwQckc
  qimNc9I1FSQLuBQkDxneOv3PLlknMZtrrkws4W2DaFFismjZhqQts3rdYjH4FAmr
  HGASR6/BNCVy6EdpFZnRPoHeUlen7vyzXeZ3HtBCRSdCYw+dlQMs/pGMHwKBgQCG
  igaEGBEskHr+V1kTg+g4bJ6T5LpU3TxmrCMFiMM30jzh5yU09q81AtezjoTX2Irn
  lTo2E/NaowFzxoXrsWkGvo+EfjVWPoiSGwxs51PvkUarIHqh5jW6nUCdnEjRQj39
  iEAduROqDi8XnnkCGb2RP5ATEII0YAauROjGAlV2oQKBgD4yneSwi1i8gfd4fEUS
  tuRB4AkX6EHw6E9Zjj/gwttVt1vYM8dbam5aZPlP602yRRUrt0T101zE+s0SBQZh
  9IUctJHxGO/5cufDZvovw2pXKlZkcpDxwPoKiUQZxiPBXf8YfKHUXz0gSc6QHAzu
  XinNZUVoxqiVkt4smBecyfGS
  -----END PRIVATE KEY-----
PEM

ap2t = Ai2Web::Ap2.transport
check(ap2t["enabled"] == true && ap2t["version"] == "0.2.0", "ap2: transport advertises version")
check(ap2t["extension"].include?("ap2"), "ap2: transport carries the extension uri")

ap2_golden = { "z" => "a/b", "currency" => "GBP", "n" => 10.0, "items" => [{ "value" => 9.99, "label" => "Mug" }], "ok" => true }
check(Ai2Web::Ap2.canonical(ap2_golden) == '{"currency":"GBP","items":[{"label":"Mug","value":9.99}],"n":10,"ok":true,"z":"a/b"}', "ap2: JCS canonical is cross-SDK stable", Ai2Web::Ap2.canonical(ap2_golden))

ap2_intent = Ai2Web::Ap2.intent_mandate("a red basketball shoe", skus: ["SHOE-1"], now: 1000)
check(ap2_intent["natural_language_description"] == "a red basketball shoe" && ap2_intent["skus"] == ["SHOE-1"] && !ap2_intent["intent_expiry"].empty?, "ap2: intent mandate built")

ap2_contents = Ai2Web::Ap2.cart_contents([{ label: "Mug", unit_amount: 9.99, quantity: 3 }], "GBP", "Test Store", now: 1000)
ap2_val = ap2_contents["payment_request"]["details"]["total"]["amount"]["value"]
check(ap2_val == 29.97, "ap2: cart total = 3 x 9.99", ap2_val)
check(ap2_contents["payment_request"]["details"]["total"]["amount"]["currency"] == "GBP", "ap2: cart currency major units")

ap2_mandate = Ai2Web::Ap2.cart_mandate(ap2_contents, ap2_key)
check(ap2_mandate["merchant_authorization"].count(".") == 2, "ap2: cart mandate is a JWT")
ap2_jwks = Ai2Web::Ap2.jwks(ap2_key)
check(ap2_jwks["keys"][0]["kty"] == "RSA" && !ap2_jwks["keys"][0]["n"].empty? && ap2_jwks["keys"][0]["alg"] == "RS256", "ap2: jwks publishes the RSA signing key")
check(Ai2Web::Ap2.verify_cart_mandate(ap2_mandate, ap2_key) == true, "ap2: valid cart mandate verifies")

# Tamper: change the total; verification must fail.
ap2_tampered = JSON.parse(JSON.generate(ap2_mandate))
ap2_tampered["contents"]["payment_request"]["details"]["total"]["amount"]["value"] = 0.01
check(Ai2Web::Ap2.verify_cart_mandate(ap2_tampered, ap2_key) == false, "ap2: tampered cart mandate fails verification")

ap2_pd = Ai2Web::Ap2.payment_details({
  "payment_mandate_contents" => {
    "payment_mandate_id" => "pm_1",
    "payment_details_id" => "pr_x",
    "payment_details_total" => { "label" => "Total", "amount" => Ai2Web::Ap2.amount(29.97, "GBP") },
    "payment_response" => { "method_name" => "card", "payer_email" => "a@b.com" }
  }
})
check(ap2_pd["payment_details_id"] == "pr_x" && ap2_pd["method"] == "card" && ap2_pd["payer_email"] == "a@b.com", "ap2: payment mandate parsed")

puts "\n" + ($failures.zero? ? "ALL PASS" : "#{$failures} FAILED")
exit($failures.zero? ? 0 : 1)
