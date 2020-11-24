local utils = require 'mp.utils'

mp.register_event('shutdown', function ()
    if utils.shared_script_property_get('showed-lyrics') then
        os.exit()
    end
end)
