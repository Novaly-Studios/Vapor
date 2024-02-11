--!nonstrict
local Players = game:GetService("Players")

local GeneralStore = require(script.Parent:WaitForChild("GeneralStore"))
local Cleaner = require(script.Parent.Parent:WaitForChild("Cleaner"))
local Signal = require(script.Parent.Parent:WaitForChild("Signal"))

local REMOVE_NODE = GeneralStore._REMOVE_NODE
local BuildFromPath = GeneralStore._BuildFromPath

local EMPTY_PATH = {}

-- Microprofiler tags
local REPLICATE_PROCESS_TAG = "ReplicatedStore.Incoming"

-- More strings
local DEFAULT_MERGE_CATEGORY = "*"

-- Types
local TYPE_TABLE = "table"
type RawStore = GeneralStore.RawStore
type StorePath = GeneralStore.StorePath

-- Logs, warnings & errors
local ERR_ROOT_OVERWRITE = "Attempt to set root table (path empty)"
local ERR_NO_PATH_GIVEN = "No path given!"

-- Settings
local MERGE_LIST_DEFAULT_SIZE = Players.MaxPlayers
local DEBUG_WARN_PATH_CONVERT = true
local PROFILE_FUNCTIONS = false

-----------------------------------------------------------------------------------

local InternalMerge = GeneralStore._InternalMerge

-- TODO: test performance of mutable versions
local function SerializeIncomingData(Data: RawStore): RawStore
    local Result = {}

    for Key, Value in Data do
        if (type(Value) == TYPE_TABLE) then
            if (Value.REMOVE_NODE) then
                Value = REMOVE_NODE
            else
                Value = SerializeIncomingData(Value)
            end
        end

        Result[tonumber(Key) or Key] = Value
    end

    return Result
end

local function ConvertToStringIndices(Data: RawStore): RawStore
    local Result = {}

    for Key, Value in Data do
        if (type(Value) == TYPE_TABLE) then
            Value = ConvertToStringIndices(Value)
        end

        Result[tostring(Key)] = Value
    end

    return Result
end

local ConvertPathToNumericRegistry = setmetatable({}, {__mode = "k"})

-- Converts an array's elements to all numerics
-- TODO: maybe mutate path (faster) and convert, mark as done so we don't re-process lots
-- TODO: just warn in merge procedure?
local function ConvertPathToNumeric(Path: StorePath)
    if (ConvertPathToNumericRegistry[Path]) then
        return
    end

    for Index = 1, #Path do
        local Value = Path[Index]
        local AsNumber = tonumber(Value)
        Path[Index] = AsNumber or Value

        if (DEBUG_WARN_PATH_CONVERT and AsNumber ~= Value and AsNumber) then
            warn("Key was converted to number: " .. tostring(Value))
        end
    end

    ConvertPathToNumericRegistry[Path] = true
end

-----------------------------------------------------------------------------------

local ReplicatedStore = {}
ReplicatedStore.__index = ReplicatedStore
ReplicatedStore.Type = "ReplicatedStore"

function ReplicatedStore.new(RemoteEvent, IsServer: boolean)
    assert(RemoteEvent, "No remote event given!")
    assert(IsServer ~= nil, "Please indicate whether this is running on server or client!")

    local self = {
        _Store = GeneralStore.new();

        _DeferredMerge = {};
        _BlockedPlayers = {};

        DeferFunction = function(Callback: () -> ())
            -- Immediate defer by default, but easy to
            -- switch to task.defer or some task.delay
            -- fixed duration function
            Callback()
        end;

        _Synced = false;
        _IsServer = IsServer;
        _Deferring = false;
        _Initialized = false;

        _RemoteEvent = RemoteEvent;

        OnDefer = Signal.new();
    };

    return setmetatable(self, ReplicatedStore)
end

