local Gamestate = require 'vendor/gamestate'
local Queue = require 'queue'
local anim8 = require 'vendor/anim8'
local tmx = require 'vendor/tmx'
local HC = require 'vendor/hardoncollider'
local Timer = require 'vendor/timer'
local Tween = require 'vendor/tween'
local music = {}

local node_cache = {}
local tile_cache = {}

local Player = require 'player'
local Floor = require 'nodes/floor'
local Floorspace = require 'nodes/floorspace'
local Floorspaces = require 'floorspaces'
local Platform = require 'nodes/platform'
local Wall = require 'nodes/wall'

--local ach = (require 'achievements').new()

local function limit( x, min, max )
    return math.min(math.max(x,min),max)
end

local function load_tileset(name)
    if tile_cache[name] then
        return tile_cache[name]
    end
    
    local tileset = tmx.load(require("maps/" .. name))
    tile_cache[name] = tileset
    return tileset
end

local function load_node(name)
    if node_cache[name] then
        return node_cache[name]
    end

    local node = require('nodes/' .. name)
    node_cache[name] = node
    return node
end

local function on_collision(dt, shape_a, shape_b, mtv_x, mtv_y)
    local node_a, node_b

    if shape_a.player and shape_b.player then
        node_a = shape_a.player
        node_b = shape_b.player
        --if a player possesses multiple bounding boxes
        -- the following should prevent them from colliding
        if node_a == node_b then return end
        node_b.players_touched = node_b.players_touched or {}
        node_a.players_touched = node_a.players_touched or {}
        node_b.players_touched[node_a] = true
        node_a.players_touched[node_b] = true
        --suspicions confirmed, someone was using mtv_x incorrectly elsewhere
        -- and the problem trickled down.
        -- mtv_x and mtv_y should have different signs depending on the object order
        -- as follows:
        if node_a.collide then
            node_a:collide(node_b, dt, mtv_x, mtv_y)
        end
        if node_b.collide then
            node_b:collide(node_a, dt, -mtv_x, -mtv_y)
        end
    return

    elseif shape_a.player then
        node_a = shape_a.player
        node_b = shape_b.node
        node_b.players_touched = node_b.players_touched or {}
        node_b.players_touched[node_a] = true
    elseif shape_b.player then
        node_b = shape_b.player
        node_a = shape_a.node
        node_a.players_touched = node_a.players_touched or {}
        node_a.players_touched[node_b] = true
    else
        node_a = shape_a.node
        node_b = shape_b.node
    end

    if node_a.collide then
        node_a:collide(node_b, dt, mtv_x, mtv_y)
    end
    if node_b.collide then
        node_b:collide(node_a, dt, mtv_x, mtv_y)
    end

end

-- this is called when two shapes stop colliding
local function collision_stop(dt, shape_a, shape_b)
    local node_a, node_b

    if shape_a.player and shape_b.player then
        node_a = shape_a.player
        node_b = shape_b.player
        --if a player possesses multiple bounding boxes
        -- the following should prevent them from colliding
        if node_a == node_b then return end
        node_b.players_touched = node_b.players_touched or {}
        node_a.players_touched = node_a.players_touched or {}
        node_b.players_touched[node_a] = nil
        node_a.players_touched[node_b] = nil
    elseif shape_a.player then
        node_a = shape_a.player
        node_b = shape_b.node
        node_b.players_touched = node_b.players_touched or {}
        node_b.players_touched[node_a] = nil
    elseif shape_b.player then
        node_b = shape_b.player
        node_a = shape_a.node
        node_a.players_touched = node_a.players_touched or {}
        node_a.players_touched[node_b] = nil
    else
        node_a = shape_a.node
        node_b = shape_b.node
    end

    if node_a.collide_end then
        node_a:collide_end(node_b, dt)
    end
    if node_b.collide_end then
        node_b:collide_end(node_a, dt)
    end
end

local function setBackgroundColor(map)
    local prop = map.properties
    if not prop.red then
        love.graphics.setBackgroundColor(0, 0, 0)
        return
    end
    love.graphics.setBackgroundColor(tonumber(prop.red),
                                     tonumber(prop.green),
                                     tonumber(prop.blue))
end

local function getCameraOffset(map)
    local prop = map.properties
    if not prop.offset then
        return 0
    end
    return tonumber(prop.offset) * map.tilewidth
end

local function getTitle(map)
    local prop = map.properties
    return prop.title or "UNKNOWN"
end

local function getSoundtrack(map)
    local prop = map.properties
    return prop.soundtrack or "level"
end

