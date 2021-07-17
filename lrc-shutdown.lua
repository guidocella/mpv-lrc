mp.register_event('shutdown', function ()
    if require 'mp.utils'.shared_script_property_get('showed-lyrics') then
        os.exit()
    end
end)
