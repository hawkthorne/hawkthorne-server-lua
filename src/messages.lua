local Server = require 'server'
local Messages = {}

local server = Server.getSingleton()

local soundList = {}

function Messages.broadcast(msg)
    for k,v in pairs(server.clients) do
        soundList[k] = soundList[k] or {} 
        table.insert(soundList[k],msg)
    end
end

function Messages.getMessages(entity)
    local entitySounds = soundList[entity] or {}
    soundList[entity] = {}
    return entitySounds
end

return Messages