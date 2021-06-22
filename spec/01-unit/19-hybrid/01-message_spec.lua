local message = require("kong.hybrid.message")


describe("kong.hybrid.message", function()
  it(".new()", function()
    local m = message.new("1c8db62c-7221-47d6-9090-3593851f21cb", "control_plane", "test_topic", "test_message")
    assert.is_table(m)
    assert.equal("1c8db62c-7221-47d6-9090-3593851f21cb", m.src)
    assert.equal("control_plane", m.dest)
    assert.equal("test_topic", m.topic)
    assert.equal("test_message", m.message)
  end)

  it("has the correct metatable", function()
    local m = message.new("1c8db62c-7221-47d6-9090-3593851f21cb", "control_plane", "test_topic", "test_message")
    assert.is_table(getmetatable(m))
    assert.is_table(getmetatable(m).__index)
  end)

  it(":pack()", function()
    local m = message.new("1c8db62c-7221-47d6-9090-3593851f21cb", "control_plane", "test_topic", "test_message")

    local packed = m:pack()
    assert.equal("\x241c8db62c-7221-47d6-9090-3593851f21cb\x0dcontrol_plane\x0atest_topic\x00\x00\x00\x0ctest_message", packed)
  end)

  it(":unpack()", function()
    local ptr = 1
    local packed = "\x241c8db62c-7221-47d6-9090-3593851f21cb\x0dcontrol_plane\x0atest_topic\x00\x00\x00\x0ctest_message"

    local fake_sock = {
      receive = function(self, size)
        local s = packed:sub(ptr, ptr + size - 1)
        ptr = ptr + size

        return s
      end,
    }
    local m = message.unpack_from_socket(fake_sock)

    assert.is_table(m)
    assert.equal("1c8db62c-7221-47d6-9090-3593851f21cb", m.src)
    assert.equal("control_plane", m.dest)
    assert.equal("test_topic", m.topic)
    assert.equal("test_message", m.message)
  end)
end)
