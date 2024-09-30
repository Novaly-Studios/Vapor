--!native
--!optimize 2
--!nonstrict

-- Allows easy command bar paste.
if (not script) then
    script = game:GetService("ReplicatedFirst").Vapor.GeneralStore
end

local XSignal = require(script.Parent.Parent.XSignal)

export type GeneralStoreKey = string | number
export type GeneralStoreStructure = {[GeneralStoreKey]: any}
export type GeneralStorePath = {GeneralStoreKey}

local FLAT_PATH_DELIMITER = "^"
local DEFAULT_TIMEOUT = 240
local TIMEOUT_WARN = 5
local EMPTY_STRING = ""

local NAME_PREFIX = "[GeneralStore] "

local LOG_UP_PROPAGATE = NAME_PREFIX .. "Up-propagate %s"
local LOG_CHANGE = NAME_PREFIX .. "Change %s (%s -> %s)"
local LOG_CREATE = NAME_PREFIX .. "Create %s = %s"
local LOG_DESTROY = NAME_PREFIX .. "Destroy %s"

local WARN_INFINITE_WAIT = NAME_PREFIX .. "Potentially infinite wait on '%s'.\n%s"

local ERR_STORE_TIMEOUT_REACHED = NAME_PREFIX .. "Store timeout reached! Path: %s (%ds)"
local ERR_AWAIT_PATH_NOT_STRING = NAME_PREFIX .. "AwaitingPath not a string!"
local ERR_AWAIT_PATH_NOT_GIVEN = NAME_PREFIX .. "AwaitingPath not given!"
local ERR_MERGE_ATOM_ATTEMPT = NAME_PREFIX .. "Cannot merge an atom into the store!"
local ERR_NO_ITEMS_IN_PATH = NAME_PREFIX .. "No items in path (no ascendants derivable)"
local ERR_ROOT_OVERWRITE = NAME_PREFIX .. "Attempt to set root table (path empty)"
local ERR_NO_VALUE_GIVEN = NAME_PREFIX .. "No value given!"
local ERR_NO_PATH_GIVEN = NAME_PREFIX .. "No path given!"

-- Don't change...
local REMOVE_NODE = {REMOVE_NODE = true}
local EMPTY_PATH = {}

-----------------------------------------------------------------------------------
local function PathTraverse(Root: GeneralStoreStructure, Path: string, Callback: (string, any, string, string) -> ())
    for Key, Value in Root do
        local NewPath = Path .. tostring(Key) .. FLAT_PATH_DELIMITER

        if (type(Value) == "table") then
            PathTraverse(Value, NewPath, Callback)
        end

        Callback(NewPath, Value, Key, Path)
    end
end

local function GetPathString(Path: GeneralStorePath): string
    local Result = EMPTY_STRING
    for _, Value in Path do
        Result ..= tostring(Value) .. FLAT_PATH_DELIMITER
    end
    return Result
end

local function InternalMerge(Into, Data)
    for Key, Value in Data do
        if (Value == REMOVE_NODE) then
            Into[Key] = REMOVE_NODE
            continue
        end

        if (type(Value) == "table") then
            local Existing = Into[Key]

            if (Existing == REMOVE_NODE) then
                Existing = table.clone(REMOVE_NODE)
                Into[Key] = Existing
            elseif (not Existing) then
                Existing = {}
                Into[Key] = Existing
            end

            InternalMerge(Existing, Value)
            continue
        end

        Into[Key] = Value
    end
end

local function BuildFromPath(Path: GeneralStorePath, Value: any): GeneralStoreStructure
    assert(Path, ERR_NO_PATH_GIVEN)
    assert(Value ~= nil, ERR_NO_VALUE_GIVEN)

    local Length = #Path
    assert(Length > 0, ERR_NO_ITEMS_IN_PATH)

    local Built = {}
    local Last = Built

    for Index = 1, Length - 1 do
        local Key = Path[Index]
        local Temp = {}
        Last[Key] = Temp
        Last = Temp
    end

    Last[Path[Length]] = Value
    return Built
end

-----------------------------------------------------------------------------------

