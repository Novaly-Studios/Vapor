local RunService = game:GetService("RunService")
local IsClient = RunService:IsClient()

local Cleaner = require(script.Parent.Parent:WaitForChild("Cleaner"))
local TypeGuard = require(script.Parent.Parent:WaitForChild("TypeGuard"))
local StoreInterface = require(script.Parent:WaitForChild("StoreInterface"))
local ReplicatedStore = require(script.Parent:WaitForChild("ReplicatedStore"))

local VALIDATE_PARAMS = true
local REMOTE_WAIT_TIMEOUT = 120

local TYPE_INSTANCE = "Instance"
local TYPE_REMOTE_EVENT = "RemoteEvent"

local ERR_ROOT_TYPE = "Instance expected, got %s"
local ERR_REMOTE_TIME_OUT = "Wait for partition timed out: %s"
local ERR_ROOT_DEPARENTED = "Instance was already deparented"

local Cache = {}

local ClientParams = TypeGuard.Params(TypeGuard.Instance():IsDescendantOf(game), TypeGuard.String(), TypeGuard.Boolean():Optional())

local function Client<T>(Root: Instance, PartitionName: string, ShouldYieldOnRemove: boolean?): (StoreInterface.Type<T>, ReplicatedStore.ReplicatedStore)
    if (VALIDATE_PARAMS) then
        ClientParams(Root, PartitionName, ShouldYieldOnRemove)
    end

    local Remote = Root:WaitForChild(PartitionName, REMOTE_WAIT_TIMEOUT)
    assert(Remote, ERR_REMOTE_TIME_OUT:format(PartitionName))
    assert(Root:IsDescendantOf(game), ERR_ROOT_DEPARENTED)

    local Cached = Cache[Remote]

    if (Cached) then
        return unpack(Cached)
    end

    local CleanerObject = Cleaner.new()

    local ReplicationObject = ReplicatedStore.new(Remote, false)
    ReplicationObject:InitClient()
    CleanerObject:Add(ReplicationObject)

    local Interface = StoreInterface.new(ReplicationObject)
    local CurrentLocation = Remote:GetFullName()

    CleanerObject:Add(Remote.AncestryChanged:Connect(function()
        if (ShouldYieldOnRemove) then
            task.wait()
        end

        if (Remote:IsDescendantOf(game)) then
            CurrentLocation = Remote:GetFullName()
        else
            print("[InstanceReplication] Remote deparented: " .. CurrentLocation)
            Cache[Remote] = nil
            CleanerObject:Clean()
        end
    end))

    Cache[Remote] = {Interface, ReplicationObject}

    return Interface, ReplicationObject
end

local ServerParams = TypeGuard.Params(TypeGuard.Instance():IsDescendantOf(game), TypeGuard.String(), (TypeGuard.Number():Or(TypeGuard.String("Defer"))):Optional(), TypeGuard.Boolean():Optional())

local function Server<T>(Root: Instance, PartitionName: string, Interval: (number | "Defer")?, ShouldYieldOnRemove: boolean?): (StoreInterface.Type<T>, ReplicatedStore.ReplicatedStore)
    if (VALIDATE_PARAMS) then
        ServerParams(Root, PartitionName, Interval, ShouldYieldOnRemove)
    end

    assert(typeof(Root) == TYPE_INSTANCE, ERR_ROOT_TYPE:format(typeof(Root)))
    assert(Root:IsDescendantOf(game), ERR_ROOT_DEPARENTED)

    local Remote = Instance.new(TYPE_REMOTE_EVENT)
    Remote.Name = PartitionName

    local Cached = Cache[Remote]

    if (Cached) then
        return unpack(Cached)
    end

    local CleanerObject = Cleaner.new()
    local ReplicationObject = ReplicatedStore.new(Remote, true)

    if (Interval) then
        if (Interval == "Defer") then
            ReplicationObject.DeferFunction = function(Callback)
                task.defer(Callback)
            end
        elseif (Interval > 0) then
            ReplicationObject.DeferFunction = function(Callback)
                task.delay(Interval, Callback)
            end
        end
    end

    ReplicationObject:InitServer()
    CleanerObject:Add(ReplicationObject)

    local Interface = StoreInterface.new(ReplicationObject)
    local CurrentLocation = Remote:GetFullName()

    CleanerObject:Add(Remote.AncestryChanged:Connect(function()
        if (Remote:IsDescendantOf(game)) then
            CurrentLocation = Remote:GetFullName()
        else
            if (ShouldYieldOnRemove) then
                task.wait()
            end

            print("[InstanceReplication] Remote deparented: " .. CurrentLocation)
            Cache[Remote] = nil
            CleanerObject:Clean()
        end
    end))

    Remote.Parent = Root
    Cache[Remote] = {Interface, ReplicationObject}
    return Interface, ReplicationObject
end

local function Auto(...)
    return IsClient and Client(...) or Server(...)
end

return Auto