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
m.collections = {}
m.collectionsCacheDurationSeconds = 60 * 60
m.downloadPath = os.getenv("HOME") .. "/.Trash/"

function m:init()
  m.logger.d('init')
end

local function createDownloadTaskAsync(url, cb)
    local outputPath = m.downloadPath .. hs.hash.SHA1(hs.timer.absoluteTime()) .. ".jpg"
    
    local function curlCallback(exitCode, stdout, stderr )
        if exitCode == 0 then
            -- success
            cb( outputPath, nil )
        else
            -- failure
            cb( nil, { stdout, stderr } )
        end
    end

    local task = hs.task.new("/usr/bin/curl", curlCallback, {"-L", url, "-o", outputPath })
    task:start()

    return task
end

function m:getCollectionPhotos(collectionId, cb) 
    local photosEntry = m.collections[collectionId]
    if photosEntry ~= nil then
        if photosEntry.expireTime >= os.time() then
            return cb(photosEntry.photos, nil)
        end
    end

    local collectionPhotosUrl = "https://api.unsplash.com/collections/".. collectionId .. "/photos?per_page=1000&client_id=" .. m.clientId
    hs.http.asyncGet(collectionPhotosUrl, {}, function(status, body, headers)
        if status == 200 then
            local response = hs.json.decode(body)
            local photos = hs.fnutils.imap(response, function(item)
                return item['urls']['raw']    
            end)

            m.collections[collectionId] = {
                photos = photos,
                expireTime = os.time() + m.collectionsCacheDurationSeconds,
            }

            cb(photos, nil)
        else
            cb(nil, { status = status, body = body })
        end
    end)
end

function m:setRandomDesktopPhotoFromCollection(collectionId)
    m:getCollectionPhotos(collectionId, function(photos)
        local index = math.random(1, #photos)
        createDownloadTaskAsync( photos[index], function(file, err)
            if err ~= nil then
                m.logger.e('Error downloading image', err)
                return
            end

            hs.screen.mainScreen():desktopImageURL("file://" .. file)
        end)
    end)
end

function m:setRandomDesktopPhoto()
    local sd = hs.screen.mainScreen():currentMode()
    local width = string.format("%0.f", sd.w * sd.scale)
    local height = string.format("%0.f", sd.h * sd.scale)
    local url = "https://source.unsplash.com/random/" .. width .. "x" .. height

    createDownloadTaskAsync( url, function(file, err)
        if err ~= nil then
            m.logger.e('Error downloading image', err)
            return
        end

        hs.screen.mainScreen():desktopImageURL("file://" .. file)
    end)
end

return m
