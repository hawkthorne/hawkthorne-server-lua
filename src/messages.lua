local Messages = {}

local soundList = {}

function Messages.broadcast(msg)
    --inline to prevent circular reference
    for k,v in pairs(require("server").getSingleton().clients) do
        soundList[k] = soundList[k] or {} 
        table.insert(soundList[k],msg)
    end
end

function Messages.getMessages(entity)
    local entitySounds = soundList[entity] or {}
    soundList[entity] = {}
    return entitySounds
end

--TODO a Messages.sendToPlayer(msg) function, useful for private chat

return Messages