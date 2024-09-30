--!native
--!optimize 2
--!nonstrict
local Players = game:GetService("Players")

local GeneralStore = require(script.Parent.GeneralStore)
local TableUtil = require(script.Parent.Parent.TableUtil)
    local Map = TableUtil.Map.Map or TableUtil.Map.Map1D
local XSignal = require(script.Parent.Parent.XSignal)

local FlatPathDelimiter = GeneralStore._FlatPathDelimiter
local BuildFromPath = GeneralStore._BuildFromPath
local RemoveNode = GeneralStore._RemoveNode

type GeneralStoreStructure = GeneralStore.GeneralStoreStructure
type GeneralStorePath = GeneralStore.GeneralStorePath
type SendTo = {Player | string}

local DEFAULT_MERGE_CATEGORY = "*"
local REPLICATE_PROCESS_TAG = "ReplicatedStore.Incoming"
local EMPTY_PATH = {}

local ERR_ROOT_OVERWRITE = "Attempt to set root table (path empty)"
local ERR_NO_PATH_GIVEN = "No path given!"

local MERGE_LIST_DEFAULT_SIZE = Players.MaxPlayers
local DEBUG_WARN_PATH_CONVERT = true

-----------------------------------------------------------------------------------

local InternalMerge = GeneralStore._InternalMerge

local function ConvertIncomingData(Data: GeneralStoreStructure): GeneralStoreStructure
    local Result = table.clone(Data)
    local Remove

    for Key, Value in Data do
        if (type(Value) == "table") then
            Value = ConvertIncomingData(Value)
        end

        local AsNumber = tonumber(Key)
        if (AsNumber and AsNumber ~= Key) then
            Remove = Remove or {}
            table.insert(Remove, Key)
            Key = AsNumber
        end

        Result[Key] = Value
    end

    if (Remove) then
        for _, Key in Remove do
            Result[Key] = nil
        end
    end

    return Result
end

local ConvertPathToNumericRegistry = setmetatable({}, {__mode = "k"})

-- Converts an array's elements to all numerics.
local function ConvertPathToNumeric(Path: GeneralStorePath)
    if (ConvertPathToNumericRegistry[Path]) then
        return
    end

    for Index, Value in Path do
        local AsNumber = tonumber(Value)
        Path[Index] = AsNumber or Value

        if (DEBUG_WARN_PATH_CONVERT and AsNumber ~= Value and AsNumber) then
            warn("Key was converted to number: " .. tostring(Value))
        end
    end

    ConvertPathToNumericRegistry[Path] = true
end

local function DeepCopyWithPathExceptions(Subject, Table, SendToPaths, CurrentPath)
    local SendToValue = SendToPaths[CurrentPath]
    if (SendToValue and not SendToValue[Subject]) then
        print(">>>>>>>>>>>>>>Reject send to", CurrentPath)
        return nil
    end

    local Result = table.clone(Table)
    local Remove

    for Key, Value in Table do
        local KeyString = tostring(Key)
        local NewPath = CurrentPath .. KeyString .. FlatPathDelimiter

        if (type(Value) == "table") then
            Value = DeepCopyWithPathExceptions(Subject, Value, SendToPaths, NewPath)
        end

        -- Need to remove the previous key if it was a number & convert to a string
        -- to avoid mixed key type issues with RemoteEvent serialization.
        if (type(Key) == "number") then
            Remove = Remove or {}
            table.insert(Remove, Key)
        end

        Result[KeyString] = Value
    end

    if (Remove) then
        for _, Key in Remove do
            Result[Key] = nil
        end
    end

    return Result
end

-----------------------------------------------------------------------------------

