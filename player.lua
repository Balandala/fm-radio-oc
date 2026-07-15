local component = require("component")
local os = require("os")
local io = require("io")
local shell = require("shell")

local keypad = component.proxy(component.getPrimary("rbmk_keypad").address)

local args = shell.parse(...)

local file = io.open(args[1], "rb")
local data = file:read("*a")
file:close()

print("Играет файл:", args[1])

local cursor = 1
local totalBytes = #data

while cursor < totalBytes do

----------------
-- Read delay --
----------------
local delay = string.byte(data, cursor)
cursor = cursor + 1

if delay > 0 then
    os.sleep(delay * 0.05)
end

---------------------
-- Read note count --
---------------------
local noteCount = string.byte(data, cursor)
cursor = cursor + 1

------------------
-- Read notes ---
-----------------
local chordNotes = {}
if noteCount > 0 then
        local chordNotes = {} 
        
        for i = 1, noteCount do
            local noteByte = string.byte(data, cursor)
            cursor = cursor + 1

            local inst = math.floor(noteByte / 36)
            local note = math.floor((noteByte % 36) / 3)
            local oct = noteByte % 3
            
            local noteString = inst .. ":" .. note .. ":" .. oct
            table.insert(chordNotes, noteString)
        end
        
        local command = table.concat(chordNotes, "-")
        
        keypad.setKeyCommand(1, command)
        keypad.pressKey(1)
    end

end