local Level = {}
Level.__index = Level
Level.level = true
Level.objectCount = 0
function Level.generateObjectId()
    Level.objectCount = Level.objectCount + 1
    return Level.objectCount
end

function Level.new(name)
    local level = {}
    setmetatable(level, Level)
    
    level.over = false
    level.name = name

    assert( love.filesystem.exists( "maps/" .. name .. ".lua" ),
            "maps/" .. name .. ".lua not found.\n\n" ..
            "Have you generated your maps lately?\n\n" ..
            "LINUX / OSX: run 'make maps'\n" ..
            "WINDOWS: use tmx2lua to generate\n\n" ..
            "Check the documentation for more info."
    )

    level.map = require("maps/" .. name)
    level.background = load_tileset(name)
    level.collider = HC(100, on_collision, collision_stop)
    level.offset = getCameraOffset(level.map)
    level.music = getSoundtrack(level.map)
    level.spawn = (level.map.properties and level.map.properties.respawn) or 'hallway'
    level.title = getTitle(level.map)
 
    level:panInit()

    --level.player = Player.factory(level.collider)
    level.boundary = {
        width =level.map.width  * level.map.tilewidth,
        height=level.map.height * level.map.tileheight
    }

    level.events = Queue.new()
    level.nodes = {}
    level.doors = {}

    for k,v in pairs(level.map.objectgroups.nodes.objects) do
        NodeClass = load_node(v.type)
        local node
        if NodeClass then
            v.objectlayer = 'nodes'
            node = NodeClass.new( v, level.collider )
            if(v.name=="") then v.name = nil end
            node.players_touched = node.players_touched or {}
            --I'm sorry I had to do this, but the type was being used inconsistently
            node.super_type = v.type
            node.name = v.name or node.type
            --I'm sorry I had to do this, but it removes the possibility of type collisions
            --TODO: refactor level.nodes to add nodes as follows:
            --  level.nodes[node] = node
            --  makes removal very easy
            node.containerLevel = level
            node.id = Level.generateObjectId()
            level.nodes[node] = node
        end
        if v.type == 'door' then
            if v.name then
                if v.name == 'main' then
                    assert(not level.default_position,"Level "..name.." must have only one 'main' door")
                    level.default_position = {x=v.x, y=v.y}
                end
                level.doors[v.name] = {x=v.x, y=v.y, node=node}
            end
        end
    end
    assert(level.default_position,"Level "..name.." has no 'main' door")

    if level.map.objectgroups.floor then
        for k,v in pairs(level.map.objectgroups.floor.objects) do
            v.objectlayer = 'floor'
            Floor.new(v, level.collider)
        end
    end

    if level.map.objectgroups.floorspace then
        level.floorspace = true
        for k,v in pairs(level.map.objectgroups.floorspace.objects) do
            v.objectlayer = 'floorspace'
            local node =  Floorspace.new(v, level)
            node.id = Level.generateObjectId()
            level.nodes[node] = node
        end
    end

    if level.map.objectgroups.platform then
        for k,v in pairs(level.map.objectgroups.platform.objects) do
            v.objectlayer = 'platform'
            local node = Platform.new(v, level.collider)
            node.id = Level.generateObjectId()
            level.nodes[node] = node
        end
    end

    if level.map.objectgroups.wall then
        for k,v in pairs(level.map.objectgroups.wall.objects) do
            Wall.new(v, level.collider)
        end
    end

    level.players = {}
    level:restartLevel()
    return level
end

function Level:restartLevel()
    Floorspaces:init()
end


function Level:enter( previous, door , player)
    --ach:achieve('enter ' .. self.name)
    self.players[player.id] = player
    --only restart if it's an ordinary level
    if previous.level or previous==Gamestate.get('overworld') then
        self.previous = previous
        self:restartLevel()
    end
    if previous == Gamestate.get('overworld') then
        player.character:respawn()
    end

    player.boundary = {
        width = self.map.width * self.map.tilewidth,
        height = self.map.height * self.map.tileheight
    }

   --if you entered through a doorway, then position yourself with it
   if door then
        player.position = {
            x = math.floor(self.doors[ door ].x + self.doors[ door ].node.width / 2 - player.width / 2),
            y = math.floor(self.doors[ door ].y + self.doors[ door ].node.height - player.height)
        }
        if self.doors[ door ].warpin then
            player.character:respawn()
        end
        if self.doors[ door ].node then
            self.doors[ door ].node:show()
            player.freeze = false
        end
    end

    --this seems borderline disastrous
    for i,node in pairs(self.nodes) do
        if node.enter then node:enter(previous) end
    end
    player:enter(self)
end

function Level:init()
end

