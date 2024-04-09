-- This software is copyright Kong Inc. and its licensors.
-- Use of the software is subject to the agreement between your organization
-- and Kong Inc. If there is no such agreement, use is governed by and
-- subject to the terms of the Kong Master Software License Agreement found
-- at https://konghq.com/enterprisesoftwarelicense/.
-- [ END OF LICENSE 0867164ffc95e54f04670b5169c09574bdbd9bba ]

local ee_helpers = require "spec-ee.helpers"
local helpers    = require "spec.helpers"
local clear_license_env = require("spec-ee.helpers").clear_license_env
local get_portal_and_vitals_key = require("spec-ee.helpers").get_portal_and_vitals_key

local function close_clients(clients)
  for idx, client in ipairs(clients) do
    client:close()
  end
end


local function client_request(params)
  local client = assert(helpers.admin_client())
  local res = assert(client:send(params))
  res.body = res:read_body()

  close_clients({ client })

  return res
end


local function gui_client_request(params)
  local portal_gui_client = assert(ee_helpers.portal_gui_client())
  local res = assert(portal_gui_client:send(params))
  res.body = res:read_body()

  close_clients({ portal_gui_client })
  return res
end



local function configure_portal(db, workspace_name)
  local workspace = db.workspaces:select_by_name(workspace_name)

  if not workspace then
    workspace = db.workspaces:insert({
      name = workspace_name
    })
  end

  db.workspaces:update({
    id = workspace.id
  },
  {
    config = {
      portal = true,
    }
  })
end




local function create_workspace_files(workspace_name, files, portal_conf)
  if not portal_conf then
    portal_conf = {
      path = "portal.conf.yaml",
      contents = [[
        name: Kong Portal
        theme:
          name: test-theme
      ]]
    }
  end

  -- -- portal conf
  client_request({
    method = "POST",
    path = "/" .. workspace_name .. "/files",
    body = portal_conf,
    headers = {["Content-Type"] = "application/json"},
  })

  -- theme conf
  client_request({
    method = "POST",
    path = "/" .. workspace_name .. "/files",
    body = {
      path = "themes/test-theme/theme.conf.yaml",
      contents = [[
        name: Kong
      ]]
    },
    headers = {["Content-Type"] = "application/json"},
  })

  -- content conf
  client_request({
    method = "POST",
    path = "/" .. workspace_name .. "/files",
    body = {
      path = "content/index.txt",
      contents = [[
        ---
        title: Home
        ---
      ]]
    },
    headers = {["Content-Type"] = "application/json"},
  })

  -- layout-base
  client_request({
    method = "POST",
    path = "/" .. workspace_name .. "/files",
    body = {
      path = "themes/test-theme/layouts/base.html",
      contents = [[
        <h1>
          BASE FILE
        </h1>
      ]]
    },
    headers = {["Content-Type"] = "application/json"},
  })

  for _, file in ipairs(files) do
    client_request({
      method = "POST",
      path = "/" .. workspace_name .. "/files",
      body = file,
      headers = {["Content-Type"] = "application/json"},
    })
  end

  gui_client_request({
    method = "GET",
    path = "/" .. workspace_name,
  })
  ngx.sleep(1)
end


