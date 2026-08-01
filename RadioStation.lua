local fs = require("filesystem")
local component = require("component")
local os = require("os")
local RadioPlayer = require("RadioPlayer")

local MUSIC_DIR = "/home/music/"
local keypad = component.rbmk_keypad

-- База данных треков: db[genre_id] = { "song1.bin", "song2.bin" }
local trackDatabase = {}

local function scanLibrary()
    print("Сканирование медиатеки...")
    trackDatabase = {} 
    
    trackDatabase["All"] = {} 
    
    for file in fs.list(MUSIC_DIR) do
        if string.sub(file, -5) == ".mbin" then
            local path = MUSIC_DIR .. file
            local f = io.open(path, "rb")
            
            if f then
                local header = f:read(6)
                if header and #header == 6 then

                    table.insert(trackDatabase["All"], path)
                    
                    local genreLen = string.byte(header, 6)
                    if genreLen > 0 then
                        local genreStr = f:read(genreLen)
                        
                        for genreWord in string.gmatch(genreStr, "%S+") do
                            if string.lower(genreWord) ~= "all" then
                                if not trackDatabase[genreWord] then
                                    trackDatabase[genreWord] = {}
                                end
                                table.insert(trackDatabase[genreWord], path)
                            end
                        end
                    end
                end
                f:close()
            end
        end
    end
    
    for genre, tracks in pairs(trackDatabase) do
        print(string.format("Найдено в '%s': %d треков", genre, #tracks))
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

local function startRadio(genres)
    scanLibrary()
    local playlist = generatePlaylist(genres)
    
    if #playlist == 0 then
        print("Не найдено треков для этих жанров!")
        return
    end

    print("Запуск эфира. В плейлисте треков: " .. #playlist)
    
    local trackIndex = 1
    local currentPlayer = nil

    while true do
        local currentTrackPath = playlist[trackIndex]
        print("\nСейчас играет: " .. fs.name(currentTrackPath))
        
        local f = io.open(currentTrackPath, "rb")
        local data = f:read("*a")
        f:close()
        
        local genreLen = string.byte(data, 6)
        local headerTotalSize = 6 + genreLen
        local bodyData = string.sub(data, headerTotalSize + 1)
        
        currentPlayer = RadioPlayer.new(bodyData, keypad, 1)
        
        while currentPlayer:getStatus() ~= "dead" do
            os.sleep(0.5) 
            
            -- ЗДЕСЬ МОЖНО ДОБАВИТЬ ПЕРЕХВАТ СОБЫТИЙ ДЛЯ ПРОПУСКА ТРЕКА
            -- Если придет событие "скип", делаем currentPlayer:stop(),
            -- статус станет "dead", и цикл автоматически пойдет дальше!
        end
        
        trackIndex = trackIndex + 1
        
        if trackIndex > #playlist then
            print("Плейлист завершен. Перемешиваем...")
            playlist = generatePlaylist(genres)
            trackIndex = 1
        end
        
        os.sleep(2) 
    end
end

-- ==========================================
-- ЗАПУСК РАДИОСТАНЦИИ
-- ==========================================

startRadio({"All"})