local fs = require("filesystem")
local component = require("component")
local os = require("os")
local thread = require("thread")
local event = require("event")
local term = require("term")
local fmplayer = require("fmplayer")

local MUSIC_DIR = "/usr/tracks/"
local keypad = component.rbmk_keypad
local trackDatabase = {}

local function safePrint(msg)
    local _, y = term.getCursor()
    term.setCursor(1, y)
    term.clearLine()
    print(msg)
    
    local prompt = "/>"
    io.write(prompt) 
    term.setCursor(3, y+2)
end

local function formatTime(ticks)
    local totalSeconds = math.floor(ticks * 0.05)
    local minutes = math.floor(totalSeconds / 60)
    local seconds = totalSeconds % 60
    return string.format("%02d:%02d", minutes, seconds)
end

-- ==========================================
-- ЛОГИКА БАЗЫ ДАННЫХ И ПЛЕЙЛИСТА
-- ==========================================
local function scanLibrary()
    trackDatabase = { ["All"] = {} }
    for file in fs.list(MUSIC_DIR) do
        if string.sub(file, -5) == ".mbin" then
            local path = MUSIC_DIR .. file
            table.insert(trackDatabase["All"], path)
            
            local f = io.open(path, "rb")
            if f then
                local header = f:read(6)
                if header and #header == 6 then
                    local genreLen = string.byte(header, 6)
                    if genreLen > 0 then
                        local genreStr = f:read(genreLen)
                        for genreWord in string.gmatch(genreStr, "%S+") do
                            if string.lower(genreWord) ~= "all" then
                                if not trackDatabase[genreWord] then trackDatabase[genreWord] = {} end
                                table.insert(trackDatabase[genreWord], path)
                            end
                        end
                    end
                end
                f:close()
            end
        end
    end
end

local function generatePlaylist(allowedGenres)
    local playlist = {}
    local addedTracks = {}
    for _, genre in ipairs(allowedGenres) do
        if trackDatabase[genre] then
            for _, path in ipairs(trackDatabase[genre]) do
                if not addedTracks[path] then
                    table.insert(playlist, path)
                    addedTracks[path] = true
                end
            end
        end
    end
    for i = #playlist, 2, -1 do
        local j = math.random(i)
        playlist[i], playlist[j] = playlist[j], playlist[i]
    end
    return playlist
end

-- ==========================================
-- ФОНОВЫЙ ДЕМОН РАДИОСТАНЦИИ
-- ==========================================
local function radioDaemon(initialGenres)
    scanLibrary()
    local playlist = generatePlaylist(initialGenres)
    local trackIndex = 1
    local nextGenres = nil

    if #playlist == 0 then safePrint("[Радио] Треки не найдены!"); return end
    safePrint("[Радио] Эфир запущен в фоне. (radio help)")

    while true do
        if trackIndex > #playlist then
            playlist = generatePlaylist(initialGenres)
            trackIndex = 1
        end

        local currentTrackPath = playlist[trackIndex]
        local trackName = string.sub(fs.name(currentTrackPath), 1, -6) 
        
        local f = io.open(currentTrackPath, "rb")
        local data = f:read("*a")
        f:close()
        
        local b1, b2, b3, b4 = string.byte(data, 2, 5)
        local totalTicks = (b1 * 16777216) + (b2 * 65536) + (b3 * 256) + b4
        
        local genreLen = string.byte(data, 6)
        local bodyData = string.sub(data, 7 + genreLen)
        
        local currentPlayer = fmplayer.new(bodyData, keypad, 1)
        
        while currentPlayer:getStatus() ~= "dead" do
            local e, action, arg = event.pull(0.5, "radio_cmd")
            
            if e == "radio_cmd" then
                if action == "stop" then
                    currentPlayer:stop()
                    safePrint("[Радио] Эфир полностью остановлен.")
                    return
                elseif action == "pause" then
                    currentPlayer:pause()
                    safePrint("[Радио] Пауза.")
                elseif action == "resume" then
                    currentPlayer:resume()
                    safePrint("[Радио] Возобновление.")
                elseif action == "skip" then
                    currentPlayer:stop()
                    safePrint("[Радио] Трек пропущен.")
                elseif action == "change" then
                    nextGenres = arg
                    safePrint("[Радио] Жанр изменен (применится после трека).")
                elseif action == "status" then
                    local curTicks = currentPlayer:getCurrentTick()
                    event.push("radio_status_reply", trackName, initialGenres, curTicks, totalTicks)
                end
            end
        end

        if nextGenres then
            playlist = generatePlaylist(nextGenres)
            initialGenres = nextGenres
            trackIndex = 1
            nextGenres = nil
            if #playlist == 0 then safePrint("[Радио] Пустой плейлист. Остановка."); return end
        else
            trackIndex = trackIndex + 1
        end
        os.sleep(1)
    end
end

-- ==========================================
-- ПАРСЕР КОМАНДНОЙ СТРОКИ (CLI)
-- ==========================================
local args = {...}
local cmd = args[1]

if not cmd or cmd == "help" then
    print("=== Управление Радио ===")
    print("radio start [жанры]  - Запустить")
    print("radio status         - Показать текущий трек и время")
    print("radio change [жанры] - Сменить жанр")
    print("radio skip/pause/resume/stop")
    return
end

if cmd == "start" then
    local genres = {"All"}
    if #args > 1 then
        genres = {}
        for i = 2, #args do table.insert(genres, args[i]) end
    end
    thread.create(radioDaemon, genres):detach()

elseif cmd == "status" then
    event.push("radio_cmd", "status")
    local e, name, curGeners, curTicks, totTicks = event.pull(1.0, "radio_status_reply")
    if e then
        print(string.format("Текущий трек:     %s [%s / %s]", name, formatTime(curTicks), formatTime(totTicks)))
        print("Текущий плейлист: " .. table.concat(curGeners, ", "))
    else
        print("Радио сейчас не играет.")
    end

elseif cmd == "stop" or cmd == "pause" or cmd == "resume" or cmd == "skip" then
    event.push("radio_cmd", cmd)

elseif cmd == "change" then
    if #args < 2 then print("Укажите жанр!"); return end
    local genres = {}
    for i = 2, #args do table.insert(genres, args[i]) end
    event.push("radio_cmd", "change", genres)
else
    print("Неизвестная команда.")
end