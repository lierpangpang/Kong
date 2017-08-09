local json = require "cjson.safe"
local crud = require "kong.api.crud_helpers"

local function issuer(row)
  local configuration = row.configuration
  if configuration then
    configuration = json.decode(configuration)
    if configuration then
      row.configuration = configuration

    else
      row.configuration = {}
    end
  end

  local keys = row.keys
  if keys then
    keys = json.decode(keys)
    if keys then
      row.keys = keys

    else
      row.keys = {}
    end
  end

  return row
end

return {
  ["/openid-connect/issuers/"] = {
    GET = function(self, dao)
      crud.paginated_set(self, dao.oic_issuers, issuer)
    end,
  },
  ["/openid-connect/issuers/:id"] = {
    GET = function(self, dao)
      crud.get({ id = self.params.id }, dao.oic_issuers, issuer)
    end,
    DELETE = function(self, dao)
      crud.delete({ id = self.params.id }, dao.oic_issuers)
    end
  },
  ["/openid-connect/signouts/"] = {
    GET = function(self, dao)
      crud.paginated_set(self, dao.oic_signout)
    end,
  },
  ["/openid-connect/signouts/:id"] = {
    GET = function(self, dao)
      crud.get({ id = self.params.id }, dao.oic_signout)
    end,
    DELETE = function(self, dao)
      crud.delete({ id = self.params.id }, dao.oic_signout)
    end
  },
  ["/openid-connect/sessions/"] = {
    GET = function(self, dao)
      crud.paginated_set(self, dao.oic_session)
    end,
  },
  ["/openid-connect/sessions/:id"] = {
    GET = function(self, dao)
      crud.get({ id = self.params.id }, dao.oic_session)
    end,
    DELETE = function(self, dao)
      crud.delete({ id = self.params.id }, dao.oic_session)
    end
  },
  ["/openid-connect/revoked/"] = {
    GET = function(self, dao)
      crud.paginated_set(self, dao.oic_revoked)
    end,
  },
  ["/openid-connect/revoked/:id"] = {
    GET = function(self, dao)
      crud.get({ id = self.params.id }, dao.oic_revoked)
    end,
    DELETE = function(self, dao)
      crud.delete({ id = self.params.id }, dao.oic_revoked)
    end
  },
}
