-- ============================================================================
-- retour.lua — BACKSPACE et Échap = « retour » dans les interfaces
-- (demande 21, 16/10/2026 : « je veux que la touche BACKSPACE et Échap puisse
--  faire retour dans toutes les interfaces du jeu jusqu'à les fermer »)
--
-- Fichier CANONIQUE : [Lib]/neon_theme/retour.lua. Une copie identique est
-- placée dans chaque ressource qui a une interface (comme theme.lua) et
-- déclarée dans son meta.xml AVANT les scripts qui l'utilisent.
--
-- Utilisation (côté client) :
--   RETOUR.brancher({
--       nom    = "inventaire",                 -- pour le débogage
--       ouvert = function() return estOuvert end,
--       retour = function(touche) ... end,     -- recule d'UN niveau (sous-menu
--                                              -- → menu, puis menu → fermé)
--       saisie = function() return champActif end, -- facultatif : un champ de
--                                              -- texte dx de l'interface a le
--                                              -- focus → BACKSPACE efface
--       cegui  = false,                        -- facultatif : ne pas tenir compte
--                                              -- du focus CEGUI (l'interface le
--                                              -- gère elle-même dans `saisie`)
--   })
--
-- Règles communes :
--   * BACKSPACE n'agit pas si l'on tape (chat, console, champ CEGUI, champ dx
--     signalé par `saisie`) : elle efface alors un caractère, comme avant ;
--   * Échap n'agit pas pendant la saisie du chat ou de la console (MTA ferme
--     d'abord la saisie) ;
--   * la touche est « consommée » (cancelEvent) : le menu de MTA ne s'ouvre pas,
--     et une seule interface recule par appui (wasEventCancelled) ;
--   * LIMITE DE MTA (CClientGame::KeyStrokeHandler) : Échap ne peut pas être
--     annulé deux fois DE SUITE. Si l'appui précédent était un Échap consommé
--     (sans autre touche entre les deux), le menu de MTA s'ouvrira quoi qu'on
--     fasse : on ne recule pas (l'interface reste telle quelle derrière le
--     menu). Pour reculer de plusieurs niveaux d'affilée : BACKSPACE.
-- ============================================================================

RETOUR = RETOUR or {}
local R = RETOUR
R.liste = R.liste or {}
R.echapBloque = false

function R.chatOuConsole()
    if isChatBoxInputActive and isChatBoxInputActive() then return true end
    if isConsoleActive and isConsoleActive() then return true end
    -- chat maison ([CHAT]/chat_system) en cours de saisie : il gère lui-même
    -- BACKSPACE (effacer) et Échap (fermer la liste, puis le chat)
    if getElementData and localPlayer and getElementData(localPlayer, "chat:saisie") == true then return true end
    return false
end

-- Un champ CEGUI (gui-edit / gui-memo) a-t-il le focus ? guiGetInputEnabled ne
-- suffit pas : en mode « allow_binds » (celui par défaut) il reste faux pendant
-- la frappe. On suit donc le focus avec onClientGUIFocus / onClientGUIBlur, qui
-- remontent jusqu'à root pour les champs de toutes les ressources.
function R.champCEGUI()
    if guiGetInputEnabled and guiGetInputEnabled() then return true end
    local c = R.champ
    if c and isElement(c) and (not guiGetVisible or guiGetVisible(c)) then return true end
    R.champ = nil
    return false
end

function R.surFocus()
    local t = getElementType(source)
    if t == "gui-edit" then
        if guiEditIsReadOnly and guiEditIsReadOnly(source) then return end   -- lecture seule : on n'y tape pas
        R.champ = source
    elseif t == "gui-memo" then
        if guiMemoIsReadOnly and guiMemoIsReadOnly(source) then return end
        R.champ = source
    end
end

function R.surBlur()
    if R.champ == source then R.champ = nil end
end

function R.brancher(o)
    assert(type(o) == "table" and type(o.ouvert) == "function" and type(o.retour) == "function",
        "RETOUR.brancher : ouvert et retour sont obligatoires")
    R.liste[#R.liste + 1] = o
    return o
end

-- Appelée par MTA pour chaque appui ; exposée pour les bancs de test.
function R.surTouche(touche, appui)
    if not appui or (touche ~= "backspace" and touche ~= "escape") then return end
    if wasEventCancelled and wasEventCancelled() then return end   -- une autre interface a déjà reculé
    if R.chatOuConsole() then return end
    if touche == "escape" and R.echapBloque then return end
    for i = #R.liste, 1, -1 do                                       -- la dernière branchée d'abord
        local o = R.liste[i]
        local okO, ouvert = pcall(o.ouvert)
        if okO and ouvert then
            if touche == "backspace" then
                local okS, tape = pcall(function()
                    return (o.saisie and o.saisie()) or (o.cegui ~= false and R.champCEGUI())
                end)
                if okS and tape then return end
            end
            cancelEvent()
            local ok, err = pcall(o.retour, touche)
            if not ok and outputDebugString then outputDebugString("[retour] " .. tostring(o.nom) .. " : " .. tostring(err), 2) end
            return
        end
    end
end

-- Observateur placé APRÈS tous les autres gestionnaires : retient si cet appui
-- était un Échap consommé (miroir de m_bLastKeyWasEscapeCancelled de MTA).
function R.observer(touche, appui)
    if not appui then return end
    R.echapBloque = (touche == "escape") and (wasEventCancelled and wasEventCancelled()) and true or false
    R.surveillerMenu(R.echapBloque)
end

-- Quand le menu de MTA s'affiche, MTA remet son drapeau à zéro, mais les
-- touches pressées menu ouvert n'arrivent pas jusqu'à onClientKey : on le
-- surveille tant que le drapeau est levé, sinon l'Échap suivant serait refusé.
function R.verifierMenu()
    if isMainMenuActive and isMainMenuActive() then
        R.echapBloque = false
        R.surveillerMenu(false)
    end
end

function R.surveillerMenu(actif)
    if not addEventHandler then return end
    if actif and not R._surveille then
        R._surveille = true
        addEventHandler("onClientRender", root, R.verifierMenu)
    elseif not actif and R._surveille then
        R._surveille = false
        removeEventHandler("onClientRender", root, R.verifierMenu)
    end
end

if addEventHandler and not R._branche then
    R._branche = true
    addEventHandler("onClientKey", root, R.surTouche, false, "high+5")
    addEventHandler("onClientKey", root, R.observer, false, "low-9999")
    addEventHandler("onClientGUIFocus", root, R.surFocus)
    addEventHandler("onClientGUIBlur", root, R.surBlur)
end
