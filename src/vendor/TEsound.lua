local Server = require 'server'
local TEsound = {}

local server = Server.getSingleton()

local soundList = {}

function TEsound.playSfx(file)
    local msg = string.format("%s %s %s","broadcast","sound",file)
    for k,v in pairs(server.clients) do
        soundList[k] = soundList[k] or {} 
        table.insert(soundList[k],msg)
    end
end

function TEsound.getSounds(entity)
    local entitySounds = soundList[entity] or {}
    soundList[entity] = {}
    return entitySounds
end

return TEsound