local MockRemoteEvent = {}
MockRemoteEvent.__index = MockRemoteEvent

function MockRemoteEvent.new()
    local Bind = Instance.new("BindableEvent")

    local self = {
        Bind = Bind;
        OnClientEvent = Bind.Event;
        OnServerEvent = Bind.Event;
    };

    return setmetatable(self, MockRemoteEvent)
end

function MockRemoteEvent:FireServer(...)
    if (self.OnFire) then
        self.OnFire(...)
    end
end

function MockRemoteEvent:FireClient(_Player, ...)
    if (self.OnFire) then
        self.OnFire(...)
    end
end

function MockRemoteEvent:FireAllClients(...)
    if (self.OnFire) then
        self.OnFire(...)
    end
end

return MockRemoteEvent