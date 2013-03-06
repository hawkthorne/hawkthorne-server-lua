local correctVersion = require 'correctversion'

if correctVersion then

  require 'utils'
  require 'vendor/lube'

  local debugger = require 'debugger'
  local Gamestate = require 'vendor/gamestate'
  local sound = require 'vendor/TEsound'
  local timer = require 'vendor/timer'
  local cli = require 'vendor/cliargs'
  local mixpanel = require 'vendor/mixpanel'

  local debugger = require 'debugger'
  local Level = require 'level'
  local camera = require 'camera'
  local fonts = require 'fonts'
  local window = require 'window'
  local cli = require 'vendor/cliargs'
  local mixpanel = require 'vendor/mixpanel'
  local character = require 'character'
  local cheat = require 'cheat'
  local Player = require 'player'
  local socket = require "socket"
  local Server = require 'server'
  local Messages = require 'messages'

  local server = nil
  local levels = nil -- levels[level_name] = level
  
  local objectBundle = {}
  local playerBundle = {}
  
  local kickTimer = 0
  --amount of idle time a player is allowed to have
  local KICK_OUT_TIME = 5

  -- XXX Hack for level loading
  Gamestate.Level = Level
  local data, msg_or_ip, port_or_nil
  local entity, cmd, parms
  
  math.randomseed( os.time() )

  -- Get the current version of the game
  local function getVersion()
    return split(love.graphics.getCaption(), "v")[2]
  end

  function love.load(arg)
    
    table.remove(arg, 1)
    cli:add_option("-p, --port=NAME", "The port to use")
    cli:add_option("-d, --debugger", "Enable debugger")

    local args = cli:parse(arg)
    if args["port"] ~= "" then
      local port = args["port"]
      Server.singleton = Server.new(port)
    end
    if args["d"] ~= "" then
      local port = args["d"]
      Server.DEBUG = true
    end
    server = Server.getSingleton()
    levels = server.levels  -- levels[level_name] = level


    love.graphics.setDefaultImageFilter('nearest', 'nearest')
    camera:setScale(window.scale, window.scale)
    love.graphics.setMode(window.screen_width, window.screen_height)
  end

  function love.update(dt)
    local dt = math.min(0.033333333, dt)
    for level_name,level in pairs(levels) do
        level:update(dt)
    end
    
    --every math.huge seconds, try to boot idle players
    kickTimer = kickTimer + dt
    if kickTimer > math.huge then
        for id, client in pairs(server.clients) do
            if client.lastUpdate + KICK_OUT_TIME < socket.gettime() then
                server:unregister(id)
            end
        end
        kickTimer = 0
    end
    
    --
    -- [NOTE: strictly, we could have just used receivefrom (and its 
    -- counterpart, sendto) in the client. there's nothing special about the
    -- functions to prevent it, indeed. send/receive are just convenience
    -- functions, sendto/receive from are the real workers.]
    local data, msg_or_ip, port_or_nil = server:receivefrom()

    if data then
        -- more of these funky match patterns!
        local entity, cmd, parms = data:match("^(%S*) (%S*) (.*)")
        local player = server.clients[entity].player
        if player==nil and cmd~='register' then
             server.log_file:write("ERROR: unauthorized player:",entity)
        elseif cmd == 'keypressed' then
            --require("mobdebug").start()
            local button = parms:match("^(%S*)")
            local player = server.clients[entity].player
            local level = player.level
            level = Gamestate.get(level)
            player.key_down[button] = true
            if level then level:keypressed( button, player) end
        elseif cmd == 'keyreleased' then
            local button = parms:match("^(%S*)")
            local level = server.clients[entity].player.level
            level = Gamestate.get(level)
            local player = server.clients[entity].player
            player.key_down[button] = false
            if level then level:keyreleased( button, player) end
        elseif cmd == 'enter' then
            local levelName = parms:match("^(%S*)")
            levels[levelName] = levels[levelName] or Gamestate.load(levelName)
            local level = levels[levelName]
            assert(level)
            local player = server.clients[entity].player
            level:enter(require("overworld"),"main",player)
              for i, node in pairs(level.nodes) do
                    local type,name
 
                    --note: super_type was created because of inconsistent type use
                    type = node.super_type
                    name = node.name

                    if node.draw and (node.position or (node.x and node.y)) and type~="sprite" then

                        local framePosition = 1
                        if _G.type(node.animation)== "function" then
                            framePosition = node:animation().position
                        elseif node.animation then
                            framePosition = node.animation.position
                        end
                   
                        local my_direction
                        if node.direction=="right" or node.direction=="left" then
                            my_direction = node.direction
                        elseif node.direction==1 then
                            my_direction = "right"
                        elseif node.direction==-1 then
                            my_direction = "left"
                        elseif not node.direction then
                            my_direction = "right"
                        else
                            error("direction of type :"..node.direction.." is not understood")
                        end
                    
                        --Note: objectBundle was made local to this file to decrease the need for automatic memory deallocation
                        objectBundle.level = levelName
                        objectBundle.x = math.round(node.x or node.position.x) + (node.offset_x or 0)
                        objectBundle.y = math.round(node.y or node.position.y) + (node.offset_y or 0)
                        objectBundle.state = node.state
                        objectBundle.position = framePosition
                        objectBundle.direction = my_direction
                        objectBundle.id = node.id
                        objectBundle.name = name
                        objectBundle.type = type
                        objectBundle.width = node.width
                        objectBundle.height = node.height
                        objectBundle.spritePath = node.spritePath
                        objectBundle.sheetPath = node.sheetPath
                        server:sendtoip(string.format("%s %s %s", objectBundle.id, 'updateObject', lube.bin:pack_node(objectBundle)), msg_or_ip,  port_or_nil)
                    end
                end
        elseif cmd == 'update' then
            --sends an update back to the client
            local player = server.clients[entity].player
            local levelName = parms:match("^(%S*)")
            if levelName ~= '$' then
                assert(levelName,"Must update a specific level")
                levels[levelName] = levels[levelName] or Gamestate.load(levelName)
                levels[levelName].nodes = levels[levelName].nodes or {}
                --update objects for client(s)
                --TODO: create appropriate index 'i' for node
                for i, node in pairs(levels[levelName].nodes) do
                    local type,name
 
                    --note: super_type was created because of inconsistent type use
                    type = node.super_type
                    name = node.name

                    --if node.draw and (node.position or (node.x and node.y)) and type~="sprite" then
                    if node.isEnemy or node.isMovingPlatform then
                        local framePosition = 1
                        if _G.type(node.animation)== "function" then
                            framePosition = node:animation().position
                        elseif node.animation then
                            framePosition = node.animation.position
                        end
                   
                        local my_direction
                        if node.direction=="right" or node.direction=="left" then
                            my_direction = node.direction
                        elseif node.direction==1 then
                            my_direction = "right"
                        elseif node.direction==-1 then
                            my_direction = "left"
                        elseif not node.direction then
                            my_direction = "right"
                        else
                            error("direction of type :"..node.direction.." is not understood")
                        end
                    
                        objectBundle.level = levelName
                        objectBundle.x = math.round(node.x or node.position.x) + (node.offset_x or 0)
                        objectBundle.y = math.round(node.y or node.position.y) + (node.offset_y or 0)
                        objectBundle.state = node.state
                        objectBundle.position = framePosition
                        objectBundle.direction = my_direction
                        objectBundle.id = node.id
                        server:sendtoip(string.format("%s %s %s", objectBundle.id, 'updateObject', lube.bin:pack_node(objectBundle)), msg_or_ip,  port_or_nil)
                    end
                end
                for i, client in pairs(server.clients) do
                    local plyr = client.player
                    if plyr then
                        playerBundle.id = plyr.id
                        playerBundle.level = plyr.level
                        playerBundle.x = plyr.position.x
                        playerBundle.y = plyr.position.y
                        playerBundle.name = plyr.character.name
                        playerBundle.costume = plyr.character.costume
                        playerBundle.state = plyr.character.state
                        playerBundle.position = plyr.character:animation() and 
                                                        plyr.character:animation().position
                        playerBundle.direction = plyr.character.direction
                        playerBundle.username = plyr.username
    
                        server:sendtoip(string.format("%s %s %s", i, 'updatePlayer', lube.bin:pack_node(playerBundle)), msg_or_ip,  port_or_nil)
                    else
                        print("you may be receiving messages from an unautorized player")
                    end
                end
            end
            --update players for client(s)
            for _,msg in pairs(sound.getSounds(entity)) do
                    server:sendtoip(msg, msg_or_ip,  port_or_nil)
            end
            for _,msg in pairs(Messages.getMessages(entity)) do
                server:sendtoip(msg, msg_or_ip,  port_or_nil)
            end
       elseif cmd == 'changeCostume' then
            local name,costume = parms:match("^(%S*) (.*)")
            server.clients[entity].player.character.name=name
            server.clients[entity].player.character.costume=costume
       elseif cmd == 'register' then
            local name,costume,username = parms:match("^(%S*) (%S*) (.*)")
            server.clients[entity].player = Player.new()
            server.clients[entity].player.id = entity
            --todo:remove town dependence
            server.clients[entity].player.level = 'overworld'
            server.clients[entity].player.ip = msg_or_ip
            server.clients[entity].player.character.name=name
            server.clients[entity].player.character.costume=costume
            server.clients[entity].player.username=username          
        elseif cmd == 'unregister' then
            server:unregister(parms)

            --clients[parms].player = nil
        elseif cmd == 'quit' then
            running = false;
        else
            print("unrecognized command:'"..(cmd or 'nil').."'")
        end
    elseif msg_or_ip == 'closed' then
        print("close message received")
        --ignoring
        --TODO: deal with close correctly
    elseif msg_or_ip ~= 'timeout' then
        error("Unknown network error: "..tostring(port_or_nil)..",".. tostring(msg_or_ip).."\n"..
              "Ensure this server hasn't already been started")
    end
  end
end
