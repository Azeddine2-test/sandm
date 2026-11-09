----------------------------------------------
--Resource: dl_flashlight                   --
--Author: Ren712                            --
--Contact: knoblauch700@o2.pl               --
----------------------------------------------

local flashLiTable = {flModel={}, shLight={}, shLiBul={}, shLiRay={}, isFlon={} ,isFLen={}, fLInID={} }
local renderTarget = {RTColor = nil, RTNormal = nil, isOn = false}
local isLightOn = false

---------------------------------------------------------------------------------------------------
-- editable variables
---------------------------------------------------------------------------------------------------
local disableFLTex = false -- true=makes the flashlight body not visible (useful for alter attach)
local autoEnableFL = false -- true=the player gets the flashlight without writing commands
-- light settings for other players
local gLightTheta = math.rad(6) -- Theta is the inner cone angle
local gLightPhi = math.rad(18) -- Phi is the outer cone angle
local gLightFalloff = 1.5 -- light intensity attenuation between the phi and theta areas
local gAttenuation = 25 -- light attenuation (max radius)
-- light settings for localPlayer
local gLocLightTheta = math.rad(6) -- Theta is the inner cone angle
local gLocLightPhi = math.rad(45) -- Phi is the outer cone angle
local gLocLightFalloff = 1.5 -- light intensity attenuation between the phi and theta areas
local gLocAttenuation = 45 -- light attenuation (max radius)
-- for all
local gWorldSelfShadow = true -- enables object self shadowing for other players
local gLightColor = {0.9,0.9,0.65,1.0} -- rgba color of the projected light, light rays and the lightbulb
local switch_key = 'r' -- define the key that switches the light effect
local objID = 15060  -- the object we are going to replace (interior building shadow in this case)

local theTikGap = 0.5 -- here you set how many seconds to wait after switching the flashlight on/off
local flTimerUpdate = 200 -- the effect update time interval 

local getLastTack = getTickCount ( )-(theTikGap*1000)
local shTeNul = dxCreateShader ( "shaders/shader_null.fx",0,0,false )

---------------------------------------------------------------------------------------------------
-- update the existing lights
---------------------------------------------------------------------------------------------------
addEventHandler("onClientPedsProcessed", root, function()
	for index,this in ipairs(getElementsByType("player")) do
		if flashLiTable.shLight[this] then
			local x1, y1, z1 = getPedBonePosition ( this, 24 )
			local lx1, ly1, lz1 = getPedBonePosition ( this, 25 )
			exports.dl_lightmanager:setLightDirection(flashLiTable.shLight[this],lx1-x1, ly1-y1, lz1-z1)
			exports.dl_lightmanager:setLightPosition(flashLiTable.shLight[this],lx1, ly1, lz1)	
		end
	end
end
, true, "high+10")

---------------------------------------------------------------------------------------------------
-- create/destroy the effects for flashlight model
---------------------------------------------------------------------------------------------------
function createFlashlightModel(thisPed)
	if not flashLiTable.flModel[thisPed] then	
		flashLiTable.flModel[thisPed] = createObject(objID,0,0,0,0,0,0,true)
		if disableFLTex and shTeNul then
			engineApplyShaderToWorldTexture ( shTeNul, "flashlight_COLOR", flashLiTable.flModel[thisPed] )	
			engineApplyShaderToWorldTexture ( shTeNul, "flashlight_L", flashLiTable.flModel[thisPed] )	
		end
		setElementAlpha(flashLiTable.flModel[thisPed],254)
		exports.pattach:attach(flashLiTable.flModel[thisPed],thisPed,24,-0.015,0.015,0.175,90,0,2)
	end
end

function destroyFlashlightModel(thisPed)
	if flashLiTable.flModel[thisPed] then			
		exports.pattach:detach(flashLiTable.flModel[thisPed])
		if disableFLTex and shTeNul then
			engineRemoveShaderFromWorldTexture ( shTeNul, "*", flashLiTable.flModel[thisPed] )
		end
		destroyElement(flashLiTable.flModel[thisPed])
		flashLiTable.flModel[thisPed]=nil
	end
end

---------------------------------------------------------------------------------------------------
-- Creates / destroys  spot light
---------------------------------------------------------------------------------------------------
function createWorldLight(thisPed)
	if flashLiTable.shLight[thisPed] or ((isSynced==false) and (thisPed~=localPlayer)) then return end
	local posX,posY,posZ = getCameraMatrix()
	if (thisPed~=localPlayer) then
		flashLiTable.shLight[thisPed] = exports.dl_lightmanager:createSpotLight(posX,posY,posZ,gLightColor[1] * 255,gLightColor[2] * 255,gLightColor[3] * 255,gLightColor[4] * 255,0,0,0,gLightFalloff,gLightTheta,gLightPhi,gAttenuation,gWorldSelfShadow)
	else
		flashLiTable.shLight[thisPed] = exports.dl_lightmanager:createSpotLight(posX,posY,posZ,gLightColor[1] * 255,gLightColor[2] * 255,gLightColor[3] * 255,gLightColor[4] * 255,0,0,0,gLocLightFalloff,gLocLightTheta,gLocLightPhi,gLocAttenuation,false)
	end
