local Players = game:GetService("Players")

local GeneralStore = require(script.Parent:WaitForChild("GeneralStore"))
local TypeGuard = require(script.Parent.Parent:WaitForChild("TypeGuard"))
local Cleaner = require(script.Parent.Parent:WaitForChild("Cleaner"))
local XSignal = require(script.Parent.Parent:WaitForChild("XSignal"))
local Shared = require(script.Parent:WaitForChild("Shared"))

local BuildFromPath = Shared.BuildFromPath
local InternalMerge = Shared.InternalMerge
local RemoveNode = Shared.RemoveNode

type StorePath = Shared.StorePath

local EMPTY_PATH = {}

local REPLICATE_PROCESS_TAG = "ReplicatedStore.Incoming"
local DEFAULT_SEND_TO_CATEGORY = "*"
local EMPTY_STRING = ""
local TYPE_TABLE = "table"

local METHOD_SHORTENINGS = { -- Sent over network, so gotta save space!
    ArrayInsertUsingPathArray = "1";
    ArrayRemoveUsingPathArray = "2";
    IncrementUsingPathArray = "3";
    Merge = "4";

    ArrayInsertUsingPathString = "5";
    ArrayRemoveUsingPathString = "6";
}

-- Settings
local MERGE_LIST_DEFAULT_SIZE = Players.MaxPlayers
local DEBUG_WARN_PATH_CONVERT = true
local VALIDATE_PARAMS = true

-----------------------------------------------------------------------------------

--- Deep copies a table such that:
--- - All string keys are converted to numbers if they can be converted.
--- - All sub-tables marked 'RemoveNode' are substituted with a reference to the real RemoveNode, used in the merging process to remove values at paths.
--- @todo: test performance of mutable versions.
local function SerializeIncomingData(Data: any): any
    local Result = {}

    for Key, Value in Data do
        if (type(Value) == TYPE_TABLE) then
            if (Value._REMOVE_NODE) then
                Value = RemoveNode
            else
                Value = SerializeIncomingData(Value)
            end
        end

        Result[tonumber(Key) or Key] = Value
    end

    return Result
end

--- Deep copies a table such that:
--- - All numerical keys are converted to strings if they can be.
local function ConvertToStringIndices(Data: any): any
    local Result = {}

    for Key, Value in Data do
        if (type(Value) == TYPE_TABLE) then
            Value = ConvertToStringIndices(Value)
        end

        Result[tostring(Key)] = Value
    end

    return Result
end

local ConvertPathToNumericCache = setmetatable({}, {__mode = "k"})
--- Mutably converts a path array's values to numeric where possible.
local function ConvertPathToNumeric(Path: StorePath)
    if (ConvertPathToNumericCache[Path]) then
        return
    end

    for Index, Value in Path do
        local AsNumber = tonumber(Value)
        Path[Index] = AsNumber or Value

        if (DEBUG_WARN_PATH_CONVERT and AsNumber ~= Value and AsNumber) then
            warn("Key was converted to number: " .. tostring(Value))
        end
    end

    ConvertPathToNumericCache[Path] = true
end

-----------------------------------------------------------------------------------

--- An extension of GeneralStore, allowing for optimized & batched replication of arbitrary data to particular clients.
local ReplicatedStore = {}
ReplicatedStore.__index = ReplicatedStore
ReplicatedStore.Type = "ReplicatedStore"

local ConstructorParams = TypeGuard.Params(TypeGuard.Instance("RemoteEvent"):Or(TypeGuard.Object()), TypeGuard.Boolean())
--- Creates a new ReplicatedStore object.
function ReplicatedStore.new(RemoteEvent: any, IsServer: boolean): typeof(ReplicatedStore)
    if (VALIDATE_PARAMS) then
        ConstructorParams(RemoteEvent, IsServer)
    end

    local self = {
        _Store = GeneralStore.new();

        _SyncedPlayers = {};
        _BlockedPlayers = {};
        _DeferredInstructions = {};

        --[[ DeferFunction = function(Callback: () -> ())
            -- Immediate defer by default, but easy to
            -- switch to task.defer or some task.delay
            -- fixed duration function
            Callback()
        end; ]]

        _Synced = false;
        _IsServer = IsServer;
        _TestMode = false;
        _Deferring = false;
        _Initialized = false;

        _RemoteEvent = RemoteEvent;

        OnDefer = XSignal.new();
    };

    return setmetatable(self, ReplicatedStore)
end

