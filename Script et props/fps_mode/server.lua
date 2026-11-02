--[[
-----------------------------------------
####   ###  ##### ####  ###  ###  #   # -
#   # #   #   #   #   #  #  #     #  #  -
####  #####   #   ####   #  #     ###   -
#     #   #   #   #  #   #  #     #  #  -
#     #   #   #   #   # ###  ###  #   # -
-----------------------------------------

#  Developed by: Patrick                                        
#  Support     : Support on my Discord (@_roger79)

]]

addEvent("onPlayerToggleFP", true)
addEventHandler("onPlayerToggleFP", root, function(state)
    if client ~= source then return end 
    setElementData(source, "isFirstPerson", state)
end)