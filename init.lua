--- === Unsplashed ===
---
-- Hattip:
-- m.name = "UnsplashRandom"
-- m.author = "Gautam Krishna R <r.gautamkrishna@gmail.com>"
-- and
-- https://github.com/roeeyn/RandomBackground.spoon/blob/main/init.lua
local logger = require("hs.logger")

local m = {}
m.__index = m

-- Metadata
m.name = "Unsplashed"
m.version = "0.1"
m.author = "crumley@gmail.com"
m.license = "MIT"
m.homepage = "https://github.com/Hammerspoon/Spoons"

m.logger = logger.new('Unsplash', 'debug')

-- Settings
m.clientId = nil
m.monitorSpaces = true
m.lastBackgroundFile = nil
m.collections = {}
m.collectionsCacheDurationSeconds = 60 * 60
m.downloadPath = os.getenv("HOME") .. "/.Trash/"
m.settingsKeyPrefix = m.name

function m:init()
    m.logger.d('init')
    m.lastBackgroundFile = hs.settings.get(m.settingsKeyPrefix .. ".lastBackgroundFile")
end

function m:start()
    m.logger.d('start')

    if m.monitorSpaces then
        local w = hs.spaces.watcher.new(function(s)
            m:_onSpaceChanged()
        end)
        w.start(w)
    end
end

local function createDownloadTaskAsync(url, cb)
    local outputPath = m.downloadPath .. hs.timer.absoluteTime() .. ".jpg"

    local function curlCallback(exitCode, stdout, stderr)
        if exitCode == 0 then
            -- success
            cb(outputPath, nil)
        else
            -- failure
            cb(nil, {stdout, stderr})
        end
    end

    m.logger.d('createDownloadTaskAsync.started', url, outputPath)
    local task = hs.task.new("/usr/bin/curl", curlCallback, {"-L", url, "-o", outputPath})
    task:start()

    return task
end

function m:getCollectionPhotos(collectionId, cb)
    local photosEntry = m.collections[collectionId]
    if photosEntry ~= nil then
        if photosEntry.expireTime >= os.time() then
            m.logger.d('getCollectionPhotos.cache-hit')
            return cb(photosEntry.photos, nil)
        end
    end

    local function cacheCb(photos, err)
        m.collections[collectionId] = {
            photos = photos,
            expireTime = os.time() + m.collectionsCacheDurationSeconds
        }

        cb(photos, err)
    end

    m:_getCollectionPhotos(collectionId, cacheCb)
end

function m:_getCollectionPhotos(collectionId, cb)
    local photos = {}
    local lastPhotoCount = #photos

    local batchSize = 3
    local completedCount = 0
    local dispatchedCount = 0

    local function nextBatch(accFn)
        local index = 0
        local startCount = completedCount
        dispatchedCount = dispatchedCount + batchSize
        while index < batchSize do
            m:getCollectionPhotosPage(collectionId, startCount + index, accFn)
            index = index + 1
        end
    end

    local function chunkCb(newPhotos, err)
        completedCount = completedCount + 1

        if err ~= nil then
            cb(nil, err)
        end

        hs.fnutils.each(newPhotos, function(url)
            table.insert(photos, url)
        end)

        if completedCount >= dispatchedCount then
            if lastPhotoCount == #photos then
                return cb(photos, nil)
            end

            lastPhotoCount = #photos
            nextBatch(chunkCb)
        end
    end

    nextBatch(chunkCb)
end

function m:getCollectionPhotosPage(collectionId, pageIndex, cb)
    local collectionPhotosUrl =
        "https://api.unsplash.com/collections/" .. collectionId .. "/photos?page=" .. pageIndex ..
            "&per_page=30&client_id=" .. m.clientId
    hs.http.asyncGet(collectionPhotosUrl, {}, function(status, body, headers)
        m.logger.d('getCollectionPhotosPage.resp', collectionPhotosUrl, status)
        if status == 200 then
            local response = hs.json.decode(body)
            local photos = hs.fnutils.imap(response, function(item)
                return item['urls']['raw']
            end)

            cb(photos, nil)
        else
            cb(nil, {
                status = status,
                body = body
            })
        end
    end)
end

function m:setRandomDesktopPhotoFromCollection(collectionId)
    m.logger.df('setRandomDesktopPhotoFromCollection collectionId=%s', collectionId)
    m:getCollectionPhotos(collectionId, function(photos, err)
        if err ~= nil then
            m.logger.e("Error downloading collecting: ", hs.inspect(err))
            return
        end
        local index = math.random(1, #photos)
        m.logger.df('setRandomDesktopPhotoFromCollection.random-photo %i/%i', index, #photos, photos[index])
        createDownloadTaskAsync(photos[index], function(file, err)
            if err ~= nil then
                m.logger.e('Error downloading image', err)
                return
            end

            m.logger.d('setRandomDesktopPhotoFromCollection.setting-background', file)
            m:_setBackground(file)
        end)
    end)
end

function m:_setBackground(file)
    m.lastBackgroundFile = file
    hs.settings.set(m.settingsKeyPrefix .. ".lastBackgroundFile", file)
    -- hs.screen.mainScreen():desktopImageURL("file://" .. file)
    hs.osascript.applescript(string.format([[
        tell application "System Events"
            tell every desktop
                set picture to "%s"
            end tell
        end tell
    ]], file))
end

function m:setRandomDesktopPhoto()
    local sd = hs.screen.mainScreen():currentMode()
    local width = string.format("%0.f", sd.w * sd.scale)
    local height = string.format("%0.f", sd.h * sd.scale)
    local url = "https://source.unsplash.com/random/" .. width .. "x" .. height

    createDownloadTaskAsync(url, function(file, err)
        if err ~= nil then
            m.logger.e('Error downloading image', err)
            return
        end

        hs.screen.mainScreen():desktopImageURL("file://" .. file)
    end)
end

function m:_onSpaceChanged()
    m.logger.d('_onSpaceChanged:refreshingBackground', m.lastBackgroundFile)
    if m.lastBackgroundFile ~= nil then
        m:_setBackground(m.lastBackgroundFile)
    end
end

return m
