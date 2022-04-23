local InstanceReplication = require(script.Parent:WaitForChild("InstanceReplication"))
local Obliterate = require(script.Parent.Parent:WaitForChild("Obliterate"))
local Cleaner = require(script.Parent.Parent:WaitForChild("Cleaner"))

local WorldPartitioners = script.Parent:WaitForChild("WorldPartitioners")

local UNSUPPORTED_OBJECT = "Unsupported object type: %s"
local NO_PRIMARY_PART = "No PrimaryPart found on model: %s"

local WorldPartitioner = {}
WorldPartitioner.__index = WorldPartitioner

function WorldPartitioner.new(InstanceReplicationObject: InstanceReplication.InstanceReplication, WorldPartitionerName: string, WorldPartitionerParams: {any}?)
    local RootObject = InstanceReplicationObject.Root
    local WorldPartitionerImplementationClassModule = require(WorldPartitioners[WorldPartitionerName])

    -- Check it's attached to a part or a model with a BasePart
    if (RootObject:IsA("Model")) then
        assert(RootObject.PrimaryPart ~= nil, NO_PRIMARY_PART:format(RootObject:GetFullName()))
    elseif (not RootObject:IsA("BasePart")) then
        error(UNSUPPORTED_OBJECT:format(RootObject:GetFullName()))
    end

    local WorldPartitionerImplementation = WorldPartitionerImplementationClassModule.new(unpack(WorldPartitionerParams));

    local self = {
        WorldPartitionerImplementation = WorldPartitionerImplementation;
        InstanceReplicationObject = InstanceReplicationObject;
        RootObject = RootObject;
        Cleaner = Cleaner.new();
    };

    return setmetatable(self, WorldPartitioner)
end

function WorldPartitioner:Register(Target: BasePart | Model, MovementDetectionInterval: number?, BypassCleaner: boolean?)
    local WorldPartitionerImplementation = self.WorldPartitionerImplementation

    if (MovementDetectionInterval) then --> Timer-based grid positioning (e.g. if physics influences the part position)
        local TerminateTimer = false
        local LastPosition

        task.spawn(function()
            while (not TerminateTimer) do
                task.wait(MovementDetectionInterval)

                local NewPosition = Target.Position

                if (LastPosition ~= NewPosition) then
                    print("Change via timer")
                    LastPosition = NewPosition
                    WorldPartitionerImplementation:Reposition(NewPosition, Target)
                end
            end
        end)

        local Connection = {
            Disconnect = function()
                TerminateTimer = true
            end;
        }

        if (not BypassCleaner) then
            self.Cleaner:Add(Connection)
        end

        return Connection
    else --> Resort to event-based grid positioning (e.g. if we are manually updating part position)
        local Connection = Target:GetPropertyChangedSignal("Position"):Connect(function()
            print("Change via reposition")
            WorldPartitionerImplementation:Reposition(Target.Position, Target)
        end)

        if (not BypassCleaner) then
            self.Cleaner:Add(Connection)
        end

        return Connection
    end
end

function WorldPartitioner:RegisterPlayer(Player: Player)
    local Char = Player.Character
    local LastRegister

    if (Char) then
        LastRegister = self:Register(Char, 0.01, true)
    end

    local CharAdded; CharAdded = Player.CharacterAdded:Connect(function(Character: Model)
        if (LastRegister) then
            LastRegister:Disconnect()
        end

        LastRegister = self:Register(Character, 0.01, true)
    end)

    local LeaveCheck; LeaveCheck = Player.AncestryChanged:Connect(function(_, Parent)
        if (Parent == nil) then
            CharAdded:Disconnect()
            LeaveCheck:Disconnect()

            if (LastRegister) then
                LastRegister:Disconnect()
            end
        end
    end)
end

function WorldPartitioner:GetObjectsNear(Player: Player)

end

function WorldPartitioner:Destroy()
    self.Cleaner:Clean()
    Obliterate(self, "WorldPartitioner")
end

return WorldPartitioner