end

function destroyWorldLight(thisPed)
	if flashLiTable.shLight[thisPed] then
		flashLiTable.shLight[thisPed] = not exports.dl_lightmanager:destroyLight(flashLiTable.shLight[thisPed])
	end
end

---------------------------------------------------------------------------------------------------
-- Creates / destroys  light bulb and rays effects
---------------------------------------------------------------------------------------------------
function createFlashLightShader(thisPed)
	if not flashLiTable.flModel[thisPed] then return false end
	if not flashLiTable.shLiBul[thisPed] or flashLiTable.shLiRay[thisPed] then
		flashLiTable.shLiBul[thisPed]=dxCreateShader("shaders/shader_lightBulb.fx",1,0,false)
		flashLiTable.shLiRay[thisPed]=dxCreateShader("shaders/shader_lightRays.fx",1,0,true)
		if not flashLiTable.shLiBul[thisPed] or not flashLiTable.shLiRay[thisPed] then
			return
		end
		if renderTarget.RTColor then 
			dxSetShaderValue (flashLiTable.shLiBul[thisPed],"colorRT",renderTarget.RTColor)		
		end
		if renderTarget.RTNormal then 
			dxSetShaderValue (flashLiTable.shLiBul[thisPed],"normalRT",renderTarget.RTNormal)	
		end
		engineApplyShaderToWorldTexture(flashLiTable.shLiBul[thisPed],"flashlight_L", flashLiTable.flModel[thisPed] )
		engineApplyShaderToWorldTexture(flashLiTable.shLiRay[thisPed], "flashlight_R", flashLiTable.flModel[thisPed] )	
		dxSetShaderValue (flashLiTable.shLiBul[thisPed],"gLightColor",gLightColor)
		dxSetShaderValue (flashLiTable.shLiRay[thisPed],"gLightColor",gLightColor)
	end
end

function destroyFlashLightShader(thisPed)
	if flashLiTable.shLiBul[thisPed] or flashLiTable.shLiRay[thisPed] then
		if flashLiTable.shLiBul[thisPed] then destroyElement(flashLiTable.shLiBul[thisPed]) end
		if flashLiTable.shLiRay[thisPed] then destroyElement(flashLiTable.shLiRay[thisPed]) end
		flashLiTable.shLiBul[thisPed]=nil
		flashLiTable.shLiRay[thisPed]=nil
	end
end

---------------------------------------------------------------------------------------------------
-- enabling and switching on the flashlight
---------------------------------------------------------------------------------------------------
function playSwitchSound(thisPed)
	pos_x,pos_y,pos_z=getElementPosition (thisPed)
	local flSound = playSound3D("sounds/switch.wav", pos_x, pos_y, pos_z, false) 
	setSoundMaxDistance(flSound,40)
	setSoundVolume(flSound,0.6)
end

function flashLightEnable(isEN,thisPed)
if isEN==true then
		flashLiTable.isFLen[thisPed]=isEN	
	else
		flashLiTable.isFLen[thisPed]=isEN	
	end
end

function flashLightSwitch(isON,thisPed)
if isElementStreamedIn(thisPed) and flashLiTable.isFLen[thisPed] then  playSwitchSound(thisPed) end
if isON then
		flashLiTable.isFlon[thisPed]=true
	else
		flashLiTable.isFlon[thisPed]=false
	end
end


function whenPlayerQuits(thisPed)
	destroyWorldLight(thisPed) 
	destroyFlashlightModel(thisPed) 
	destroyFlashLightShader(thisPed)  
end

---------------------------------------------------------------------------------------------------
-- streaming in/out the flashlight model
---------------------------------------------------------------------------------------------------
addEventHandler("onClientResourceStart", getResourceRootElement( getThisResource()), function()
	if FLenTimer then return end
	FLenTimer = setTimer(	function()
		for index,thisPed in ipairs(getElementsByType("player")) do
			if flashLiTable.fLInID[thisPed]==nil then flashLiTable.fLInID[thisPed]=0 end
			if isElementStreamedIn(thisPed) and flashLiTable.isFLen[thisPed]==true and flashLiTable.fLInID[thisPed]~=getElementInterior(thisPed) then
			triggerServerEvent("onPlayerGetInter", resourceRoot, thisPed)
		end
		if  isElementStreamedIn(thisPed) and not flashLiTable.flModel[thisPed] and flashLiTable.isFLen[thisPed]==true then
			createFlashlightModel(thisPed)
			if flashLiTable.fLInID[thisPed]~=nil then setElementInterior ( flashLiTable.flModel[thisPed], flashLiTable.fLInID[thisPed]) end
			end
		if  isElementStreamedIn(thisPed) and flashLiTable.flModel[thisPed] and flashLiTable.isFLen[thisPed]==false then
			destroyFlashlightModel(thisPed)
			end
		if isElementStreamedIn(thisPed) and not flashLiTable.shLiRay[thisPed] and flashLiTable.isFlon[thisPed]==true then 
			createFlashLightShader(thisPed) 
			createWorldLight(thisPed)
			end
		if (isElementStreamedIn(thisPed) or not isElementStreamedIn(thisPed)) and flashLiTable.shLiRay[thisPed] and flashLiTable.isFlon[thisPed]==false then 
			destroyFlashLightShader(thisPed) 
			destroyWorldLight(thisPed)			
			end
		end
	end
	,flTimerUpdate,0 )
end
)

