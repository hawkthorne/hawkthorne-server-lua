local socket = require "socket"

local Server = {}
Server.__index = Server
Server.singleton = nil
Server.DEBUG = false

local function __NULL__() end

function Server.new(port)
    local server = {}
    setmetatable(server, Server)
    server.players = {} -- players[player_id] = player
    server.levels = {}  -- levels[level_name] = level
    server.clients = {}
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
    server.udp:settimeout(0)
    server.port = port or 12345
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
  return self.clients[entity].ip
end

function Server:getPort(entity)
  return self.clients[entity].port
end
function Server:receivefrom()
    local data, msg_or_ip, port_or_nil = self.udp:receivefrom()
    local entity = data and data:match("^(%S*) (.*)")
    if msg_or_ip and msg_or_ip ~= 'timeout' and entity then 
        self.clients[entity] = {ip = ip,port=port,lastUpdate=os.time()}
    end
    if data then
        self.log_file:write("FROM CLIENT: "..(data or "<nil>").."\n")
        self.log_file:write("           : "..msg_or_ip..","..port_or_nil.."\n")
        --TODO: call less frequently
        --self.log_file:flush()
    end
    return data, msg_or_ip, port_or_nil
end

function Server:sendtoplayer(message,player_entity)
    assert(type(player_entity)=="string","String required")
    if self.clients then
        self:sendtoip(message,self:getIp(player_entity),self:getPort(player_entity))
    else
       print("bad player: "..(player_entity or 'nil'))
    end
end

function Server:sendtoip(message,ip,port)
    if self.clients then
        self.udp:sendto(message,ip,port)
        self.log_file:write("TO CLIENT: '"..(message or "<nil>").."'\n")
        self.log_file:write("         : "..ip..","..port.."\n")
        --TODO: call less frequently
        --self.log_file:flush()
    else
        print("bad player: "..(player_entity or 'nil'))
    end
end


return Server