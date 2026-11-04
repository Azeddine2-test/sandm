-- ============================================================================
-- CarPlay — reconnaissance des liens (partagé client / serveur, demande 69)
-- ----------------------------------------------------------------------------
-- CARPLAY_LIENS.analyser(texte) renvoie :
--   { type = "youtube", ref = "<ID de 11 caractères>", url = "https://www.youtube.com/watch?v=<ID>" }
--   { type = "audio",   ref = "<lien direct>",        url = "<lien direct>", flux = true|false }
-- ou nil, "<message d'erreur en français>".
--
-- Formats YouTube acceptés : youtube.com/watch?v=, m.youtube.com,
-- music.youtube.com, youtu.be/, /shorts/, /embed/, /live/, /v/, avec ou sans
-- « https:// », avec ou sans paramètres (&t=, ?si=, &list=…).
-- Liens audio : http(s) direct (.mp3, .ogg, .wav, .aac, .m4a, .opus, .flac,
-- listes .m3u / .pls) ou flux radio sans extension. Les pages de Spotify,
-- SoundCloud, Deezer, Apple Music, TikTok… ne sont PAS des fichiers audio :
-- refus explicite plutôt qu'un silence incompréhensible.
-- ============================================================================

if type(CARPLAY_LIENS) ~= "table" then CARPLAY_LIENS = {} end
local L = CARPLAY_LIENS

L.EXTENSIONS = { mp3 = true, ogg = true, wav = true, aac = true, m4a = true, opus = true, flac = true, m3u = true, pls = true, mp4 = false }

-- Sites qui donnent une PAGE web, pas un fichier audio.
L.PAGES = {
    "spotify.com", "soundcloud.com", "deezer.com", "music.apple.com", "tiktok.com",
    "instagram.com", "facebook.com", "twitch.tv", "vimeo.com", "dailymotion.com",
    "x.com", "twitter.com", "tidal.com", "music.amazon",
}

local function idValide(id)
    return type(id) == "string" and #id == 11 and id:match("^[%w_%-]+$") ~= nil
end

local function hoteEtChemin(url)
    local hote, chemin = url:match("^[hH][tT][tT][pP][sS]?://([^/%?#]+)([^#]*)")
    if not hote then return nil end
    hote = hote:lower():gsub(":%d+$", "")
    return hote, (chemin ~= "" and chemin or "/")
end

function L.youtubeId(url)
    local hote, chemin = hoteEtChemin(url)
    if not hote then return nil end
    hote = hote:gsub("^www%.", ""):gsub("^m%.", ""):gsub("^music%.", "")
    local id
    if hote == "youtu.be" then
        id = chemin:match("^/([%w_%-]+)")
    elseif hote == "youtube.com" or hote == "youtube-nocookie.com" then
        id = chemin:match("[%?&]v=([%w_%-]+)")
            or chemin:match("^/shorts/([%w_%-]+)")
            or chemin:match("^/embed/([%w_%-]+)")
            or chemin:match("^/live/([%w_%-]+)")
            or chemin:match("^/v/([%w_%-]+)")
        if not id and hote ~= "youtube-nocookie.com" and not chemin:match("^/watch") and not chemin:match("^/shorts") then
            return nil, "page"
        end
    else
        return nil
    end
    if idValide(id) then return id end
    return nil, "id"
end

