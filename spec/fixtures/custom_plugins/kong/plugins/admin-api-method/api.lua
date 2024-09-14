return {
  ["/method_without_exit"] = {
    GET = function()
      kong.response.set_status(201)
      kong.response.set_header("x-foo", "bar")
      ngx.print("hello")
    end,
  },
  ["/parsed_params"] = {
    POST = function(self, db, helpers, parent)
      kong.response.exit(200, self.params)
    end,
  },
}