local function Store(Defer: ((Callback: (() -> ())) -> ())?, DefaultStructure: any?)
    local DeferFunction = Defer
    local self = {}
    
    local _ShaftedEvents = {} -- ShaftedEvents: {[string]: Signal}
    local _Structure = {}
    local _Deferring = false
    local _Destroyed = false
    local _DebugLog = false
    local _Awaiting = {} -- Awaiting: {[PathString]: Signal}

    --- Destroys the store, firing nil to all sub-values & disconnecting all events.
    local function Destroy()
        -- Todo: use Clear()
        _Destroyed = true

        for _, Event in _Awaiting do
            Event:Fire(nil)
            Event:Destroy()
        end
    end
    self.Destroy = Destroy

    --- Queues up changes in the store which will only fire to value
    --- changed signals at a later point with the latest values.
    local function _DeferEventFlat(PathString: string, New: any?, Old: any?, Key: string?, ParentPathName: string?)
        if (not _Awaiting[PathString]) then
            return
        end

        local ShaftedEvents = _ShaftedEvents
        ShaftedEvents[PathString] = {New, Old, Key, ParentPathName}

        if (not _Deferring) then
            _Deferring = true

            DeferFunction(function()
                if (_Destroyed) then
                    return
                end

                _ShaftedEvents = {}
                _Deferring = false

                for PathName, Change in ShaftedEvents do
                    local Event = _Awaiting[PathName]
                    if (Event) then
                        local Value, Old = Change[1], Change[2]
                        Event:Fire(Value, Old, Value == Old)
                    end

                    local ParentPathName = Change[4]
                    if (ParentPathName) then
                        local ParentEvent = _Awaiting[ParentPathName .. "\255"]
                        if (ParentEvent) then
                            ParentEvent:Fire(Change[3], Change[1], Change[2])
                        end
                    end
                end
            end)
        end
    end

    --- Fires a signal when an atom or table was changed in a merge
    local function _PathWasChanged(PathName: string, Value: any?, Old: any?, Key: string?, ParentPathName: string?)
        if (DeferFunction) then
            _DeferEventFlat(PathName, Value, Old, Key, ParentPathName)
        else
            local Event = _Awaiting[PathName]
            if (Event) then
                Event:Fire(Value, Old, Value == Old)
            end

            if (ParentPathName) then
                local ParentEvent = _Awaiting[ParentPathName .. "\255"]
                if (ParentEvent) then
                    ParentEvent:Fire(Key, Value, Old)
                end
            end
        end

        if (_DebugLog) then
            PathName = (PathName == "" and "ROOT" or PathName)

            if (Old ~= nil and Value ~= nil) then
                if (Old == Value) then
                    --> Up-propagated
                    print(LOG_UP_PROPAGATE:format(PathName))
                else
                    --> Changed
                    print(LOG_CHANGE:format(PathName, tostring(Old), tostring(Value)))
                end
            elseif (Old == nil and Value ~= nil) then
                --> Creation
                print(LOG_CREATE:format(PathName, tostring(Value)))
            elseif (Old ~= nil and Value == nil) then
                --> Destruction
                print(LOG_DESTROY:format(PathName, tostring(Value)))
            end
        end
    end

    --- Obtains down a path, and does not error for nil values.
    local function Get(Path: GeneralStorePath, DefaultValue: any?): any?
        Path = Path or EMPTY_PATH

        local Result = _Structure
        for _, Key in Path do
            Result = Result[Key]
            if (Result == nil) then
                return DefaultValue
            end
        end
        return Result
    end
    self.Get = Get

    local function _Merge(ParentPath, Data, Into)
        local ExistingKey = next(Into)
        local DidChange = false
        local LastType

        if (ExistingKey) then
            LastType = typeof(ExistingKey)
        end

        for Key, Value in Data do
            local ValuePath = ParentPath .. tostring(Key) .. FLAT_PATH_DELIMITER
            local ExistingValue = Into[Key]

            local KeyType = typeof(Key)
            local ExistingValueType = typeof(ExistingValue)

            if (not LastType) then
                LastType = KeyType
            end

            -- Mixed key types bad bad bad bad bad.
            if (KeyType ~= LastType) then
                error(`{NAME_PREFIX}Attempted to insert using mixed keys! ({ValuePath}: {LastType} + {KeyType})`)
            end

            if (Value == ExistingValue) then
                -- No change, so no need to fire off any events (which would otherwise happen).
                continue
            end

            local ValueIsTable = (type(Value) == "table")
            if (ValueIsTable and Value.REMOVE_NODE) then
                -- REMOVE_NODE is used in place of 'nil' in tables (since obviously
                -- nil-ed values won't exist, so this acts as a signifier to remove)

                if (ExistingValue == nil) then
                    continue
                end

                -- If REMOVE_NODE table has 2 keys then it must have been removed then merged.
                -- Semantically this is requires remove table, then merge table, so skip "continue".
                local AllowContinue = (next(Value, (next(Value)))) == nil
                local Skip = false
                DidChange = true

                if (ExistingValueType == "table") then
                    -- "Remove table" -> all awaiting events on sub-paths should be fired
                    Into[Key] = nil

                    PathTraverse(ExistingValue, ValuePath, function(NewPath, OldValue, Key, ParentPath)
                        _PathWasChanged(NewPath, nil, OldValue, Key, ParentPath)
                    end)
                    _PathWasChanged(ValuePath, nil, ExistingValue, Key, ParentPath)

                    if (AllowContinue) then
                        continue
                    end

                    ExistingValue = nil
                    Skip = true
                end

                -- "Remove atom" -> nullify, then signify path was changed to nil
                if (not Skip) then
                    Into[Key] = nil
                    _PathWasChanged(ValuePath, nil, ExistingValue, Key, ParentPath)
                    ExistingValue = nil

                    if (AllowContinue) then
                        continue
                    end
                end
            end

            if (ValueIsTable) then
                if (Value.REMOVE_NODE) then
                    Value.REMOVE_NODE = nil
                end

                -- Item is a sub-table -> recurse and then activate changed event (up-propagated)
                local IsNew = (ExistingValue == nil)

                if (IsNew) then
                    DidChange = true
                    ExistingValue = {}
                    Into[Key] = ExistingValue
                end

                local Temp = _Merge(ValuePath, Value, ExistingValue)
                DidChange = DidChange or Temp

                if (IsNew) then
                    _PathWasChanged(ValuePath, ExistingValue, nil, Key, ParentPath)
                elseif (DidChange) then
                    _PathWasChanged(ValuePath, ExistingValue, ExistingValue, Key, ParentPath)
                end

                continue
            end

            if (ExistingValueType == "table") then
                -- Replacing a table -> fire all sub-paths with nil
                PathTraverse(ExistingValue, ValuePath, function(NewPath, OldValue, Key, ParentPath)
                    _PathWasChanged(NewPath, nil, OldValue, Key, ParentPath)
                end)
            end

            -- Existing value is nil or not equal to new value -> put in new value
            Into[Key] = Value
            _PathWasChanged(ValuePath, Value, ExistingValue, Key, ParentPath)
            DidChange = true
        end

        return DidChange
    end

    --- Merges data into the existing structure.
    --- The core mechanism for changing the store.
    local function Merge(Data: GeneralStoreStructure)
        assert(type(Data) == "table", ERR_MERGE_ATOM_ATTEMPT)
        _Merge(EMPTY_STRING, Data, _Structure)
        _PathWasChanged(EMPTY_STRING, _Structure, _Structure, nil, nil)
    end
    self.Merge = Merge

    --- Sets down a path, constructing tables if none are present along the way.
    local function Set(Path: GeneralStorePath, Value: any?)
        assert(Path, ERR_NO_PATH_GIVEN)
        assert(#Path > 0, ERR_ROOT_OVERWRITE)

        if (type(Value) == "table" and Get(Path)) then
            -- Set using table -> remove previous value and overwrite (we don't want to merge 'set' tables in - unintuitive)
            Merge(BuildFromPath(Path, REMOVE_NODE))
        end

        Merge(BuildFromPath(Path, Value == nil and REMOVE_NODE or Value))
    end
    self.Set = Set

    --- Same as Set except merges with existing tables instead
    --- of overwriting them.
    local function SetMerge(Path: GeneralStorePath, Value: any?)
        assert(Path, ERR_NO_PATH_GIVEN)
        assert(#Path > 0, ERR_ROOT_OVERWRITE)
        Merge(BuildFromPath(Path, Value == nil and REMOVE_NODE or Value))
    end
    self.SetMerge = SetMerge

    --- Clears the whole store.
    local function Clear()
        for Key in assert(Get({})) do
            Merge({[Key] = REMOVE_NODE})
        end
    end
    self.Clear = Clear

    local SignalLock = {
        __index = function(self, Key)
            error("Signal was cleaned and locked as all connections were disconnected", 2)
        end;
    }

    --- Creates or obtains the event corresponding to a path's value changing.
    local function _GetValueChangedSignalFlat(AwaitingPath: string, SubValue: boolean?)
        assert(AwaitingPath, ERR_AWAIT_PATH_NOT_GIVEN)
        assert(type(AwaitingPath) == "string", ERR_AWAIT_PATH_NOT_STRING)

        local Event = _Awaiting[AwaitingPath]
        if (Event) then
            return Event
        end

        local Event = XSignal.new()
        _Awaiting[AwaitingPath] = Event

        --[[ do
            -- Posisble mode in future: registered by default, until connection count returns to 0.
            -- This way we don't necessarily maintain the signal reference until whole GeneralStore is GC'ed.

            local Count = 0
            local OriginalConnect = Event.Connect

            function Event:Connect(Callback)
                Count += 1

                local Connection = OriginalConnect(self, Callback)
                    local OriginalDisconnect = Connection.Disconnect

                function Connection:Disconnect()
                    OriginalDisconnect(self)
                    Count -= 1
                    if (Count == 0) then
                        _Awaiting[AwaitingPath] = nil
                    end

                    setmetatable(Event, SignalLock)
                    if (not table.isfrozen(Event)) then
                        table.freeze(Event)
                    end
                end
                
                return Connection
            end
        end ]]

        return Event
    end

    --- Creates or obtains the event corresponding to a path's value changing.
    local function GetValueChangedSignal(Path: GeneralStorePath): RBXScriptSignal
        return _GetValueChangedSignalFlat(GetPathString(Path))
    end
    self.GetValueChangedSignal = GetValueChangedSignal

    --- Creates or obtains the event corresponding to a path's sub key-value pairs changing.
    local function GetSubValueChangedSignal(Path: GeneralStorePath): RBXScriptSignal
        return _GetValueChangedSignalFlat(GetPathString(Path) .. "\255")
    end
    self.GetSubValueChangedSignal = GetSubValueChangedSignal

    -- Waits for a value down a path.
    local function Await(Path: GeneralStorePath, Timeout: number?): any
        local CorrectedTimeout = Timeout or DEFAULT_TIMEOUT
        local Got = Get(Path)

        -- ~= nil as it could be false.
        if (Got ~= nil) then
            return Got
        end

        local Trace = debug.traceback()

        -- Proxy for timeout OR the awaiting event, as we don't want to fire the awaiting event on timeout incase other coroutines are listening.
        local StringPath = GetPathString(Path or EMPTY_PATH)
        local ValueSignal = _GetValueChangedSignalFlat(StringPath)

        local Warning = task.delay(TIMEOUT_WARN, function()
            warn(WARN_INFINITE_WAIT:format(StringPath, Trace))
        end)

        local Result = ValueSignal:Wait(CorrectedTimeout)
        task.cancel(Warning)

        -- It timed out
        if (Result == nil) then
            error(ERR_STORE_TIMEOUT_REACHED:format(StringPath, CorrectedTimeout))
        end

        return Result
    end
    self.Await = Await

    --- Turns debug logging on or off (printing out all path value changes).
    local function SetDebugLog(DebugLog: boolean)
        _DebugLog = DebugLog
    end
    self.SetDebugLog = SetDebugLog

    --- Obtains or creates metadata for a path.
    --- Todo.
    --[[ local function GetMetadata(Path: GeneralStorePath): any
        Path = Path or EMPTY_PATH
        local PathString = GetPathString(Path)
        local Target = _Metadata[PathString]
        if (Target) then
            return Target
        end
        Target = {}
        _Metadata[PathString] = Target
        return Target
    end
    self.GetMetadata = GetMetadata ]]

    if (DefaultStructure) then
        Merge(DefaultStructure)
    end
    return self
end

--[[
    -- Example usage
    local Test = Store()
    Test.SetDebugLog(true)
    Test.GetValueChangedSignal({}):Connect(function(...) print("AHHHH", ...) end)
    Test.Merge({
        A = {
            B = {
                C = 5;
                D = 10;
            }
        }
    })

    print("---")

    Test.Merge({
        A = {
            B = {
                C = 10;
                D = REMOVE_NODE;
            }
        }
    })

    print("---")

    Test.Merge({
        A = {
            D = 2
        }
    })

    print("---")

    Test.Merge({
        A = REMOVE_NODE;
    })
]]

return table.freeze({
    _FlatPathDelimiter = FLAT_PATH_DELIMITER;
    _BuildFromPath = BuildFromPath;
    _GetPathString = GetPathString;
    _InternalMerge = InternalMerge;
    _PathTraverse = PathTraverse;
    _RemoveNode = REMOVE_NODE;

    new = Store;
})