function L.analyser(texte)
    if type(texte) ~= "string" then return nil, "Colle un lien YouTube ou un lien audio." end
    local url = texte:gsub("^%s+", ""):gsub("%s+$", "")
    if url == "" then return nil, "Colle un lien YouTube ou un lien audio." end
    if #url > ((CARPLAY_CONFIG and CARPLAY_CONFIG.lienMax) or 500) then return nil, "Ce lien est trop long." end
    if url:find("[%s%c]") then return nil, "Un lien ne contient pas d'espace." end
    if not url:match("^[hH][tT][tT][pP][sS]?://") then
        -- « youtube.com/watch?v=… » ou « youtu.be/… » collés sans https://
        if url:match("^[%w%.%-]+%.[%a][%a]+/") or url:match("^[%w%.%-]+%.[%a][%a]+$") then
            url = "https://" .. url
        else
            return nil, "Ce n'est pas un lien (il doit commencer par https://)."
        end
    end
    local hote, chemin = hoteEtChemin(url)
    if not hote or hote == "" then return nil, "Lien illisible." end

    local id, pourquoi = L.youtubeId(url)
    if id then
        return { type = "youtube", ref = id, url = "https://www.youtube.com/watch?v=" .. id }
    end
    if pourquoi == "id" then return nil, "Lien YouTube incomplet : l'identifiant de la vidéo est introuvable." end
    if pourquoi == "page" then return nil, "Ce lien YouTube n'est pas une vidéo (chaîne, recherche…). Ouvre la vidéo et copie son lien." end

    for _, site in ipairs(L.PAGES) do
        local s = site:gsub("%.", "%%.")
        if hote == site or hote:match("%." .. s .. "$") or hote:match("^" .. s) then
            return nil, "Les liens " .. site .. " sont des pages web, pas des fichiers audio. Utilise un lien YouTube ou un lien audio direct (.mp3, flux radio)."
        end
    end

    local ext = chemin:match("^([^%?]*)"):match("%.(%w+)$")
    ext = ext and ext:lower()
    if ext and L.EXTENSIONS[ext] == false then
        return nil, "Les vidéos ." .. ext .. " ne sont pas lues : utilise un lien YouTube ou audio."
    end
    if ext and ({ html = true, htm = true, php = true, aspx = true, jpg = true, jpeg = true, png = true, gif = true, webp = true })[ext] then
        return nil, "Ce lien mène à une page ou une image, pas à un son."
    end
    return { type = "audio", ref = url, url = url, flux = not (ext and L.EXTENSIONS[ext]) }
end

-- URL du lecteur YouTube intégré (CEF). MTA ajoute lui-même le Referer exigé
-- par YouTube pour /embed (mtasa-blue #4531) et lève la règle d'autoplay.
function L.urlLecteur(id, debut)
    debut = math.max(0, math.floor(tonumber(debut) or 0))
    return "https://www.youtube.com/embed/" .. id .. "?autoplay=1&start=" .. debut
        .. "&controls=0&disablekb=1&fs=0&iv_load_policy=3&rel=0&playsinline=1&modestbranding=1"
end

-- 75 → « 1:15 » ; 3725 → « 1:02:05 »
function L.duree(s)
    s = math.max(0, math.floor(tonumber(s) or 0))
    local h, m, sec = math.floor(s / 3600), math.floor(s % 3600 / 60), s % 60
    if h > 0 then return string.format("%d:%02d:%02d", h, m, sec) end
    return string.format("%d:%02d", m, sec)
end

-- Durée ISO 8601 de YouTube (« PT3M33S », « PT1H2M5S ») → secondes
function L.dureeISO(t)
    if type(t) ~= "string" then return nil end
    local h = tonumber(t:match("(%d+)H")) or 0
    local m = tonumber(t:match("(%d+)M")) or 0
    local s = tonumber(t:match("(%d+)S")) or 0
    local tot = h * 3600 + m * 60 + s
    return tot > 0 and tot or nil
end

-- Durée lue dans la page d'une vidéo YouTube (plusieurs formats possibles).
function L.dureeDansPage(html)
    if type(html) ~= "string" then return nil end
    local s = tonumber(html:match('"lengthSeconds"%s*:%s*"(%d+)"'))
    if s and s > 0 then return s end
    local ms = tonumber(html:match('"approxDurationMs"%s*:%s*"(%d+)"'))
    if ms and ms > 0 then return math.floor(ms / 1000) end
    local iso = html:match('itemprop="duration"%s+content="(PT[%dHMS]+)"')
    return L.dureeISO(iso)
end

-- « \u00e9 » → « é » (titres oEmbed si fromJSON est indisponible)
function L.deJSON(s)
    if type(s) ~= "string" then return s end
    s = s:gsub("\\u(%x%x%x%x)", function(h)
        local c = tonumber(h, 16)
        if c < 0x80 then return string.char(c)
        elseif c < 0x800 then return string.char(0xC0 + math.floor(c / 64), 0x80 + c % 64)
        else return string.char(0xE0 + math.floor(c / 4096), 0x80 + math.floor(c / 64) % 64, 0x80 + c % 64) end
    end)
    s = s:gsub('\\"', '"'):gsub("\\/", "/"):gsub("\\\\", "\\")
    return s
end

-- Coupe une chaîne UTF-8 sans casser un caractère.
function L.couper(s, max)
    s = tostring(s or "")
    if #s <= max then return s end
    local i = max
    while i > 0 do
        local b = s:byte(i + 1)
        if not b or b < 0x80 or b >= 0xC0 then break end
        i = i - 1
    end
    return s:sub(1, i) .. "…"
end
