-- This software is copyright Kong Inc. and its licensors.
-- Use of the software is subject to the agreement between your organization
-- and Kong Inc. If there is no such agreement, use is governed by and
-- subject to the terms of the Kong Master Software License Agreement found
-- at https://konghq.com/enterprisesoftwarelicense/.
-- [ END OF LICENSE 0867164ffc95e54f04670b5169c09574bdbd9bba ]

local typedefs = require "kong.db.schema.typedefs"

return {
	name 				= "group_rbac_roles",
	generate_admin_api  = false,
  admin_api_nested_name = "roles",
	primary_key 		= { "group", "rbac_role" },
  db_export = false,
	fields = {
		{ created_at     = typedefs.auto_timestamp_s },
		{ updated_at     = typedefs.auto_timestamp_s },
		{ group = { description = "The group associated with the RBAC role", type = "foreign", required = true, reference = "groups", on_delete = "cascade" } },
		{ rbac_role = { description = "The RBAC role", type = "foreign", required = true, reference = "rbac_roles", on_delete = "cascade" } },
		{ workspace = { description = "The workspace associated with the RBAC role.", type = "foreign", required = true, reference = "workspaces", on_delete = "cascade" } },
	},
}