local function leaveLevel(level, levelName, doorName)
  local destination = Gamestate.get(levelName)
            
  if level == destination then
    level.player.position = { -- Copy, or player position corrupts entrance data
      x = level.doors[doorName].x + level.doors[doorName].node.width / 2 - level.player.width / 2,
      y = level.doors[doorName].y + level.doors[doorName].node.height - level.player.height
    }
    return
  end

  Gamestate.switch(levelName, doorName)
end

function Level:update(dt)
    --levels only progress when they have a player
    if not self.players then return end
    
    --TODO:find a better way to associate players with levels
    -- I shouldn't need to loop through the server's players
    --TODO:maybe add a test to determine if player.level is correct
    
--    local plyrs = require("server").getSingleton().players
--    for _,plyr in pairs(plyrs) do
--      if not plyr.attack_box then
--        plyr:enter(Gamestate.get(plyr.level))
--      end
--      self.players[plyr.id] = plyr
--    end
--    
    Tween.update(dt)
    for _,player in pairs(self.players) do
        player:update(dt)
        for _,node in pairs(self.nodes) do
            if node.update then node:update(dt, player) end
        end
    end
    --ach:update(dt)
 
    self.collider:update(dt)

    self:updatePan(dt)

    Timer.update(dt)
    --apply accumulated changes that can't be that can't be executed mid-update
    --TODO:reimplement processActionQueue
    --self:processActionQueue()

    local exited, levelName, doorName = self.events:poll('exit')
    if exited then
      leaveLevel(self, levelName, doorName)
    end
end


function Level:quit()
    if self.respawn ~= nil then
        Timer.cancel(self.respawn)
    end
end

function Level:leave()
end

function Level:exit(levelName, doorName)
end


function Level:draw()
end

-- draws the nodes based on their location in the y axis
-- this is an accurate representation of the location
-- written by NimbusBP1729, refactored by jhoff
function Level:floorspaceNodeDraw()
end

function Level:leave(player)
    if not player then return end
    self.collider:remove(player.bb)
    self.collider:remove(player.attack_box.bb)
    player.bb = nil
    player.attack_box.bb = nil
    --assert(nil,"Need to associate a player with leaving")
    --ach:achieve('leave ' .. self.name)
    for i,node in pairs(self.nodes) do
        if node.leave then node:leave() end
        if node.collide_end then
            node:collide_end(player)
        end
    end
    self.players[player.id] = nil
end

function Level:keyreleased( button , player)
    player:keyreleased( button, self )
end

function Level:keypressed( button , player)
    
    if button == 'INTERACT' and player.character.state ~= 'idle' then
        return
    end

    for i,node in pairs(self.nodes) do
        node.players_touched = node.players_touched or {}
        if node.players_touched[player] and node.keypressed then
            if node:keypressed( button, player) then
              return true
            end
        end
    end
   
    if player:keypressed( button ) then
      return true
    end

end

function Level:panInit()
    self.pan_delay = 1
    self.pan_distance = 80
    self.pan_speed = 140
end

--this should superficially change the sprite state on the server-side
--this should move the camera on the client-side
function Level:updatePan(dt)
    for _,player in pairs(self.players) do
        player.pan = player.pan or 0
        player.pan_hold_up = player.pan_hold_up or 0
        player.pan_hold_down = player.pan_hold_down or 0
        local up = player.key_down['UP'] and not player.controlState:is('ignoreMovement')
        local down = player.key_down['DOWN'] and not player.controlState:is('ignoreMovement')

        if up and player.velocity.x == 0 then
            player.pan_hold_up = player.pan_hold_up + dt
        else
            player.pan_hold_up = 0
        end
    
        if down and player.velocity.x == 0 then
            player.pan_hold_down = player.pan_hold_down + dt
        else
            player.pan_hold_down = 0
        end

        if up and player.pan_hold_up >= self.pan_delay then
            player.gaze_state = 'gaze'
            player.pan = math.max( player.pan - dt * self.pan_speed, -self.pan_distance )
        elseif down and player.pan_hold_down >= self.pan_delay then
            --we currently have no sprite for looking down
            --player.crouch_state = 'gaze'
            player.pan = math.min( player.pan + dt * self.pan_speed, self.pan_distance )
        else
            player.gaze_state = player:getSpriteStates()[player.current_state_set].gaze_state
            if player.pan > 0 then
                player.pan = math.max( player.pan - dt * self.pan_speed, 0 )
            elseif player.pan < 0 then
                player.pan = math.min( player.pan + dt * self.pan_speed, 0 )
            end
        end
    end
end

return Level