function getPlayerInteriorFromServer(thisPed,interiorID)
	if flashLiTable.flModel[thisPed] then
		flashLiTable.fLInID[thisPed]=interiorID
		if flashLiTable.flModel[thisPed] then setElementInterior ( flashLiTable.flModel[thisPed], flashLiTable.fLInID[thisPed]) end
	end
end

---------------------------------------------------------------------------------------------------
-- switching on / off the flashlight
---------------------------------------------------------------------------------------------------
addEventHandler("onClientVehicleEnter", getRootElement(),
    function(thePlayer, seat)
        if thePlayer == localPlayer then
			if isLightOn then
				isLightOn = false
				triggerServerEvent("onSwitchLight", resourceRoot, isLightOn)
				triggerEvent("switchFlashLight", root, isLightOn)
			end
        end
    end
)

function toggleLight()
	if getPedOccupiedVehicle(localPlayer) then return end
	if (getTickCount ( ) - getLastTack < theTikGap*1000) then outputChatBox('FlashLight: Wait '..theTikGap..' seconds.',255,0,0) return end
	isLightOn = not isLightOn
	triggerServerEvent("onSwitchLight", resourceRoot, isLightOn)
	triggerEvent("switchFlashLight", root, isLightOn)
	getLastTack = getTickCount ( )
end

function toggleFlashLight()
if flashLiTable.flModel[localPlayer] then 
	outputChatBox('You have disabled the flashlight',0,255,0)
	triggerServerEvent("onSwitchLight", resourceRoot, false)
	triggerServerEvent("onSwitchEffect", resourceRoot, false)
	isLightOn = false
	unbindKey(switch_key,"down",toggleLight)
else
	outputChatBox('You have enabled the flashlight',0,255,0)
	triggerServerEvent("onSwitchLight", resourceRoot, false)
	triggerServerEvent("onSwitchEffect", resourceRoot, true)
	bindKey(switch_key,"down",toggleLight)
	end
end

---------------------------------------------------------------------------------------------------
-- crude ped bone rotation handling
---------------------------------------------------------------------------------------------------
addEventHandler("onClientPreRender", root, function()
	for index,thisPed in ipairs(getElementsByType("player")) do
		if flashLiTable.flModel[thisPed] and isElementStreamedIn(thisPed) then
			if ((getPedControlState (thisPed, "sprint") and not getPedControlState(thisPed, "fire")) and getPedWeaponSlot(thisPed) == 0) then
				setElementBoneRotation(thisPed, 21, 44.449, -150.920, 78.471)
				setElementBoneRotation(thisPed, 22, 0, 0, -76)
				setElementBoneRotation(thisPed, 23, 0, -116.5, 0)
				updateElementRpHAnim(thisPed)
			end
		end
	end
end
, true, "high+20")

---------------------------------------------------------------------------------------------------
-- events
---------------------------------------------------------------------------------------------------
addEventHandler("onClientResourceStart", getResourceRootElement( getThisResource()), function()
	renderTarget.RTColor, renderTarget.RTNormal = exports.dl_core:getRenderTargets()
	
	engineImportTXD( engineLoadTXD( "objects/flashlight.txd" ), objID ) 
	engineReplaceModel ( engineLoadDFF( "objects/flashlight.dff", 0 ), objID,true)	

	triggerServerEvent("onPlayerStartRes", resourceRoot)
	if autoEnableFL then 
		toggleFlashLight() 
	else
		outputChatBox('Type /flashlight to enable the flashlight ',255,255,0)
	end
	outputChatBox('Hit '..switch_key..' to turn on/off the flashlight',255,255,0)
	addCommandHandler("flashlight", toggleFlashLight)
end
)

addEventHandler("onClientResourceStop", getResourceRootElement( getThisResource()), function()
	for index,this in ipairs(getElementsByType("player")) do
		if flashLiTable.shLight[this] then
			destroyWorldLight(this)
		end
	end
end
)

addEvent( "flashOnPlayerEnable", true )
addEvent( "flashOnPlayerQuit", true )
addEvent( "flashOnPlayerSwitch", true )
addEvent( "flashOnPlayerInter", true)
addEventHandler( "flashOnPlayerQuit", resourceRoot, whenPlayerQuits)
addEventHandler( "flashOnPlayerSwitch", resourceRoot, flashLightSwitch)
addEventHandler( "flashOnPlayerEnable", resourceRoot, flashLightEnable)
addEventHandler( "flashOnPlayerInter", resourceRoot, getPlayerInteriorFromServer)
