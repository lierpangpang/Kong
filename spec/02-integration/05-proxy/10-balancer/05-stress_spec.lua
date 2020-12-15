local bu = require "spec.fixtures.balancer_utils"
local helpers = require "spec.helpers"


local https_server = helpers.https_server
local stress_generator = helpers.stress_generator

for _, consistency in ipairs(bu.consistencies) do
  for _, strategy in helpers.each_strategy() do

    describe("proxying under stress #" .. strategy .. " #" .. consistency, function()
      local bp

      lazy_setup(function()
        bp = bu.get_db_utils_for_dc_and_admin_api(strategy, {
          "routes",
          "services",
          "plugins",
          "upstreams",
          "targets",
        })

        local fixtures = {
          dns_mock = helpers.dns_mock.new()
        }

        fixtures.dns_mock:A {
          name = "a.stressed.test",
          address = "127.0.0.1",
        }

        assert(helpers.start_kong({
          database   = strategy,
          nginx_conf = "spec/fixtures/custom_nginx.template",
          db_update_frequency = 0.1,
          worker_consistency = consistency,
          worker_state_update_frequency = bu.CONSISTENCY_FREQ,
        }, nil, nil, fixtures))

      end)

      lazy_teardown(function()
        helpers.stop_kong()
      end)

      it("round-robin with single target", function()
        bu.begin_testcase_setup(strategy, bp)
        local upstream_name, upstream_id = bu.add_upstream(bp)
        local port = bu.add_target(bp, upstream_id, "a.stressed.test")
        local api_host = bu.add_api(bp, upstream_name)
        bu.end_testcase_setup(strategy, bp, consistency)

        -- setup target server
        local server = https_server.new(port, "a.stressed.test")
        server:start()

        -- setup stress test
        local proxy_ip = helpers.get_proxy_ip(false)
        local proxy_port = helpers.get_proxy_port(false)
        local generator1 = stress_generator.new("http", proxy_ip, proxy_port)

        -- Go hit them with our test requests
        generator1:run("/", {["Host"] = api_host}, 3, 200)

        helpers.wait_until(function()
          return generator1:is_running() == false
        end, 10)

        -- collect server results
        local count = server:shutdown()
        local results = generator1:get_results()

        assert.are.equal(0, results.proxy_failures)
        assert.are.equal(results.successes, count.total)
      end)

      it("round-robin with multiple targets", function()
        bu.begin_testcase_setup(strategy, bp)
        local upstream_name, upstream_id = bu.add_upstream(bp)
        local port1 = bu.add_target(bp, upstream_id, "a.stressed.test")
        local port2 = bu.add_target(bp, upstream_id, "a.stressed.test")
        local port3 = bu.add_target(bp, upstream_id, "a.stressed.test")
        local api_host = bu.add_api(bp, upstream_name)
        bu.end_testcase_setup(strategy, bp, consistency)

        -- setup target servers
        local server1 = https_server.new(port1, "a.stressed.test")
        local server2 = https_server.new(port2, "a.stressed.test")
        local server3 = https_server.new(port3, "a.stressed.test")
        server1:start()
        server2:start()
        server3:start()

        -- setup stress test
        local proxy_ip = helpers.get_proxy_ip(false)
        local proxy_port = helpers.get_proxy_port(false)
        local generator1 = stress_generator.new("http", proxy_ip, proxy_port)

        -- Go hit them with our test requests
        generator1:run("/", {["Host"] = api_host}, 3, 200)

        helpers.wait_until(function()
          return generator1:is_running() == false
        end, 10)

        -- collect server results
        local count1 = server1:shutdown()
        local count2 = server2:shutdown()
        local count3 = server3:shutdown()
        local results = generator1:get_results()

        assert.are.equal(0, results.proxy_failures)
        assert.are.equal(results.successes, count1.total + count2.total + count3.total)
      end)

      it("consistent-hashing", function()
        bu.begin_testcase_setup(strategy, bp)
        local upstream_name, upstream_id = bu.add_upstream(bp, {
          hash_on = "header",
          hash_on_header = "x-stressed",
        })
        local port1 = bu.add_target(bp, upstream_id, "localhost")
        local port2 = bu.add_target(bp, upstream_id, "localhost")
        local port3 = bu.add_target(bp, upstream_id, "localhost")
        local api_host = bu.add_api(bp, upstream_name)
        bu.end_testcase_setup(strategy, bp, consistency)

        -- setup target servers
        local server1 = https_server.new(port1, "localhost")
        local server2 = https_server.new(port2, "localhost")
        local server3 = https_server.new(port3, "localhost")
        server1:start()
        server2:start()
        server3:start()

        -- setup stress test
        local proxy_ip = helpers.get_proxy_ip(false)
        local proxy_port = helpers.get_proxy_port(false)
        local generator1 = stress_generator.new("http", proxy_ip, proxy_port)

        -- Go hit them with our test requests
        local headers = {
          ["Host"] = api_host,
          ["x-stressed"] = "gogo",
        }
        generator1:run("/", headers, 3, 200)

        helpers.wait_until(function()
          return generator1:is_running() == false
        end, 10)

        -- collect server results
        local count1 = server1:shutdown()
        local count2 = server2:shutdown()
        local count3 = server3:shutdown()
        local results = generator1:get_results()

        assert.are.equal(0, results.proxy_failures)
        assert.are.equal(results.successes, count1.total + count2.total + count3.total)
      end)

      it("least-connections", function()
        bu.begin_testcase_setup(strategy, bp)
        local upstream_name, upstream_id = bu.add_upstream(bp, {
          algorithm = "least-connections",
        })
        local port1 = bu.add_target(bp, upstream_id, "localhost")
        local port2 = bu.add_target(bp, upstream_id, "localhost")
        local port3 = bu.add_target(bp, upstream_id, "localhost")
        local api_host = bu.add_api(bp, upstream_name)
        bu.end_testcase_setup(strategy, bp, consistency)

        -- setup target servers
        local server1 = https_server.new(port1, "localhost")
        local server2 = https_server.new(port2, "localhost")
        local server3 = https_server.new(port3, "localhost")
        server1:start()
        server2:start()
        server3:start()

        -- setup stress test
        local proxy_ip = helpers.get_proxy_ip(false)
        local proxy_port = helpers.get_proxy_port(false)
        local generator1 = stress_generator.new("http", proxy_ip, proxy_port)

        -- Go hit them with our test requests
        generator1:run("/", {["Host"] = api_host}, 3, 200)

        helpers.wait_until(function()
          return generator1:is_running() == false
        end, 10)

        -- collect server results
        local count1 = server1:shutdown()
        local count2 = server2:shutdown()
        local count3 = server3:shutdown()
        local results = generator1:get_results()

        assert.are.equal(0, results.proxy_failures)
        assert.are.equal(results.successes, count1.total + count2.total + count3.total)
      end)

    end)

  end
end