local function ReplicatedStore(RemoteEvent: RemoteEvent, IsServer: boolean, DeferFunction: ((Callback: (() -> ())) -> ())?)
    assert(RemoteEvent, "No remote event given")
    assert(IsServer ~= nil, "Please indicate whether this is running on server or client")

    local self = {}

    local _DeferFunction = DeferFunction or function(Callback: () -> ())
        Callback()
    end

    local _GeneralStore = GeneralStore.new()
        local _GSGetSubValueChangedSignal = _GeneralStore.GetSubValueChangedSignal
        local _GSGetValueChangedSignal = _GeneralStore.GetValueChangedSignal
        local _GSSetDebugLog = _GeneralStore.SetDebugLog
        local _GSDestroy = _GeneralStore.Destroy
        local _GSAwait = _GeneralStore.Await
        local _GSMerge = _GeneralStore.Merge
        local _GSGet = _GeneralStore.Get
    local _GetPathString = GeneralStore._GetPathString

    local _PlayerDisconnectConnection
    local _EventConnection
    local _ExclusiveSendTo = {}
    local _BlockedPlayers = {}
    local _DeferredMerge = {}
    local _Initialized = false
    local _Deferring = false
    local _Destroyed = false
    local _OnDefer = XSignal.new()
    local _Synced = false

    -- Client method to sync the store.
    local function InitClient()
        assert(not _Initialized, "Already initialized on client!")

        _EventConnection = RemoteEvent.OnClientEvent:Connect(function(Data: GeneralStoreStructure, InitialSync: boolean)
            debug.profilebegin(REPLICATE_PROCESS_TAG)

                --[[ if (Data == nil) then
                    StoreObject:Clear()
                    debug.profileend()
                    return
                end ]]

                Data = ConvertIncomingData(Data)

                -- No need to merge data which comes in after we send off the initial sync request and wait for it to pass back.
                if (not InitialSync and not _Synced) then
                    debug.profileend()
                    return
                end

                -- Initial sync will be up to date and the whole structure so we can stop rejecting after we receive it.
                if (InitialSync) then
                    _Synced = true
                end

                _GSMerge(Data)
            debug.profileend()
        end)

        RemoteEvent:FireServer()
        _Initialized = true
    end
    self.InitClient = InitClient

    -- Obtains down a path; does not error
    local function Get(Path: GeneralStorePath?, DefaultValue: any?): any?
        Path = Path or EMPTY_PATH
        ConvertPathToNumeric(Path :: any)
        return _GSGet(Path, DefaultValue)
    end
    self.Get = Get

    local function _FullSync(Player: Player, InitialSync: boolean)
        local Result = DeepCopyWithPathExceptions(Player.Name, Get(), _ExclusiveSendTo, "")
        if (not Result) then
            return
        end

        task.wait(0.2)
        RemoteEvent:FireClient(Player, Result, InitialSync)
        RemoteEvent:SetAttribute("FS" .. tostring(Player.UserId):gsub("%-", ""), true)
    end

    -- Server method; receives client requests.
    local function InitServer()
        assert(not _Initialized, "Already initialized on server!")

        -- Client requests initial sync -> replicate whole state to client.
        _EventConnection = RemoteEvent.OnServerEvent:Connect(function(Player: Player)
            _FullSync(Player, true)
        end)

        -- Player disconnects -> remove from sync list.
        _PlayerDisconnectConnection = Players.PlayerRemoving:Connect(function(Player)
            local PlayerName = Player.Name
            local Remove = {}

            for Key, Value in _ExclusiveSendTo do
                if (typeof(Value) ~= "table") then
                    continue
                end

                Value[PlayerName] = nil

                if (next(Value) == nil) then
                    table.insert(Remove, Key)
                end
            end

            for _, Key in Remove do
                _ExclusiveSendTo[Key] = nil
            end
        end)

        _Initialized = true
    end
    self.InitServer = InitServer

    local function Destroy()
        _Destroyed = true
        _EventConnection:Disconnect()
        if (_PlayerDisconnectConnection) then
            _PlayerDisconnectConnection:Disconnect()
        end
        _GSDestroy()
    end
    self.Destroy = Destroy

    local function _DeferProcess()
        for PlayerName, Merges in _DeferredMerge do
            local Merged = {}
            for _, Value in Merges do
                InternalMerge(Merged, Value, true)
            end

            if (next(Merged) == nil) then
                continue
            end

            -- Default merge category -> all players except ones in the block list.
            if (PlayerName == DEFAULT_MERGE_CATEGORY) then
                for _, Player in Players:GetChildren() do
                    local Name = Player.Name
                    if (_BlockedPlayers[Name]) then
                        continue
                    end

                    local Result = DeepCopyWithPathExceptions(Name, Merged, _ExclusiveSendTo, "")
                    if (not Result) then
                        continue
                    end

                    RemoteEvent:FireClient(Player, Result, false)
                end

                continue
            end

            -- Player-specific merge category -> a specific player.
            local GotPlayer = Players:FindFirstChild(PlayerName)
            if (not GotPlayer or _BlockedPlayers[PlayerName]) then
                continue
            end

            local Result = DeepCopyWithPathExceptions(PlayerName, Merged, _ExclusiveSendTo, "")
            if (not Result) then
                continue
            end

            RemoteEvent:FireClient(GotPlayer, Result, false)
        end

        _DeferredMerge = {}
        _OnDefer:Fire()
    end

    local function _DeferMerge(Category: string, Data: GeneralStoreStructure)
        -- Insert into merge list for this category.
        local MergeList = _DeferredMerge[Category]
        if (not MergeList) then
            MergeList = table.create(MERGE_LIST_DEFAULT_SIZE)
            _DeferredMerge[Category] = MergeList
        end
        table.insert(MergeList, Data)

        -- Activate next defer function.
        if (not _Deferring) then
            _Deferring = true

            _DeferFunction(function()
                if (_Destroyed) then
                    return
                end

                _Deferring = false
                _DeferProcess()
            end)
        end
    end

    local function _ServerMerge(Data: GeneralStoreStructure, SendTo: SendTo?)
        if (SendTo) then
            -- Send only to specific players
            for _, Player in SendTo do
                _DeferMerge(Player.Name, Data)
            end
            return
        end

        _DeferMerge(DEFAULT_MERGE_CATEGORY, Data)
    end

    local function Merge(Data: GeneralStoreStructure, SendTo: SendTo?)
        -- Keep our core store up to date.
        _GSMerge(Data)

        -- Shaft off sending changes to clients to next defer function cycle (if server).
        if (IsServer) then
            _ServerMerge(Data, SendTo)
        end
    end
    self.Merge = Merge

    local function Set(Path: GeneralStorePath, Value: any?, SendTo: SendTo?)
        assert(Path, ERR_NO_PATH_GIVEN)
        assert(#Path > 0, ERR_ROOT_OVERWRITE)

        Path = Path or EMPTY_PATH
        ConvertPathToNumeric(Path)

        if (type(Value) == "table" and Get(Path)) then
            -- Set using table -> remove previous value and overwrite (we don't want to merge 'set' tables in - unintuitive)
            Merge(BuildFromPath(Path, RemoveNode), SendTo)
        end

        Merge(BuildFromPath(Path, Value == nil and RemoveNode or Value), SendTo)
    end
    self.Set = Set

    local function GetValueChangedSignal(Path: GeneralStorePath): RBXScriptSignal
        Path = Path or EMPTY_PATH
        ConvertPathToNumeric(Path)
        return _GSGetValueChangedSignal(Path)
    end
    self.GetValueChangedSignal = GetValueChangedSignal

    local function GetSubValueChangedSignal(Path: GeneralStorePath): RBXScriptSignal
        Path = Path or EMPTY_PATH
        ConvertPathToNumeric(Path)
        return _GSGetSubValueChangedSignal(Path)
    end
    self.GetSubValueChangedSignal = GetSubValueChangedSignal

    local function Await(Path: GeneralStorePath, Timeout: number): any?
        Path = Path or EMPTY_PATH
        ConvertPathToNumeric(Path)
        return _GSAwait(Path, Timeout)
    end
    self.Await = Await

    local function SetDebugLog(DebugLog: boolean)
        _GSSetDebugLog(DebugLog)
    end
    self.SetDebugLog = SetDebugLog

    local function ExclusiveSync(Path: GeneralStorePath, Players: {Player}?)
        assert(Path, "No path given")
        ConvertPathToNumeric(Path)
        _ExclusiveSendTo[_GetPathString(Path)] = (Players and Map(Players, function(Player)
            return true, Player.Name
        end) or nil)
    end
    self.ExclusiveSync = ExclusiveSync

    --[[ local function Block(Player: Player, Clear: boolean?)
        error("Unimplemented")

        local PlayerName = Player.Name
        local BlockedPlayers = _BlockedPlayers
        assert(not BlockedPlayers[PlayerName])

        local Connection; Connection = Player.AncestryChanged:Connect(function(_, Parent)
            if (Parent == nil) then
                Unblock(Player, false)
            end
        end)

        BlockedPlayers[PlayerName] = Connection

        if (Clear) then
            _RemoteEvent:FireClient(Player)
        end
    end

    local function Unblock(Player: Player, Renew: boolean?)
        error("Unimplemented")

        local PlayerName = Player.Name
        local BlockedPlayers = _BlockedPlayers
        local Connection = BlockedPlayers[PlayerName]

        if (not Connection) then
            return
        end

        Connection:Disconnect()
        BlockedPlayers[PlayerName] = nil

        if (Renew) then
            _FullSync(Player, false)
        end
    end ]]

    return self
end

return table.freeze({
    new = ReplicatedStore;
})