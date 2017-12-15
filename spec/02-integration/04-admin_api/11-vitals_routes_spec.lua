local helpers     = require "spec.helpers"
local dao_helpers = require "spec.02-integration.03-dao.helpers"
local dao_factory = require "kong.dao.factory"
local cassandra   = require "kong.vitals.cassandra.strategy"
local postgres    = require "kong.vitals.postgres.strategy"
local cjson       = require "cjson"
local time        = ngx.time
local fmt         = string.format

dao_helpers.for_each_dao(function(kong_conf)

  if kong_conf.database == "cassandra" then
    -- only test postgres currently
    return
  end

  describe("Admin API Vitals with " .. kong_conf.database, function()
    local client, dao, strategy

    local minute_start_at = time() - ( time() % 60 )
    local node_1 = "20426633-55dc-4050-89ef-2382c95a611e"
    local node_2 = "8374682f-17fd-42cb-b1dc-7694d6f65ba0"
    local node_3 = "20478633-55dc-4050-89ef-2382c95a611f"

    describe("when vitals is enabled", function()
      setup(function()
        dao = assert(dao_factory.new(kong_conf))

        -- start with a clean db
        dao:drop_schema()
        helpers.run_migrations(dao)

        -- to insert test data
        if dao.db_type == "postgres" then
          strategy = postgres.new(dao)
          local q = "create table if not exists " .. strategy:current_table_name() ..
              "(LIKE vitals_stats_seconds INCLUDING defaults INCLUDING constraints INCLUDING indexes)"
          assert(dao.db:query(q))
        else
          strategy = cassandra.new(dao)
        end

        local q = "insert into vitals_node_meta(node_id) values('%s')"
        local nodes = { node_1, node_2, node_3 }

        for i, node in ipairs(nodes) do
          assert(dao.db:query(fmt(q, node)))
        end

        local test_data_1 = {
          { minute_start_at, 0, 0, nil, nil, nil, nil, 0 },
          { minute_start_at + 1, 0, 3, 0, 11, 193, 212, 1 },
          { minute_start_at + 2, 3, 4, 1, 8, 60, 9182, 4 },
        }

        local test_data_2 = {
          { minute_start_at + 1, 1, 5, 0, 99, 25, 144, 9 },
          { minute_start_at + 2, 1, 7, 0, 0, 13, 19, 8 },
        }

        assert(strategy:insert_stats(test_data_1, node_1))
        assert(strategy:insert_stats(test_data_2, node_2))

        assert(helpers.start_kong({
          database = kong_conf.database,
          vitals   = true,
        }))

        client = helpers.admin_client()
      end)

      teardown(function()
        if client then
          client:close()
        end

        helpers.stop_kong()

        dao:truncate_tables()
      end)

      describe("/vitals", function()
        describe("GET", function()
          it("returns data about vitals configuration", function()
            local res = assert(client:send {
              methd = "GET",
              path = "/vitals"
            })
            res = assert.res_status(200, res)
            local json = cjson.decode(res)

            local expected = {
              stats = {
                cache_datastore_hits_total = {
                  levels = {
                    cluster = {
                      intervals = {
                        seconds = { retention_period_seconds = 3600 },
                        minutes = { retention_period_seconds = 90000 },
                      },
                    },
                    nodes = {
                      intervals = {
                        seconds = { retention_period_seconds = 3600 },
                        minutes = { retention_period_seconds = 90000 },
                      },
                    },
                  }
                },
                cache_datastore_misses_total = {
                  levels = {
                    cluster = {
                      intervals = {
                        seconds = { retention_period_seconds = 3600 },
                        minutes = { retention_period_seconds = 90000 },
                      },
                    },
                    nodes = {
                      intervals = {
                        seconds = { retention_period_seconds = 3600 },
                        minutes = { retention_period_seconds = 90000 },
                      },
                    },
                  }
                },
                latency_proxy_request_min_ms = {
                  levels = {
                    cluster = {
                      intervals = {
                        seconds = { retention_period_seconds = 3600 },
                        minutes = { retention_period_seconds = 90000 },
                      },
                    },
                    nodes = {
                      intervals = {
                        seconds = { retention_period_seconds = 3600 },
                        minutes = { retention_period_seconds = 90000 },
                      },
                    },
                  }
                },
                latency_proxy_request_max_ms = {
                  levels = {
                    cluster = {
                      intervals = {
                        seconds = { retention_period_seconds = 3600 },
                        minutes = { retention_period_seconds = 90000 },
                      },
                    },
                    nodes = {
                      intervals = {
                        seconds = { retention_period_seconds = 3600 },
                        minutes = { retention_period_seconds = 90000 },
                      },
                    },
                  }
                },
                latency_upstream_min_ms = {
                  levels = {
                    cluster = {
                      intervals = {
                        seconds = { retention_period_seconds = 3600 },
                        minutes = { retention_period_seconds = 90000 },
                      },
                    },
                    nodes = {
                      intervals = {
                        seconds = { retention_period_seconds = 3600 },
                        minutes = { retention_period_seconds = 90000 },
                      },
                    },
                  }
                },
                latency_upstream_max_ms = {
                  levels = {
                    cluster = {
                      intervals = {
                        seconds = { retention_period_seconds = 3600 },
                        minutes = { retention_period_seconds = 90000 },
                      },
                    },
                    nodes = {
                      intervals = {
                        seconds = { retention_period_seconds = 3600 },
                        minutes = { retention_period_seconds = 90000 },
                      },
                    },
                  }
                },
                requests_proxy_total = {
                  levels = {
                    cluster = {
                      intervals = {
                        seconds = { retention_period_seconds = 3600 },
                        minutes = { retention_period_seconds = 90000 },
                      },
                    },
                    nodes = {
                      intervals = {
                        seconds = { retention_period_seconds = 3600 },
                        minutes = { retention_period_seconds = 90000 },
                      },
                    },
                  }
                },
                requests_consumer_total = {
                  levels = {
                    cluster = {
                      intervals = {
                        seconds = { retention_period_seconds = 3600 },
                        minutes = { retention_period_seconds = 90000 },
                      },
                    },
                    nodes = {
                      intervals = {
                        seconds = { retention_period_seconds = 3600 },
                        minutes = { retention_period_seconds = 90000 },
                      },
                    },
                  }
                },
              }
            }

            assert.same(expected, json)
          end)
        end)
      end)

      describe("/vitals/cluster", function()
        describe("GET", function()
          it("retrieves the vitals seconds cluster data", function()
            local res = assert(client:send {
              methd = "GET",
              path = "/vitals/cluster",
              query = {
                interval = "seconds"
              }
            })
            res = assert.res_status(200, res)
            local json = cjson.decode(res)

            local expected = {
              stats = {
                cluster = {
                  [tostring(minute_start_at)] = { 0, 0, cjson.null, cjson.null, cjson.null, cjson.null, 0 },
                  [tostring(minute_start_at + 1)] = { 1, 8, 0, 99, 25, 212, 10 },
                  [tostring(minute_start_at + 2)] = { 4, 11, 0, 8, 13, 9182, 12 }
                }
              }
            }

            assert.same(expected, json)
          end)

          it("retrieves the vitals minutes cluster data", function()
            local res = assert(client:send {
              methd = "GET",
              path = "/vitals/cluster",
              query = {
                interval = "minutes"
              }
            })
            res = assert.res_status(200, res)
            local json = cjson.decode(res)

            local expected = {
              stats = {
                cluster = {
                  [tostring(minute_start_at)] = { 5, 19, 0, 99, 13, 9182, 22 }
                }
              }
            }

            assert.same(expected, json)
          end)

          it("returns a 400 if called with invalid query param", function()
            local res = assert(client:send {
              methd = "GET",
              path = "/vitals/cluster",
              query = {
                interval = "so-wrong"
              }
            })
            res = assert.res_status(400, res)
            local json = cjson.decode(res)

            assert.same("Invalid query params: interval must be 'minutes' or 'seconds'", json.message)
          end)
        end)
      end)

      describe("/vitals/nodes", function()
        describe("GET", function()
          it("retrieves the vitals seconds data for all nodes", function()
            local res = assert(client:send {
              methd = "GET",
              path = "/vitals/nodes",
              query = {
                interval = "seconds"
              }
            })
            res = assert.res_status(200, res)
            local json = cjson.decode(res)

            local expected = {
              stats = {
                ["20426633-55dc-4050-89ef-2382c95a611e"] = {
                  [tostring(minute_start_at)] = { 0, 0, cjson.null, cjson.null, cjson.null, cjson.null, 0 },
                  [tostring(minute_start_at + 1)] = { 0, 3, 0, 11, 193, 212, 1 },
                  [tostring(minute_start_at + 2)] = { 3, 4, 1, 8, 60, 9182, 4 },
                },
                ["8374682f-17fd-42cb-b1dc-7694d6f65ba0"] = {
                  [tostring(minute_start_at + 1)] = { 1, 5, 0, 99, 25, 144, 9 },
                  [tostring(minute_start_at + 2)] = { 1, 7, 0, 0, 13, 19, 8 },
                }
              }
            }

            assert.same(expected, json)
          end)

          it("retrieves the vitals minutes data for all nodes", function()
            local res = assert(client:send {
              methd = "GET",
              path = "/vitals/nodes",
              query = {
                interval = "minutes"
              }
            })
            res = assert.res_status(200, res)
            local json = cjson.decode(res)

            local expected = {
              stats = {
                [node_1] = {
                  [tostring(minute_start_at)] = { 3, 7, 0, 11, 60, 9182, 5 }
                },
                [node_2] = {
                  [tostring(minute_start_at)] = { 2, 12, 0, 99, 13, 144, 17 }
                }
              }
            }

            assert.same(expected, json)
          end)

          it("returns a 400 if called with invalid query param", function()
            local res = assert(client:send {
              methd = "GET",
              path = "/vitals/nodes",
              query = {
                interval = "so-wrong"
              }
            })
            res = assert.res_status(400, res)
            local json = cjson.decode(res)

            assert.same("Invalid query params: interval must be 'minutes' or 'seconds'", json.message)
          end)
        end)
      end)

      describe("/vitals/nodes/{node_id}", function()
        describe("GET", function()
          it("retrieves the vitals seconds data for a requested node", function()
            local res = assert(client:send {
              methd = "GET",
              path = "/vitals/nodes/" .. node_1,
              query = {
                interval = "seconds"
              }
            })
            res = assert.res_status(200, res)
            local json = cjson.decode(res)

            local expected = {
              stats = {
                ["20426633-55dc-4050-89ef-2382c95a611e"] = {
                  [tostring(minute_start_at)] = { 0, 0, cjson.null, cjson.null, cjson.null, cjson.null, 0 },
                  [tostring(minute_start_at + 1)] = { 0, 3, 0, 11, 193, 212, 1 },
                  [tostring(minute_start_at + 2)] = { 3, 4, 1, 8, 60, 9182, 4 },
                },
              }
            }

            assert.same(expected, json)
          end)

          it("retrieves the vitals minutes data for a requested node", function()
            local res = assert(client:send {
              methd = "GET",
              path = "/vitals/nodes/" .. node_1,
              query = {
                interval = "minutes"
              }
            })
            res = assert.res_status(200, res)
            local json = cjson.decode(res)

            local expected = {
              stats = {
                [node_1] = {
                  [tostring(minute_start_at)] = { 3, 7, 0, 11, 60, 9182, 5 }
                }
              }
            }

            assert.same(expected, json)
          end)

          it("retrieves the empty vitals minutes data for a requested node", function()
            local res = assert(client:send {
              methd = "GET",
              path = "/vitals/nodes/" .. node_3,
              query = {
                interval = "minutes"
              }
            })
            res = assert.res_status(200, res)
            local json = cjson.decode(res)

            local expected = {
              stats = {}
            }

            assert.same(expected, json)
          end)

          it("returns a 400 if called with invalid query param", function()
            local res = assert(client:send {
              methd = "GET",
              path = "/vitals/nodes/" .. node_1,
              query = {
                wrong_query_key = "seconds"
              }
            })
            res = assert.res_status(400, res)
            local json = cjson.decode(res)

            assert.same("Invalid query params: interval must be 'minutes' or 'seconds'", json.message)
          end)

          it("returns a 404 if the node_id does not exist", function()
            local res = assert(client:send {
              methd = "GET",
              path = "/vitals/nodes/totally-fake-uuid",
              query = {
                interval = "seconds"
              }
            })
            res = assert.res_status(404, res)
            local json = cjson.decode(res)

            assert.same("Not found", json.message)
          end)
        end)
      end)

      describe("/vitals/consumers/{username_or_id}", function()
        before_each(function()
          dao.db:truncate_table("consumers")
          dao.db:truncate_table("vitals_consumers")
        end)

        describe("GET", function()
          it("retrieves the consumers seconds data for the entire cluster", function()
            local consumer = assert(helpers.dao.consumers:insert {
              username = "bob",
              custom_id = "1234"
            })

            local now = time()

            assert(strategy:insert_consumer_stats({
              -- inserting minute and second data, but only expecting second data in response
              { consumer.id, now, 60, 45 },
              { consumer.id, now, 1, 17 }
            }, node_1))

            local res = assert(client:send {
              methd = "GET",
              path = "/vitals/consumers/" .. consumer.id,
              query = {
                interval = "seconds"
              }
            })

            res = assert.res_status(200, res)
            local json = cjson.decode(res)

            local expected =  {
              meta = {
                consumer = {
                  id = consumer.id
                },
                interval = "seconds"
              },
              stats = {
                cluster = {
                  [tostring(now)] = 17
                }
              }
            }

            assert.same(expected, json)
          end)

          it("returns a 404 if called with invalid consumer_id path param", function()
            local res = assert(client:send {
              methd = "GET",
              path = "/vitals/consumers/fake-uuid",
              query = {
                interval = "seconds"
              }
            })
            res = assert.res_status(404, res)
            local json = cjson.decode(res)

            assert.same("Not found", json.message)
          end)

          it("returns a 400 if called with invalid query param", function()
            local consumer = assert(helpers.dao.consumers:insert {
              username = "bob",
              custom_id = "1234"
            })

            local res = assert(client:send {
              methd = "GET",
              path = "/vitals/consumers/" .. consumer.id,
              query = {
                wrong_query_key = "seconds"
              }
            })
            res = assert.res_status(400, res)
            local json = cjson.decode(res)

            assert.same("Invalid query params: interval must be 'minutes' or 'seconds'", json.message)
          end)
        end)
      end)

      describe("/vitals/consumers/{username_or_id}/nodes", function()
        before_each(function()
          dao.db:truncate_table("consumers")
          dao.db:truncate_table("vitals_consumers")
        end)

        describe("GET", function()
          it("retrieves the consumers minutes data for all nodes", function()
            local consumer = assert(helpers.dao.consumers:insert {
              username = "bob",
              custom_id = "1234"
            })

            -- make sure the data we enter is in the same minute, so we
            -- can make a correct assertion
            local at = time() - 10
            local minute_start_at = at - (at % 60)
            at = minute_start_at + 5

            -- a couple requests, a few seconds apart
            assert(strategy:insert_consumer_stats({
              { consumer.id, at, 1, 2 },
              { consumer.id, at + 10, 1, 1 },
            }, node_1))

            local res = assert(client:send {
              methd = "GET",
              path = "/vitals/consumers/" .. consumer.id .. "/nodes",
              query = {
                interval = "minutes"
              }
            })

            res = assert.res_status(200, res)
            local json = cjson.decode(res)

            local expected = {
              meta = {
                consumer = {
                  id = consumer.id
                },
                interval = "minutes"
              },
              stats = {
                [node_1] = {
                  [tostring(minute_start_at)] = 3
                }
              }
            }

            assert.same(expected, json)
          end)

          it("returns a 404 if called with invalid consumer_id path param", function()
            local res = assert(client:send {
              methd = "GET",
              path = "/vitals/consumers/fake-uuid",
              query = {
                interval = "seconds"
              }
            })
            res = assert.res_status(404, res)
            local json = cjson.decode(res)

            assert.same("Not found", json.message)
          end)

          it("returns a 400 if called with invalid query param", function()
            local consumer = assert(helpers.dao.consumers:insert {
              username = "bob",
              custom_id = "1234"
            })

            local res = assert(client:send {
              methd = "GET",
              path = "/vitals/consumers/" .. consumer.id,
              query = {
                wrong_query_key = "seconds"
              }
            })
            res = assert.res_status(400, res)
            local json = cjson.decode(res)

            assert.same("Invalid query params: interval must be 'minutes' or 'seconds'", json.message)
          end)
        end)
      end)
    end)

    describe("when vitals is not enabled", function()
      setup(function()
        dao = assert(dao_factory.new(kong_conf))

        helpers.run_migrations(dao)

        assert(helpers.start_kong({
          database = kong_conf.database,
          vitals   = false,
        }))

        client = helpers.admin_client()
      end)

      teardown(function()
        if client then
          client:close()
        end

        helpers.stop_kong()
      end)

      describe("GET", function()

        it("responds 404", function()
          local res = assert(client:send {
            methd = "GET",
            path = "/vitals"
          })
          assert.res_status(404, res)
        end)
      end)
    end)
  end)

end)