-- Client method; syncs the store
function ReplicatedStore:InitClient()
    assert(not self._Initialized, "Already initialized on client!")

    local RemoteEvent = self._RemoteEvent
    local StoreObject = self._Store

    self._EventConnection = RemoteEvent.OnClientEvent:Connect(function(Data: any?, InitialSync: boolean)
        debug.profilebegin(REPLICATE_PROCESS_TAG)

            if (Data == nil) then
                StoreObject:Clear()
                debug.profileend()
                return
            end

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

            for _, Call in Data do
                --self[Call.Method](self, unpack(Call.Args))
                self[Call[1]](self, unpack(Call[2]))
            end
        debug.profileend()
    end)

    RemoteEvent:FireServer()
    self._Initialized = true
end

--- Server method - receives client requests.
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

--- See `GeneralStore.GetUsingPathArray`. Has an optional SendTo array which can contain a list of players (or no players) to selectively
--- replicate this to.
function ReplicatedStore:GetUsingPathArray(Path: StorePath?, DefaultValue: any?): any?
    Path = Path or EMPTY_PATH
    ConvertPathToNumeric(Path)

    return self._Store:GetUsingPathArray(Path, DefaultValue)
end
ReplicatedStore.getUsingPathArray = ReplicatedStore.GetUsingPathArray

--- See `GeneralStore.GetUsingPathString`. Has an optional SendTo array which can contain a list of players (or no players) to selectively
--- replicate this to.
function ReplicatedStore:GetUsingPathString(...): any?
    return self._Store:GetUsingPathString(...)
end
ReplicatedStore.getUsingPathString = ReplicatedStore.GetUsingPathString

--- See `GeneralStore.ArrayInsertUsingPathArray`. Has an optional SendTo array which can contain a list of players (or no players) to selectively
--- replicate this to.
function ReplicatedStore:ArrayInsertUsingPathArray(Path: StorePath?, Value: any, At: number?, SendTo: {Player}?): number
    Path = Path or EMPTY_PATH
    ConvertPathToNumeric(Path)

    -- Keep our core store up to date
    local Result = self._Store:ArrayInsertUsingPathArray(Path, Value, At)
    self:_QueueMethod(METHOD_SHORTENINGS.ArrayInsertUsingPathArray, SendTo, Path, Value, At)
    return Result
end
ReplicatedStore.arrayInsertUsingPathArray = ReplicatedStore.ArrayInsertUsingPathArray

--- See `GeneralStore.ArrayInsertUsingPathString`. Has an optional SendTo array which can contain a list of players (or no players) to selectively
--- replicate this to.
function ReplicatedStore:ArrayInsertUsingPathString(PathString: string, Value: any, At: number?, SendTo: {Player}?): number
    local Result = self._Store:ArrayInsertUsingPathString(PathString, Value, At)
    self:_QueueMethod(METHOD_SHORTENINGS.ArrayInsertUsingPathString, SendTo, PathString, Value, At)
    return Result
end
ReplicatedStore.arrayInsertUsingPathString = ReplicatedStore.ArrayInsertUsingPathString

--- See `GeneralStore.ArrayRemoveUsingPathArray`. Has an optional SendTo array which can contain a list of players (or no players) to selectively
--- replicate this to.
function ReplicatedStore:ArrayRemoveUsingPathArray(Path: StorePath, At: number?, SendTo: {Player}?): (any?, number)
    Path = Path or EMPTY_PATH
    ConvertPathToNumeric(Path)

    local RemovedValue, RemovedIndex = self._Store:ArrayRemoveUsingPathArray(Path, At)
    self:_QueueMethod(METHOD_SHORTENINGS.ArrayRemoveUsingPathArray, SendTo, Path, At)
    return RemovedValue, RemovedIndex
end
ReplicatedStore.arrayRemoveUsingPathArray = ReplicatedStore.ArrayRemoveUsingPathArray

--- See `GeneralStore.ArrayRemoveUsingPathString`. Has an optional SendTo array which can contain a list of players (or no players) to selectively
--- replicate this to.
function ReplicatedStore:ArrayRemoveUsingPathString(PathString: string, Value: any, At: number?, SendTo: {Player}?): number
    local RemovedValue, RemovedIndex = self._Store:ArrayRemoveUsingPathString(PathString, Value, At)
    self:_QueueMethod(METHOD_SHORTENINGS.ArrayRemoveUsingPathString, SendTo, PathString, Value, At)
    return RemovedValue, RemovedIndex
end
ReplicatedStore.arrayRemoveUsingPathString = ReplicatedStore.ArrayRemoveUsingPathString

--- See `GeneralStore.Merge`. Has an optional SendTo array which can contain a list of players (or no players) to selectively
--- replicate this to.
function ReplicatedStore:Merge(Data: any, SendTo: {Player}?)
    -- Keep our core store up to date
    self._Store:Merge(Data)
    self:_QueueMethod(METHOD_SHORTENINGS.Merge, SendTo, Data)
