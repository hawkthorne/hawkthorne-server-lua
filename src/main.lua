local socket = require "socket"
require 'vendor/lube'
local Server = require 'server'
local server = Server.getSingleton()

local correctVersion = require 'correctversion'

if correctVersion then

  require 'utils'
  local debugger = require 'debugger'
  local Gamestate = require 'vendor/gamestate'
  local Level = require 'level'
  local camera = require 'camera'
  local fonts = require 'fonts'
  local sound = require 'vendor/TEsound'
  local window = require 'window'
  local cli = require 'vendor/cliargs'
  local mixpanel = require 'vendor/mixpanel'
  local character = require 'character'
  local cheat = require 'cheat'
  local Player = require 'player'
  local Server = require 'server'

  local players = server.players -- players[player_id] = player
  local levels = server.levels  -- levels[level_name] = level

  -- XXX Hack for level loading
  Gamestate.Level = Level
  local data, msg_or_ip, port_or_nil
  local entity, cmd, parms
  -- Get the current version of the game
  local function getVersion()
    return split(love.graphics.getCaption(), "v")[2]
  end

function server_print(...)
  print(...)
  io.flush()
end
  function love.load(arg)
    server_print("Beginning hawkthorne server loop.")
    table.remove(arg, 1)

    love.graphics.setDefaultImageFilter('nearest', 'nearest')
    camera:setScale(window.scale, window.scale)
    love.graphics.setMode(window.screen_width, window.screen_height)

  end

  function love.update(dt)
    local dt = math.min(0.033333333, dt)
    for level_name,level in pairs(levels) do
        level:update(dt)
    end
    
    --
    -- [NOTE: strictly, we could have just used receivefrom (and its 
    -- counterpart, sendto) in the client. there's nothing special about the
    -- functions to prevent it, indeed. send/receive are just convenience
    -- functions, sendto/receive from are the real workers.]
    local data, msg_or_ip, port_or_nil = server:receivefrom()
    if data then
        io.flush()
        -- more of these funky match patterns!
        local entity, cmd, parms = data:match("^(%S*) (%S*) (.*)")
        if cmd == 'keypressed' then
            local button = parms:match("^(%S*)")
            local player = players[entity]
            local level = player.level
            level = Gamestate.get(level)
            player.key_down[button] = true
            if level then level:keypressed( button, player) end
            print("keypressed:"..button)
        elseif cmd == 'keyreleased' then
            local button = parms:match("^(%S*)")
            local level = players[entity].level
            level = Gamestate.get(level)
            local player = players[entity]
            player.key_down[button] = false
            player.key_down[button] = false
            if level then level:keyreleased( button, player) end
            print("keyreleased:"..button)
        elseif cmd == 'keydown' then
            -- local button = parms:match("^(%S*)")
            -- local level = players[entity].level
            -- local player = players[entity]
        elseif cmd == 'enter' then
            local level = parms:match("^(%S*)")
            levels[level] = levels[level] or Gamestate.load(level)
            level = levels[level]
            local player = players[entity]
            level:enter(require("overworld"),"main",player)
        elseif cmd == 'update' then
            --sends an update back to the client
            local level = parms:match("^(%S*)")
            if level ~= '$' then
            assert(level,"Must update a specific level")
            levels[level] = levels[level] or Gamestate.load(level)
            levels[level].nodes = levels[level].nodes or {}
            --update objects for client(s)
            for i, node in pairs(levels[level].nodes) do

                  if node.draw and node.position then
                  local type,name
 
                  --note: super_type was created because of inconsistent type use
                  type = node.super_type
                  name = node.name
                  
                    local objectBundle  = {level = level,
                      x = node.position.x,y = node.position.y,
                      state = node.state,
                      position = node.animation and node:animation().position,
                      direction = node.direction,
                      id = i,
                      name = name,
                      type = type,
                      person = node.properties and node.properties.person,
                      testVal = node.enemytype,
                    }
                    server:sendtoip(string.format("%s %s %s", i, 'updateObject', lube.bin:pack_node(objectBundle)), msg_or_ip,  port_or_nil)
                end
            end
            for i, plyr in pairs(players) do
                    local playerBundle  = {id = plyr.id,
                                          level = plyr.level,
                                          x = plyr.position.x, y = plyr.position.y,
                                          name = plyr.character.name,
                                          costume = plyr.character.costume,
                                          state = plyr.character.state,
                                          position = plyr.character:animation() and 
                                                     plyr.character:animation().position,
                                          direction = plyr.character.direction}

                server:sendtoip(string.format("%s %s %s", i, 'updatePlayer', lube.bin:pack_node(playerBundle)), msg_or_ip,  port_or_nil)
            end
            end
            --update players for client(s)
       elseif cmd == 'register' then
            local name,costume = parms:match("^(%S*) (.*)")
            server_print("registering a new player:", entity)
            server_print("msg_or_ip:", msg_or_ip)
            server_print("port_or_nil:", port_or_nil)
            server_print()
            players[entity] = Player.new()
            players[entity].id = entity
            --todo:remove town dependence
            players[entity].level = 'overworld'
            players[entity].ip_address = msg_or_ip
            players[entity].character.name=name
            players[entity].character.costume=costume
            print("registered")
        elseif cmd == 'enterLevel' then
            local level = parms:match("^(%S*)")
            players[entity].level = level
        elseif cmd == 'unregister' then
            server_print("unregistering a player:", entity)
            server_print("msg_or_ip:", msg_or_ip)
            server_print("port_or_nil:", port_or_nil)
            players[entity] = nil
        elseif cmd == 'quit' then
            running = false;
        else
            server_print("unrecognized command:'"..(cmd or 'nil').."'")
            server_print()
        end
    elseif msg_or_ip == 'closed' then
        --ignoring
        --TODO: deal with close correctly
    elseif msg_or_ip ~= 'timeout' then
        error("Unknown network error: "..tostring(msg))
    end
  end
end
