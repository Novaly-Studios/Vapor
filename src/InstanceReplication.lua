local RunService = game:GetService("RunService")
local IsClient = RunService:IsClient()

local Cleaner = require(script.Parent.Parent:WaitForChild("Cleaner"))
local TypeGuard = require(script.Parent.Parent:WaitForChild("TypeGuard"))
local StoreInterface = require(script.Parent:WaitForChild("StoreInterface"))
local ReplicatedStore = require(script.Parent:WaitForChild("ReplicatedStore"))

local VALIDATE_PARAMS = true
local REMOTE_WAIT_TIMEOUT = 60

local TYPE_INSTANCE = "Instance"
local TYPE_REMOTE_EVENT = "RemoteEvent"

local CLIENT_PARTITION_TAG = "ClientPartition"

local ERR_ROOT_TYPE = "Instance expected, got %s"
local ERR_REMOTE_TIME_OUT = "Wait for partition timed out: %s"
local ERR_ROOT_DEPARENTED = "Instance was already deparented"
local ERR_PARTITION_ALREADY_TAKEN = "Partition already taken: %s"
local ERR_PARTITION_ALREADY_ACTIVE = "Partition already active: %s"

local InstanceReplication = {}
InstanceReplication.__index = InstanceReplication
InstanceReplication.ReplicatedStoreCache = {}

local ClientParams = TypeGuard.Params(TypeGuard.Instance():IsDescendantOf(game), TypeGuard.String(), TypeGuard.Boolean():Optional())

local function Client(Root: Instance, PartitionName: string, ShouldYieldOnRemove: boolean?)
    if (VALIDATE_PARAMS) then
        ClientParams(Root, PartitionName, ShouldYieldOnRemove)
    end

    local Remote = Root:WaitForChild(PartitionName, REMOTE_WAIT_TIMEOUT)

    if (not Remote) then
        error(ERR_REMOTE_TIME_OUT:format(PartitionName))
    end

    if (Remote:GetAttribute(CLIENT_PARTITION_TAG)) then
        error(ERR_PARTITION_ALREADY_ACTIVE:format(PartitionName))
    end

    local CleanerObject = Cleaner.new()

    local ReplicationObject = ReplicatedStore.new(Remote, false)
    ReplicationObject:InitClient()
    CleanerObject:Add(ReplicationObject)

    local Interface = StoreInterface.new(ReplicationObject)
    CleanerObject:Add(Interface)

    local CurrentLocation = Remote:GetFullName()

    CleanerObject:Add(Remote.AncestryChanged:Connect(function(_, NewParent)
        if (ShouldYieldOnRemove) then
            task.wait()
        end

        if (NewParent == nil) then
            print("[InstanceReplication] Remote deparented: " .. CurrentLocation)
            CleanerObject:Clean()
        else
            CurrentLocation = Remote:GetFullName()
        end
    end))

    Remote:SetAttribute(CLIENT_PARTITION_TAG, true)

    return Interface, ReplicationObject
end

local ServerParams = TypeGuard.Params(TypeGuard.Instance():IsDescendantOf(game), TypeGuard.String(), TypeGuard.Number():Optional(), TypeGuard.Boolean():Optional())

local function Server(Root: Instance, PartitionName: string, Interval: number?, ShouldYieldOnRemove: boolean?)
    if (VALIDATE_PARAMS) then
        ServerParams(Root, PartitionName, Interval, ShouldYieldOnRemove)
    end

    assert(typeof(Root) == TYPE_INSTANCE, ERR_ROOT_TYPE:format(typeof(Root)))
    assert(Root.Parent ~= nil, ERR_ROOT_DEPARENTED)
    assert(Root:FindFirstChild(PartitionName) == nil, ERR_PARTITION_ALREADY_TAKEN:format(PartitionName))

    local Remote = Instance.new(TYPE_REMOTE_EVENT)
    Remote.Name = PartitionName

    local CleanerObject = Cleaner.new()
    local ReplicationObject = ReplicatedStore.new(Remote, true)

    if (Interval and Interval > 0) then
        ReplicationObject.DeferFunction = function(Callback)
            task.delay(Interval, Callback)
        end
    end

    ReplicationObject:InitServer()
    CleanerObject:Add(ReplicationObject)

    local Interface = StoreInterface.new(ReplicationObject)
    CleanerObject:Add(Interface)

    local CurrentLocation = Remote:GetFullName()

    CleanerObject:Add(Remote.AncestryChanged:Connect(function(_, NewParent)
        if (NewParent == nil) then
            if (ShouldYieldOnRemove) then
                task.wait()
            end

            print("[InstanceReplication] Remote deparented: " .. CurrentLocation)
            CleanerObject:Clean()
        else
            CurrentLocation = Remote:GetFullName()
        end
    end))

    Remote.Parent = Root

    return Interface, ReplicationObject
end

local function Auto(...)
    return IsClient and Client(...) or Server(...)
end

return Auto