local thread = require("thread")
local event = require("event")

local RadioPlayer = {}

function RadioPlayer.new(bodyData, keypadProxy, buttonId)
    local self = {}
    
    self.id = "player_" .. tostring(math.random(100000, 999999))
    self.eventName = "control_" .. self.id
    
    self.isPaused = false
    
    local function playLoop()
        local cursor = 1
        local totalBytes = #bodyData

        while cursor <= totalBytes do
            if self.isPaused then
                local _, action = event.pull(self.eventName)
                if action == "resume" then self.isPaused = false
                elseif action == "stop" then break
                elseif action == "rewind" then cursor = 1; self.isPaused = false end
            else
                local delay = string.byte(bodyData, cursor)
                cursor = cursor + 1

                if delay > 0 then
                    local e, action = event.pull(delay * 0.05, self.eventName)
                    
                    if e == self.eventName then
                        if action == "pause" then self.isPaused = true; goto continue
                        elseif action == "stop" then break
                        elseif action == "rewind" then cursor = 1; goto continue end
                    end
                end

                if cursor > totalBytes then break end

                local noteCount = string.byte(bodyData, cursor)
                cursor = cursor + 1
                
                if noteCount > 0 then
                    local chordNotes = {}
                    for i = 1, noteCount do
                        local b = string.byte(bodyData, cursor)
                        cursor = cursor + 1
                        table.insert(chordNotes, math.floor(b/36) .. ":" .. math.floor((b%36)/3) .. ":" .. (b%3))
                    end
                    
                    keypadProxy.setKeyCommand(buttonId, table.concat(chordNotes, "-"))
                    keypadProxy.pressKey(buttonId)
                end
            end
            ::continue::
        end
    end

    self.playerThread = thread.create(playLoop)
    
    function self:pause()
        event.push(self.eventName, "pause")
    end

    function self:resume()
        event.push(self.eventName, "resume")
    end

    function self:stop()
        event.push(self.eventName, "stop")
    end

    function self:rewind()
        event.push(self.eventName, "rewind")
    end

    function self:getStatus()
        if not self.playerThread then return "dead" end
        return self.playerThread:status()
    end

    return self
end

return RadioPlayer