-- Client method; syncs the store
function ReplicatedStore:InitClient()
    assert(not self._Initialized, "Already initialized on client!")

    local RemoteEvent = self._RemoteEvent
    local StoreObject = self._Store

    self._EventConnection = RemoteEvent.OnClientEvent:Connect(function(Data: RawStore?, InitialSync: boolean)
        debug.profilebegin(REPLICATE_PROCESS_TAG)

            --[[ if (Data == nil) then
                StoreObject:Clear()
                debug.profileend()
                return
            end ]]

            Data = SerializeIncomingData(Data)

            -- No need to merge data which comes in after we send off the initial sync request and wait for it to pass back
            if (not InitialSync and not self._Synced) then
                debug.profileend()
                return
            end

            -- Initial sync will be up to date and the whole structure so we can stop rejecting after we receive it
            if (InitialSync) then
                self._Synced = true
            end

            -- Received events are in-order
            StoreObject:Merge(Data)

            if (InitialSync) then
                task.spawn(function()
                    if (RemoteEvent.Name == "Profile" and RemoteEvent.Parent == Players.LocalPlayer) then
                        local StoreValue = StoreObject:Get({"DataLoaded"})

                        if (Data.DataLoaded and StoreValue) then
                            task.wait(5)

                            if (not StoreObject:Get({"DataLoaded"})) then
                                warn(`[ReplicatedStore] DataLoaded was overwritten`)
                            end
                        elseif (Data.DataLoaded and not StoreValue) then
                            warn(`[ReplicatedStore] DataLoaded not registered in store`)
                        else
                            warn(`[ReplicatedStore] got Profile data but DataLoaded was not present`)
                        end
                    end
                end)
            end
        debug.profileend()
    end)

    RemoteEvent:FireServer()
    self._Initialized = true

    task.spawn(function()
        if (RemoteEvent.Name == "Profile" and RemoteEvent.Parent == Players.LocalPlayer) then
            task.wait(15)

            if (not self._Synced) then
                warn(`[ReplicatedStore {RemoteEvent:GetFullName()}] failed to sync after 15 seconds / {tostring(RemoteEvent:GetAttribute("FS" .. tostring(Players.LocalPlayer.UserId):gsub("%-", "")))}`)
            end
        end
    end)
end

-- Server method; receives client requests
function ReplicatedStore:InitServer()
    assert(not self._Initialized, "Already initialized on server!")

    local RemoteEvent = self._RemoteEvent

    -- Client requests initial sync -> replicate whole state to client
    self._EventConnection = RemoteEvent.OnServerEvent:Connect(function(Player: Player)
        self:_FullSync(Player, true)
    end)

    self._Initialized = true
end

function ReplicatedStore:Destroy()
    self._EventConnection:Disconnect()
    self._Store:Destroy()
end

-- Obtains down a path; does not error
function ReplicatedStore:Get(Path: StorePath, DefaultValue: any?): any?
    Path = Path or EMPTY_PATH
    ConvertPathToNumeric(Path)
    return self._Store:Get(Path, DefaultValue)
end

-- Immediately update the internal Store object, but
-- create a defer point during which to merge changes
-- to the specific player(s) specified (or all by default)
function ReplicatedStore:_ServerMerge(Data: RawStore, SendTo: {Player | string}?)
    if (SendTo) then
        -- Send only to specific players
        for _, Player in SendTo do
            self:DeferMerge(Player.Name, Data)
        end
    else
        self:DeferMerge(DEFAULT_MERGE_CATEGORY, Data)
    end
end

function ReplicatedStore:Merge(Data: RawStore, ...)
    -- Keep our core store up to date
    self._Store:Merge(Data)

    -- Shaft off sending changes to clients to next defer function cycle (if server)
    if (self._IsServer) then
        self:_ServerMerge(Data, ...)
    end
end

