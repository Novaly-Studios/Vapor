local RunService = game:GetService("RunService")
    local IsClient = RunService:IsClient()

local Cleaner = require(script.Parent.Parent:WaitForChild("Cleaner"))
local StoreInterface = require(script.Parent:WaitForChild("StoreInterface"))
local ReplicatedStore = require(script.Parent:WaitForChild("ReplicatedStore"))

local REMOTE_WAIT_TIMEOUT = 60

local TYPE_INSTANCE = "Instance"
local TYPE_REMOTE_EVENT = "RemoteEvent"

local CLIENT_PARTITION_TAG = "ClientPartition"

local ERR_ROOT_TYPE = "Instance expected, got %s"
local ERR_REMOTE_TIME_OUT = "Wait for partition timed out: %s"
local ERR_ROOT_DEPARENTED = ""
local ERR_PARTITION_ALREADY_TAKEN = "Partition already taken: %s"
local ERR_PARTITION_ALREADY_ACTIVE = "Partition already active: %s"

local InstanceReplication = {}
InstanceReplication.__index = InstanceReplication
InstanceReplication.ReplicatedStoreCache = {}

local function Client(Root: Instance, PartitionName: string)
    assert(typeof(Root) == TYPE_INSTANCE, ERR_ROOT_TYPE:format(typeof(Root)))
    assert(Root.Parent ~= nil, ERR_ROOT_DEPARENTED)

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

    CleanerObject:Add(Root.AncestryChanged:Connect(function(_, NewParent)
        if (NewParent == nil) then
            CleanerObject:Clean()
        end
    end))

    Remote:SetAttribute(CLIENT_PARTITION_TAG, true)

    return Interface, ReplicationObject
end

local function Server(Root: Instance, PartitionName: string, Interval: number?)
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

    CleanerObject:Add(Root.AncestryChanged:Connect(function(_, NewParent)
        if (NewParent == nil) then
            CleanerObject:Clean()
        end
    end))

    Remote.Parent = Root

    return Interface, ReplicationObject
end

local function Auto(...)
    return IsClient and Client(...) or Server(...)
end

return Auto