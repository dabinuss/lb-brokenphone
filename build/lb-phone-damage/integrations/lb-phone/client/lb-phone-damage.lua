-- Loaded by lb-phone so SendNUIMessage targets LB Phone's own NUI document.
AddEventHandler('lb-phone-damage:lbui:update', function(data)
    if type(data) ~= 'table' then return end
    SendNUIMessage(data)
end)
