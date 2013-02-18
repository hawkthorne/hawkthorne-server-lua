local socket = require "socket"
local Messages = require "messages"

local Server = {}
Server.__index = Server
Server.singleton = nil
Server.DEBUG = true

local function __NULL__() end

function Server.new(port)
    local server = {}
    setmetatable(server, Server)
    server.levels = {}  -- levels[level_name] = level
    server.clients = {} -- clients[player_id] = {port, ip, lastUpdate, player}
    local prefix = "server"..os.date("%Y_%m_%d")
    local suffix = ".log"
    local file_name = prefix..suffix
    local i = 1
    while(file_exists(file_name)) do
        file_name = prefix.."_"..i..suffix
        i = i+1
    end
    if Server.DEBUG then
        server.log_file = io.open(file_name, "w")
    else
        server.log_file = {write=__NULL__}
    end

    
    server.udp = socket.udp()
    server.udp:settimeout(0.0333)
    server.port = port or 12346
    server.udp:setsockname('*', server.port)
    lube.bin:setseperators("?","!")
    return server
end

function file_exists(name)
   local f=io.open(name,"r")
   if f~=nil then io.close(f) return true else return false end
end

--returns the same server every time
function Server.getSingleton()
    Server.singleton = Server.singleton or Server.new()
    return Server.singleton
end


function Server:getIp(entity)
  error("deprecated for lack of transparency")
  return self.clients[entity].ip
end

function Server:getPort(entity)
  error("deprecated for lack of transparency")
  return self.clients[entity].port
end
function Server:receivefrom()
    local data, msg_or_ip, port_or_nil = self.udp:receivefrom()
    local entity = data and data:match("^(%S*) (.*)")
    local now
    if msg_or_ip and msg_or_ip ~= 'timeout' and entity then 
        self.clients[entity] = self.clients[entity] or {}
        self.clients[entity].ip = msg_or_ip
        self.clients[entity].port=port_or_nil
        self.clients[entity].lastUpdate=os.time()
    end
    if data then
        self.log_file:write("FROM CLIENT: "..(data or "<nil>").."\n")
        self.log_file:write("           : "..msg_or_ip..","..port_or_nil.."\n")
        now=socket.gettime()
        self.log_file:write(string.format('       Time: %s,%3d',os.date("%X",now),select(2,math.modf(now))*1000).."\n")
        --TODO: call less frequently
        --self.log_file:flush()
    end
    return data, msg_or_ip, port_or_nil
end

function Server:sendtoplayer(message,entity)
    assert(type(entity)=="string","String required")
    if self.clients then
        self:sendtoip(message,self.clients[entity].ip,self.clients[entity].port)
    else
       print("bad player: "..(entity or 'nil'))
    end
end

function Server:sendtoip(message,ip,port)
    if self.clients then
        self.udp:sendto(message,ip,port)
        self.log_file:write("TO CLIENT: '"..(message or "<nil>").."'\n")
        self.log_file:write("         : "..ip..","..port.."\n")
        now=socket.gettime()
        self.log_file:write(string.format('     Time: %s,%3d',os.date("%X",now),select(2,math.modf(now))*1000).."\n")
        --TODO: call less frequently
        --self.log_file:flush()
    else
        print("bad player: "..(player_entity or 'nil'))
    end
end

function Server:unregister(entity)
    --FIXME: unregister bug
    -- old character is never properly removed.
    self.log_file:write("ERROR: cannot unregister")
    local level = self.clients[entity].player.level
    Messages.broadcast(string.format("%s %s %s %s", entity, 'stateSwitch',level,'gameover'))
    self.clients[entity] = nil
end

return Server