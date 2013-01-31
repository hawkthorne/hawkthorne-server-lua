local socket = require "socket"

local Server = {}
Server.__index = Server
Server.singleton = nil

function Server.new()
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
    server.log_file = io.open(file_name, "w")
    
    server.udp = socket.udp()
    server.udp:settimeout(0)
    server.port = 12345
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

function Server:addNewClient(entity,ip,port)
    if not self.clients[entity] then 
        self.clients[entity] = {ip = ip,port=port}
    end
end

function Server:getIp(entity)
  return self.clients[entity].ip
end

function Server:getPort(entity)
  return self.clients[entity].port
end
function Server:receivefrom()
    --require("mobdebug").start()
    local data, msg_or_ip, port_or_nil = self.udp:receivefrom()
    local entity = data and data:match("^(%S*) (.*)")
    if msg_or_ip and msg_or_ip ~= 'timeout' and entity and not self.clients[entity] then 
        self:addNewClient(entity,msg_or_ip,port_or_nil)
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
    if player_entity=="*" and self.clients then
        for k,v in pairs(self.clients) do
            self:sendtoip(message, v.ip, v.port or port)
        end
    elseif self.clients then
        self:sendtoip(message,self:getIp(player_entity),self:getPort(player_entity))
    else
       print("bad player: "..(player_entity or 'nil'))
    end
end

function Server:sendtoip(message,ip,port)
    if ip=="*" then
        for k,v in pairs(self.clients) do
            self.udp:sendto(message, v.ip, v.port or port)
        end
    elseif self.clients then
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