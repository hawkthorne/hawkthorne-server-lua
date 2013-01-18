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
    
    server.udp = socket.udp()
    server.udp:settimeout(0)
    server.port = 12345 --unnecessary
    server.udp:setsockname('*', server.port)
    lube.bin:setseperators("?","!")
    return server
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
        print("FROM CLIENT: "..(data or "<nil>"))
        print("           : "..msg_or_ip..","..port_or_nil)
    end
    return data, msg_or_ip, port_or_nil
end

function Server:sendtoplayer(message,player_entity)
    assert(type(player_entity)=="string","String required")
    if player_entity=="*" and self.clients then
        print("broadcasting: ")
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
        print("broadcasting: '".. message.."'")
        for k,v in pairs(self.clients) do
            self.udp:sendto(message, v.ip, v.port or port)
        end
    elseif self.clients then
        self.udp:sendto(message,ip,port)
        print("TO CLIENT: '"..(message or "<nil>").."'")
        print("         : "..ip..","..port)
    else
        print("bad player: "..(player_entity or 'nil'))
    end
end


return Server