function ReplicatedStore:Set(Path: StorePath, Value: any?, SendTo: {Player | string}?)
    assert(Path, ERR_NO_PATH_GIVEN)
    assert(#Path > 0, ERR_ROOT_OVERWRITE)

    Path = Path or EMPTY_PATH
    ConvertPathToNumeric(Path)

    if (type(Value) == TYPE_TABLE and self:Get(Path)) then
        -- Set using table -> remove previous value and overwrite (we don't want to merge 'set' tables in - unintuitive)
        self:Merge(BuildFromPath(Path, REMOVE_NODE), SendTo)
    end

    self:Merge(BuildFromPath(Path, Value == nil and REMOVE_NODE or Value), SendTo)
end

function ReplicatedStore:DeferMerge(Category: string, Data: RawStore)
    -- Insert into merge list for this category
    local DeferredMerge = self._DeferredMerge
    local MergeList = DeferredMerge[Category]

    if (not MergeList) then
        MergeList = table.create(MERGE_LIST_DEFAULT_SIZE)
        DeferredMerge[Category] = MergeList
    end

    table.insert(MergeList, Data)

    -- Activate next defer function
    if (not self._Deferring) then
        self._Deferring = true

        self.DeferFunction(function()
            -- Since this may yield for a later frame, check if ReplicatedStore was Destroyed & reject defer if so
            if (table.isfrozen(self)) then
                return
            end

            self._Deferring = false
            self:DeferProcess()
        end)
    end
end

function ReplicatedStore:DeferProcess()
    local BlockedPlayers = self._BlockedPlayers
    local DeferredMerge = self._DeferredMerge
    local RemoteEvent = self._RemoteEvent

    for PlayerName, Merges in DeferredMerge do
        local Merged = {}

        for Index = 1, #Merges do
            InternalMerge(Merges[Index], Merged, true)
        end

        Merged = ConvertToStringIndices(Merged)

        if (PlayerName == DEFAULT_MERGE_CATEGORY) then
            -- Default merge category -> all players except ones in the block list

            if (next(BlockedPlayers) == nil) then
                -- No blocked players -> FireAllClients broadcast (more efficient)
                RemoteEvent:FireAllClients(Merged, false)
            else
                for _, Player in Players:GetChildren() do
                    if (BlockedPlayers[Player.Name]) then
                        continue
                    end

                    RemoteEvent:FireClient(Player, Merged, false)
                end
            end

            continue
        end

        -- Player-specific merge category -> a specific player
        local GotPlayer = Players:FindFirstChild(PlayerName)

        if (not GotPlayer or BlockedPlayers[PlayerName]) then
            continue
        end

        RemoteEvent:FireClient(GotPlayer, Merged, false)
    end

    self._DeferredMerge = {}
    self.OnDefer:Fire()
end

function ReplicatedStore:GetValueChangedSignal(Path: StorePath): RBXScriptSignal
    Path = Path or EMPTY_PATH
    ConvertPathToNumeric(Path)
    return self._Store:GetValueChangedSignal(Path)
end

function ReplicatedStore:GetSubValueChangedSignal(Path: StorePath): RBXScriptSignal
    Path = Path or EMPTY_PATH
    ConvertPathToNumeric(Path)
    return self._Store:GetSubValueChangedSignal(Path)
end

function ReplicatedStore:Await(Path: StorePath, Timeout: number): any?
    Path = Path or EMPTY_PATH
    ConvertPathToNumeric(Path)
    return self._Store:Await(Path, Timeout)
end
ReplicatedStore.await = ReplicatedStore.Await

function ReplicatedStore:SetDebugLog(DebugLog: boolean)
    self._Store:SetDebugLog(DebugLog)
end

ReplicatedStore.setDebugLog = ReplicatedStore.SetDebugLog

function ReplicatedStore:_FullSync(Player: Player, InitialSync: boolean)
    self._RemoteEvent:FireClient(Player, ConvertToStringIndices(self:Get()), InitialSync)
    self._RemoteEvent:SetAttribute("FS" .. tostring(Player.UserId):gsub("%-", ""), true)
end

function ReplicatedStore:Block(Player: Player, Clear: boolean?)
    error("Unimplemented")

    local PlayerName = Player.Name
    local BlockedPlayers = self._BlockedPlayers
    assert(not BlockedPlayers[PlayerName])

    -- We'll want to clean up the connection & connection ref if player leaves
    local Connection; Connection = PlayerName.AncestryChanged:Connect(function(_, Parent)
        if (Parent == nil) then
            self:Unblock(Player, false)
        end
    end)

    BlockedPlayers[PlayerName] = Connection

    if (Clear) then
        self._RemoteEvent:FireClient(Player)
    end
end

function ReplicatedStore:Unblock(Player: Player, Renew: boolean?)
    error("Unimplemented")

    local PlayerName = Player.Name
    local BlockedPlayers = self._BlockedPlayers
    local Connection = BlockedPlayers[PlayerName]

    if (not Connection) then
        return
    end

    Connection:Disconnect()
    BlockedPlayers[PlayerName] = nil

    if (Renew) then
        self:_FullSync(Player, false)
    end
end

Cleaner.Wrap(ReplicatedStore)

export type ReplicatedStore = typeof(ReplicatedStore)

return ReplicatedStore