end
ReplicatedStore.merge = ReplicatedStore.Merge

--- See `GeneralStore.IncrementUsingPathArray`. Has an optional SendTo array which can contain a list of players (or no players) to selectively
--- replicate this to.
function ReplicatedStore:IncrementUsingPathArray(Path: StorePath, By: number?, Default: number?, SendTo: {Player}?): number
    ConvertPathToNumeric(Path)

    local NewValue = self._Store:IncrementUsingPathArray(Path, By, Default)
    self:_QueueMethod(METHOD_SHORTENINGS.IncrementUsingPathArray, SendTo, Path, By, Default)
    return NewValue
end
ReplicatedStore.incrementUsingPathArray = ReplicatedStore.IncrementUsingPathArray

--- See `GeneralStore.SetUsingPathArray`. Has an optional SendTo array which can contain a list of players (or no players) to selectively
--- replicate this to.
function ReplicatedStore:SetUsingPathArray(Path: StorePath, Value: any?, SendTo: {Player}?)
    Path = Path or EMPTY_PATH
    ConvertPathToNumeric(Path)

    if (type(Value) == TYPE_TABLE and self:GetUsingPathArray(Path)) then
        -- Set using table -> remove previous value and overwrite (we don't want to merge 'set' tables in - unintuitive)
        self:Merge(BuildFromPath(Path, RemoveNode), SendTo)
    end

    self:Merge(BuildFromPath(Path, Value == nil and RemoveNode or Value), SendTo)
end
ReplicatedStore.setUsingPathArray = ReplicatedStore.SetUsingPathArray

--- See `GeneralStore.GetValueChangedSignalUsingPathArray`.
function ReplicatedStore:GetValueChangedSignalUsingPathArray(Path: StorePath): typeof(XSignal)
    Path = Path or EMPTY_PATH
    ConvertPathToNumeric(Path)

    return self._Store:GetValueChangedSignalUsingPathArray(Path)
end
ReplicatedStore.GetValueChangedSignalUsingPathArray = ReplicatedStore.GetValueChangedSignalUsingPathArray

--- See `GeneralStore.AwaitUsingPathArray`.
function ReplicatedStore:AwaitUsingPathArray(Path: StorePath, ...): any?
    Path = Path or EMPTY_PATH
    ConvertPathToNumeric(Path)

    return self._Store:AwaitUsingPathArray(Path, ...)
end
ReplicatedStore.awaitUsingPathArray = ReplicatedStore.AwaitUsingPathArray

--- See `GeneralStore.AwaitUsingPathString`.
function ReplicatedStore:AwaitUsingPathString(...): any?
    return self._Store:AwaitUsingPathString(...)
end
ReplicatedStore.awaitUsingPathString = ReplicatedStore.AwaitUsingPathString

--- See `GeneralStore.SetDebugLog`.
function ReplicatedStore:SetDebugLog(DebugLog: boolean)
    self._Store:SetDebugLog(DebugLog)
end
ReplicatedStore.setDebugLog = ReplicatedStore.SetDebugLog

--- Untested - do not use.
--- Note: likely will require erasure of player's merge / call batches too.
--- Blocks a player from receiving updates from this store and optionally nullifies the store on their client.
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
ReplicatedStore.block = ReplicatedStore.Block

--- Untested - do not use. This will likely be used for an upcoming world streaming system.
--- Unblocks a player from receiving updates from this store and optionally re-sends the store.
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
        self._SyncedPlayers[Player.UserId] = nil
        self:_FullSync(Player, false)
    end
end
ReplicatedStore.unblock = ReplicatedStore.Unblock

--- Shaft off sending changes to clients to next defer function cycle (if server). See _PrepareDefer and _DeferProcess
--- for the subsequent data preparation steps.
function ReplicatedStore:_QueueMethod(Name: string, SendTo: {Player}?, ...)
    if (self._IsServer) then
        if (SendTo) then
            for _, Player in SendTo do
                self:_PrepareDefer(Player.Name, Name, ...)
            end
        else
            self:_PrepareDefer(DEFAULT_SEND_TO_CATEGORY, Name, ...)
        end
    end
end

local ShortenedMergeName = METHOD_SHORTENINGS.Merge
--- Enqueues fundamental mutation method calls (Merge, ArrayInsert, ArrayRemove, Increment, etc.) to be sent to clients,
--- attempts to optimize them, and initiates a defer point after which the batch will be sent.
--- @todo Condense down consecutive non-merge-optimizable method args into {Method = "Test", Args = { {1}, {2, 3}, {4} }}
function ReplicatedStore:_PrepareDefer(SendToCategory: string, Method: string, ...)
    debug.profilebegin("PrepareDefer(" .. Method .. ")")

    -- Find or setup _instruction list for that player
    local DeferredInstructions = self._DeferredInstructions
    local InstructionList = DeferredInstructions[SendToCategory]

    if (not InstructionList) then
        InstructionList = table.create(MERGE_LIST_DEFAULT_SIZE)
        DeferredInstructions[SendToCategory] = InstructionList
    end

    -- Record the call
    if (Method == ShortenedMergeName) then
        -- Condense down consecutive merge calls into a single merge call to send to the client
        -- Otherwise begin by just creating a new merge on the list
        -- Note: any theoretical GeneralStore mutation operation that can be *fully* implemented with Merge / Set calls should do so as this is optimised by the following mechanism
        local MergeIn = select(1, ...)
        local LastCall = InstructionList[#InstructionList]
        local LastMerge

        if (LastCall and LastCall[1] == ShortenedMergeName) then
            LastMerge = LastCall[2][1]
        end

        if (LastMerge) then
            InternalMerge(MergeIn, LastMerge, true)
        else
            table.insert(InstructionList, {Method, {MergeIn}})
        end
    else
        -- Non-merge calls deoptimize the above, but it has to happen to avoid desync
        table.insert(InstructionList, {Method, {...}})
    end

    -- Activate next defer function
    if (not self._Deferring) then
        self._Deferring = true

        local DeferFunction = self.DeferFunction

        if (DeferFunction) then
            DeferFunction(function()
                -- Since this may yield for a later frame, check if ReplicatedStore was Destroyed & reject defer if so
                if (table.isfrozen(self)) then
                    return
                end

                self._Deferring = false
                self:_DeferProcess()
            end)
        else
            self._Deferring = false
            self:_DeferProcess()
        end
    end

    debug.profileend()
end

--- Extension of _PrepareDefer. Initiates a defer point for sending data to the client, during which
--- specific calls will be optimised into a compressed structure.
function ReplicatedStore:_DeferProcess()
    local DeferredInstructions = self._DeferredInstructions
    local BlockedPlayers = self._BlockedPlayers
    local RemoteEvent = self._RemoteEvent

    for PlayerName, Data in DeferredInstructions do
        -- Default category -> send this data to all players except ones in the block list
        if (PlayerName == DEFAULT_SEND_TO_CATEGORY) then
            if (next(BlockedPlayers) == nil) then
                -- No blocked players -> FireAllClients broadcast (more efficient)
                RemoteEvent:FireAllClients(Data, false)
            else
                for _, Player in Players:GetChildren() do
                    if (BlockedPlayers[Player.Name]) then
                        continue
                    end

                    RemoteEvent:FireClient(Player, Data, false)
                end
            end

            continue
        end

        -- Player-specific -> send to that player
        local GotPlayer = Players:FindFirstChild(PlayerName)

        if (not GotPlayer or BlockedPlayers[PlayerName]) then
            continue
        end

        RemoteEvent:FireClient(GotPlayer, Data, false)
    end

    table.clear(self._DeferredInstructions)
    self.OnDefer:Fire()
end

--- Fully syncs this store's data down to a specific client who requests it.
--- Blocks subsequent calls to ensure exploiters cannot overload the server.
function ReplicatedStore:_FullSync(Player: Player, InitialSync: boolean)
    local Package = {{METHOD_SHORTENINGS.Merge, {ConvertToStringIndices(self:GetUsingPathString())}}}

    if (self._TestMode) then
        self._RemoteEvent:FireClient(Player, Package, InitialSync)
        return
    end

    local SyncedPlayers = self._SyncedPlayers
    local UserID = Player.UserId

    if (SyncedPlayers[UserID]) then
        print("[ReplicatedStore] Reject sync request from " .. Player.Name)
        return
    end

    SyncedPlayers[UserID] = true

    local Connection; Connection = Player.AncestryChanged:Connect(function(_, NewParent)
        if (NewParent ~= nil) then
            return
        end

        Connection:Disconnect()
        SyncedPlayers[UserID] = nil
    end)

    self._RemoteEvent:FireClient(Player, Package, InitialSync)
end

for OriginalName, ShortenedName in METHOD_SHORTENINGS do
    ReplicatedStore[ShortenedName] = ReplicatedStore[OriginalName]
end

Cleaner.Wrap(ReplicatedStore)

export type ReplicatedStore = typeof(ReplicatedStore)

return ReplicatedStore