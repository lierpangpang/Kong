local helpers = require "spec.helpers"
local cjson = require "cjson"


for _, strategy in helpers.each_strategy() do
  describe("#testme /ca_certificates with DB: #" .. strategy, function ()
    local client
    local db

    local original_ca_certificate = [[
-----BEGIN CERTIFICATE-----
MIIFrTCCA5WgAwIBAgIUFQe9z25yjw26iWzS+P7+hz1zx6AwDQYJKoZIhvcNAQEL
BQAwXjELMAkGA1UEBhMCVVMxCzAJBgNVBAgMAkNBMQswCQYDVQQHDAJTRjENMAsG
A1UECgwES29uZzEUMBIGA1UECwwLRW5naW5lZXJpbmcxEDAOBgNVBAMMB3Jvb3Rf
Y2EwHhcNMjEwMzA0MTEyMjM0WhcNNDEwMjI3MTEyMjM0WjBeMQswCQYDVQQGEwJV
UzELMAkGA1UECAwCQ0ExCzAJBgNVBAcMAlNGMQ0wCwYDVQQKDARLb25nMRQwEgYD
VQQLDAtFbmdpbmVlcmluZzEQMA4GA1UEAwwHcm9vdF9jYTCCAiIwDQYJKoZIhvcN
AQEBBQADggIPADCCAgoCggIBAKKjido39I5SEmPhme0Z+hG0buOylXg+jmqHpJ/K
rs+dSq/PsJCjSke81eOP2MFa5duyBxdnXmMJwZYxuQ91bKxdzWVE9ZgCJgNJYsB6
y5+Fe7ypERwa2ebS/M99FFJ3EzpF017XdsgnSfVh1GEQOZkWQ1+7YrEUEgtwN5lO
MVUmj1EfoL+jQ/zwxwdxpLu3dh3Ica3szmx3YxqIPRnpyoYYqbktjL63gmFCjLeW
zEXdVZyoisdaA4iZ9e/wmuLR2/F4cbZ0SjU7QULZ2Zt/SCrs3CaJ3/ZAa6s84kjg
JBMav+GxbvATSuWQEajiVQrkW9HvXD/NUQBCzzZsOfpzn0044Ls7XvWDCCXs+xtG
Uhd5cJfmlcbHbZ9PU1xTBqdbwiRX+XlmX7CJRcfgnYnU/B3m5IheA1XKYhoXikgv
geRwq5uZ8Z2E/WONmFts46MLSmH43Ft+gIXA1u1g3eDHkU2bx9u592lZoluZtL3m
bmebyk+5bd0GdiHjBGvDSCf/fgaWROgGO9e0PBgdsngHEFmRspipaH39qveM1Cdh
83q4I96BRmjU5tvFXydFCvp8ABpZz9Gj0h8IRP+bK5ukU46YrEIxQxjBee1c1AAb
oatRJSJc2J6zSYXRnQfwf5OkhpmVYc+1TAyqPBfixa2TQ7OOhXxDYsJHAb7WySKP
lfonAgMBAAGjYzBhMB0GA1UdDgQWBBT00Tua7un0KobEs1aXuSZV8x4Q7TAfBgNV
HSMEGDAWgBT00Tua7un0KobEs1aXuSZV8x4Q7TAPBgNVHRMBAf8EBTADAQH/MA4G
A1UdDwEB/wQEAwIBhjANBgkqhkiG9w0BAQsFAAOCAgEAgI8CSmjvzQgmnzcNwqX5
o+KBWEMHJEqQfowaZE7o6xkvEljb1YHRDE0hlwUtD1vbKUthoHD8Mqim3No5z4J0
dEE+mXQ3zlJWKl5gqHs9KtcLhk51mf4VJ2TW8Z7AoE2OjWSnycLNdlpqUvxzCQOn
CIhvyDfs4OV1RYywbfiLLmzTCYT7Mt5ye1ZafoRNZ37DCnI/uqoOaMb+a6VaE+0F
ZXlDonXmy54QUmt6foSG/+kYaqdVLribsE6H+GpePmPTKKOvgE1RutR5+nvMJUB3
+zMQSPVVYLzizwV+Tq9il81qNQB2hZGvM8iSRraBNn8mwpx7M6kcoJ4gvCA3kHCI
rmuuzlhkNcmZYh0uG378CzhdEOV+JMmuCh4xt2SbQIr5Luqm/+Xoq4tDplKoUVkC
DScxPoFNoi9bZYW/ppcaeX5KT3Gt0JBaCfD7d0CtbUp/iPS1HtgXTIL9XiYPipsV
oPLtqvfeORl6aUuqs1xX8HvZrSgcld51+r8X31YIs6feYTFvlbfP0/Jhf2Cs0K/j
jhC0sGVdWO1C0akDlEBfuE5YMrehjYrrOnEavtTi9+H0vNaB+BGAJHIAj+BGj5C7
0EkbQdEyhB0pliy9qzbPtN5nt+y0I1lgN9VlFMub6r1u5novNzuVm+5ceBrxG+ga
T6nsr9aTE1yghO6GTWEPssw=
-----END CERTIFICATE-----
]]
    local original_ca_certificate_digest = "c0b27aebdb87568a1e6250cf4e015bc0b31524df5b03acda2f99f0ac79199b1d"

    lazy_setup(function()
      helpers.setenv("CERT", original_ca_certificate)
      local _
      _, db = helpers.get_db_utils(strategy, {
        "ca_certificates",
        "vaults",
      },
      nil, {
        "env",
        "mock",
      })

      assert(helpers.start_kong {
        database = strategy,
        prefix = helpers.test_conf.prefix,
        nginx_conf = "spec/fixtures/custom_nginx.template",
        vaults = "env,mock",
      })

      client = assert(helpers.admin_client(10000))

      local res = client:put("/vaults/test-vault", {
        headers = { ["Content-Type"] = "application/json" },
        body = {
          name = "env",
        },
      })

      assert.res_status(200, res)

      local res = client:put("/vaults/mock-vault", {
        headers = { ["Content-Type"] = "application/json" },
        body = {
          name = "mock",
        },
      })

      assert.res_status(200, res)
    end)

    before_each(function()
      client = assert(helpers.admin_client(10000))
    end)

    after_each(function()
      if client then
        client:close()
      end
    end)

    lazy_teardown(function()
      helpers.stop_kong()
      helpers.unsetenv("CERT")
    end)

    describe("should create ca certificates correctly", function ()
      before_each(function()
        db.ca_certificates:truncate()
      end)

      it("should create a non-referenced ca certificate correctly", function ()
        local res, err = client:post("/ca_certificates", {
          headers = { ["Content-Type"] = "application/json" },
          body = {
            cert = original_ca_certificate,
          },
        })
        assert.is_nil(err)
        local body = assert.res_status(201, res)
        local ca_certificate = cjson.decode(body)

        assert.equal(ca_certificate.cert, ca_certificate.cert)
        assert.same(ca_certificate.cert_digest, original_ca_certificate_digest)
      end)

      it("should not create a referenced ca certificate without ca digest", function ()
        local res = client:post("/ca_certificates", {
          headers = { ["Content-Type"] = "application/json" },
          body = {
            cert = "{vault://test-vault/cert}",
          },
        })
        local body = assert.res_status(400, res)
        assert.matches("the cert_digest of a vault referenced CA certificate must be provided manually", body)
      end)

      it("should create a referenced ca certificate with ca digest", function ()
        local res, err = client:post("/ca_certificates", {
          headers = { ["Content-Type"] = "application/json" },
          body = {
            cert = "{vault://test-vault/cert}",
            cert_digest = original_ca_certificate_digest,
          },
        })
        assert.is_nil(err)
        local body = assert.res_status(201, res)
        local ca_certificate = cjson.decode(body)

        assert.equal(ca_certificate.cert, ca_certificate.cert)
        assert.same(ca_certificate.cert_digest, original_ca_certificate_digest)
      end)
    end)
  end)
end