for _, strategy in helpers.each_strategy() do
for _, workspace in ipairs({ "default", "doggos"}) do

  describe("sitemap #" .. strategy, function()
    local db
    local reset_license_data

      setup(function()
        reset_license_data = clear_license_env()
        _, db, _ = helpers.get_db_utils(strategy, { "files" })
        assert(helpers.start_kong({
          database    = strategy,
          license_path = "spec-ee/fixtures/mock_license.json",
          portal      = true,
          portal_and_vitals_key = get_portal_and_vitals_key(),
          portal_gui_use_subdomains = false,
          portal_is_legacy = false,
        }))
        configure_portal(db, workspace)
      end)

      teardown(function()
        helpers.stop_kong()
        reset_license_data()
      end)

      before_each(function()
        db:truncate("files")
      end)

      it("can properly display 'content' type router files", function()
        create_workspace_files(workspace, {
          {
            path = "content/home.txt",
            contents = "---layout: base.html---"
          },
          {
            path = "content/home.md",
            contents = "---layout: base.html---"
          },
          {
            path = "content/docs.txt",
            contents = "---layout: base.html---"
          },
          {
            path = "content/docs.md",
            contents = "---layout: base.html---"
          },
          {
            path = "content/about.txt",
            contents = "---layout: base.html---"
          },
          {
            path = "content/about.md",
            contents = "---layout: base.html---"
          }
        })

        local res = gui_client_request({
          method = "GET",
          path = "/" .. workspace .. "/sitemap.xml",
        })
        assert.equals(res.status, 200)
        for _, v in ipairs({ "/home", "/docs", "/about" }) do
          local _, count = string.gsub(res.body, workspace .. v, "")
          assert.equals(1, count)
        end
      end)

      it("can properly display 'explicit' type router files", function()
        create_workspace_files(workspace, {
          {
            path = "content/home.txt",
            contents = [[
              ---
              layout: base.html
              route: /home_explicit
              ---
            ]]
          },
          {
            path = "content/home.md",
            contents = [[
              ---
              layout: base.html
              route: /home_explicit
              ---
            ]]
          },
          {
            path = "content/docs.txt",
            contents = [[
              ---
              layout: base.html
              route: /docs_explicit
              ---
            ]]
          },
          {
            path = "content/docs.md",
            contents = [[
              ---
              layout: base.html
              route: /docs_explicit
              ---
            ]]
          },
          {
            path = "content/about.txt",
            contents = [[
              ---
              layout: base.html
              route: /about_explicit
              ---
            ]]
          },
          {
            path = "content/about.md",
            contents = [[
              ---
              layout: base.html
              route: /about_explicit
              ---
            ]]
          }
        })

        helpers.wait_until(function()
          return pcall(function()
            local res = gui_client_request({
              method = "GET",
              path = "/" .. workspace .. "/sitemap.xml",
            })
            assert.equals(res.status, 200)
            for _, v in ipairs({ "/home_explicit", "/docs_explicit", "/about_explicit" }) do
              local _, count = string.gsub(res.body, workspace .. v, "")
              assert.equals(1, count)
            end
          end)
        end)
      end)

      it("can properly display 'collection' type router files", function()
        create_workspace_files(workspace, {
          {
            path = "content/_guides/home.txt",
            contents = "---title: guide---"
          },
          {
            path = "content/_guides/home.md",
            contents = "---title: guide---"
          },
          {
            path = "content/_guides/docs.txt",
            contents = "---title: guide---"
          },
          {
            path = "content/_guides/docs.md",
            contents = "---title: guide---"
          },
          {
            path = "content/_guides/about.txt",
            contents = "---title: guide---"
          },
          {
            path = "content/_guides/about.md",
            contents = "---title: guide---"
          },
        }, {
          path = "portal.conf.yaml",
          contents = [[
            name: Kong Portal
            theme:
              name: test-theme
            collections:
              guides:
                output: true
                route: /:collection/:name
                layout: base.html
          ]]
        })

        helpers.wait_until(function()
          return pcall(function()
            local res = gui_client_request({
              method = "GET",
              path = "/" .. workspace .. "/sitemap.xml",
            })

            assert.equals(res.status, 200)
            for _, v in ipairs({ "/guides/home", "/guides/docs", "/guides/about" }) do
              local _, count = string.gsub(res.body, workspace .. v, "")
              assert.equals(1, count)
            end
          end)
        end)
      end)

      it("hides routes that have private tag", function()
        create_workspace_files(workspace, {
          {
            path = "content/home.txt",
            contents = "---title: guide---"
          },
          {
            path = "content/private.md",
            contents = "---private: true---"
          },
        })

        local res = gui_client_request({
          method = "GET",
          path = "/" .. workspace .. "/sitemap.xml",
        })

        assert.equals(res.status, 200)
        local _, count = string.gsub(res.body, workspace .. "/home", "")
        assert.equals(1, count)
        _, count = string.gsub(res.body, workspace .. "/private", "")
        assert.equals(0, count)
      end)
  end)
end
end