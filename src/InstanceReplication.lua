local RunService = game:GetService("RunService")
local IsClient = RunService:IsClient()

local ReplicatedStore = require(script.Parent.ReplicatedStore)
local StoreInterface = require(script.Parent.StoreInterface)
local TypeGuard = require(script.Parent.Parent.TypeGuard)
local Cleaner = require(script.Parent.Parent.Cleaner)

local VALIDATE_PARAMS = true
local REMOTE_WAIT_TIMEOUT = 240

local TYPE_INSTANCE = "Instance"
local TYPE_REMOTE_EVENT = "RemoteEvent"

local ERR_ROOT_TYPE = "Instance expected, got %s"
local ERR_REMOTE_TIME_OUT = "Wait for partition timed out: %s"
local ERR_ROOT_DEPARENTED = "Instance was already deparented"

local Cache = {}

local ClientParams = TypeGuard.Params(
    TypeGuard.Instance():IsDescendantOf(game),
    TypeGuard.String(),
    TypeGuard.Optional(TypeGuard.Boolean())
)
local function Client<T>(Root: Instance, PartitionName: string, ShouldYieldOnRemove: boolean?): (StoreInterface.StandardMethods<T>, typeof(ReplicatedStore))
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
    ReplicationObject.InitClient()
    CleanerObject:Add(ReplicationObject)

    CleanerObject:Add(Remote.AncestryChanged:Connect(function()
        if (ShouldYieldOnRemove) then
            task.wait()
        end

        if (not Remote:IsDescendantOf(game)) then
            Cache[Remote] = nil
            CleanerObject:Clean()
        end
    end))

    local Interface = StoreInterface.new(ReplicationObject)
    Cache[Remote] = {Interface, ReplicationObject}
    return Interface, ReplicationObject
end

local ServerParams = TypeGuard.Params(
    TypeGuard.Instance():IsDescendantOf(game),
    TypeGuard.String(),
    TypeGuard.Or(TypeGuard.Number(), TypeGuard.String("Defer"), TypeGuard.Nil()),
    TypeGuard.Optional(TypeGuard.Boolean())
)
local function Server<T>(Root: Instance, PartitionName: string, Interval: (number | "Defer")?, ShouldYieldOnRemove: boolean?): (StoreInterface.StandardMethods<T>, typeof(ReplicatedStore))
    if (VALIDATE_PARAMS) then
        ServerParams(Root, PartitionName, Interval, ShouldYieldOnRemove)
    end

    assert(typeof(Root) == TYPE_INSTANCE, ERR_ROOT_TYPE:format(typeof(Root)))
    assert(Root:IsDescendantOf(game), ERR_ROOT_DEPARENTED)

    local Remote = Root:FindFirstChild(PartitionName)
    if (not Remote) then
        Remote = Instance.new(TYPE_REMOTE_EVENT)
        Remote.Name = PartitionName
        Remote.Parent = Root
    end

    local Cached = Cache[Remote]
    if (Cached) then
        return unpack(Cached)
    end

    local CleanerObject = Cleaner.new()
    local DeferFunction

    if (Interval) then
        if (Interval == "Defer") then
            DeferFunction = function(Callback)
                task.defer(Callback)
            end
        elseif (Interval > 0) then
            DeferFunction = function(Callback)
                task.delay(Interval, Callback)
            end
        end
    end

    local ReplicationObject = ReplicatedStore.new(Remote, true, DeferFunction)
    ReplicationObject.InitServer()
    CleanerObject:Add(ReplicationObject)
    CleanerObject:Add(Remote.AncestryChanged:Connect(function()
        if (not Remote:IsDescendantOf(game)) then
            if (ShouldYieldOnRemove) then
                task.wait()
            end

            Cache[Remote] = nil
            CleanerObject:Clean()
        end
    end))

    local Interface = StoreInterface.new(ReplicationObject)
    Cache[Remote] = {Interface, ReplicationObject}
    return Interface, ReplicationObject
end

return (IsClient and Client or Server)