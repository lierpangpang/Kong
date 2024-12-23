local pl_path = require("pl.path")
local shell = require("resty.shell")
local resty_signal = require("resty.signal")


local CONSTANTS = require("spec.internal.constants")


local function make(workdir, specs)
  workdir = pl_path.normpath(workdir or pl_path.currentdir())

  for _, spec in ipairs(specs) do
    local ok, _, stderr = shell.run(string.format("cd %s; %s", workdir, spec.cmd), nil, 0)
    assert(ok, stderr)
  end

  return true
end


local grpc_target_proc


local function start_grpc_target()
  local ngx_pipe = require("ngx.pipe")
  assert(make(CONSTANTS.GRPC_TARGET_SRC_PATH, {
    {
      cmd    = "make clean && make all",
    },
  }))
  grpc_target_proc = assert(ngx_pipe.spawn({ CONSTANTS.GRPC_TARGET_SRC_PATH .. "/target" }, {
      merge_stderr = true,
  }))

  return true
end


local function stop_grpc_target()
  if grpc_target_proc then
    grpc_target_proc:kill(resty_signal.signum("QUIT"))
    grpc_target_proc = nil
  end
end


local function get_grpc_target_port()
  return 15010
end


return {
  start_grpc_target = start_grpc_target,
  stop_grpc_target = stop_grpc_target,
  get_grpc_target_port = get_grpc_target_port,
}

