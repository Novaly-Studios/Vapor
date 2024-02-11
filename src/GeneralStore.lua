--!nonstrict

-- Allows easy command bar paste.
if (not script) then
	script = game:GetService("ReplicatedFirst").Vapor.GeneralStore
end

local Cleaner = require(script.Parent.Parent:WaitForChild("Cleaner"))
local XSignal = require(script.Parent.Parent:WaitForChild("XSignal"))

-- More strings
local FLAT_PATH_DELIMITER = "^"
local EMPTY_STRING = ""

-- Types
export type StoreKey = string | number
export type RawStore = {[StoreKey]: any}
export type StorePath = {StoreKey}

local TYPE_STRING = "string"
local TYPE_TABLE = "table"

-- Logs, warnings & errors
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
local ERR_NO_EXISTING_AWAIT = NAME_PREFIX .. "No existing await event for: %s"
local ERR_NO_ITEMS_IN_PATH = NAME_PREFIX .. "No items in path (no ascendants derivable)"
local ERR_ROOT_OVERWRITE = NAME_PREFIX .. "Attempt to set root table (path empty)"
local ERR_NO_VALUE_GIVEN = NAME_PREFIX .. "No value given!"
local ERR_NO_PATH_GIVEN = NAME_PREFIX .. "No path given!"
local ERR_MIXED_KEYS = NAME_PREFIX .. "Attempted to insert using mixed keys!"

-- Don't change
local REMOVE_NODE = {REMOVE_NODE = true}
local EMPTY_PATH = {}

-- Settings
local DEFAULT_TIMEOUT = 120 -- Await timeout, prevents memory leaks
local TIMEOUT_WARN = 5 -- When to warn user in possible timeout case

-----------------------------------------------------------------------------------

-- Traverses each item in the table recursively, creating a path string for each
-- Not inclusive of root
local function PathTraverse(Root: RawStore, Path: string, Callback: (string, any, string, string) -> ())
    for Key, Value in Root do
        local NewPath = Path .. tostring(Key) .. FLAT_PATH_DELIMITER

        if (type(Value) == TYPE_TABLE) then
            PathTraverse(Value, NewPath, Callback)
        end

        Callback(NewPath, Value, Key, Path)
    end
end

local function GetPathString(Path: StorePath): string
    local Length = #Path
    local Result = EMPTY_STRING

    for Index = 1, Length do
        Result ..= tostring(Path[Index]) .. FLAT_PATH_DELIMITER
    end

    return Result
end

local function InternalMerge(Data, Into, BypassRemoveNode)
    for Key, Value in Data do
        if ((not BypassRemoveNode) and Value == REMOVE_NODE) then
            Into[Key] = nil
            continue
        end

        if (typeof(Value) == "table") then
            local Got = Into[Key]

            if (Got == nil) then
                Got = {}
                Into[Key] = Got
            end

            if (typeof(Got) ~= "table" and Value == REMOVE_NODE) then
                Into[Key] = REMOVE_NODE
                continue
            end

            InternalMerge(Value, Got, BypassRemoveNode)
            continue
        end

        Into[Key] = Value
    end
end

local function BuildFromPath(Path: StorePath, Value: any): RawStore
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

local Store = {}
Store.__index = Store
Store.Type = "Store"

function Store.new(DeferFunction, DefaultStructure: any?)
    local StoreStructure = {}; -- The data to be replicated

    local self = {
        _Store = StoreStructure;

        _Awaiting = setmetatable({}, {__mode = "k"}); -- Awaiting: {[PathString]: Signal}
        _DeferredEvents = {}; -- DeferredEvents: {[string]: Signal}

        _DebugLog = false;
        _Deferring = false;

        DeferFunction = DeferFunction;
    };

    local Object = setmetatable(self, Store)

    if (DefaultStructure) then
        -- Not possible to hook into changed events using this,
        -- since it occurs in construction
        Object:Merge(DefaultStructure)
    end

    return Object
end

function Store:Destroy()
    for _, Event in self._Awaiting do
        Event:Fire(nil) -- Release all awaiting
        Event:Destroy()
    end
end

--[[
    Obtains down a path, and does not error for nil values.
]]
function Store:Get(Path: StorePath, DefaultValue: any?): any?
    Path = Path or EMPTY_PATH

    local Result = self._Store

    for Index = 1, #Path do
        Result = Result[Path[Index]]

        if (Result == nil) then
            return DefaultValue
        end
    end

    return Result
end
Store.get = Store.Get

--[[
    Sets down a path; constructs tables if none are present along the way.
]]
function Store:Set(Path: StorePath, Value: any?)
    assert(Path, ERR_NO_PATH_GIVEN)
    assert(#Path > 0, ERR_ROOT_OVERWRITE)

    if (type(Value) == TYPE_TABLE and self:Get(Path)) then
        -- Set using table -> remove previous value and overwrite (we don't want to merge 'set' tables in - unintuitive)
        self:Merge(BuildFromPath(Path, REMOVE_NODE))
    end

    self:Merge(BuildFromPath(Path, Value == nil and REMOVE_NODE or Value))
end
Store.set = Store.Set

--[[
    Same as Set except merges with existing tables instead
    of overwriting them.
]]
function Store:SetMerge(Path: StorePath, Value: any?)
    assert(Path, ERR_NO_PATH_GIVEN)
    assert(#Path > 0, ERR_ROOT_OVERWRITE)

    self:Merge(BuildFromPath(Path, Value == nil and REMOVE_NODE or Value))
end
Store.setMerge = Store.SetMerge

--[[
    Merges a data structure into the existing structure.
    The core mechanism for changing the store.
]]
function Store:Merge(Data: RawStore)
    assert(type(Data) == TYPE_TABLE, ERR_MERGE_ATOM_ATTEMPT)

    local StoreData = self._Store
    self:_Merge(EMPTY_STRING, Data, StoreData)
    self:_PathWasChanged(EMPTY_STRING, StoreData, StoreData, nil, nil)
end
Store.merge = Store.Merge

--[[
    Clears the whole store.
]]
function Store:Clear()
    for Key in self:Get() do
        self:Merge({[Key] = REMOVE_NODE})
    end
end
Store.clear = Store.Clear

-- Waits for a value
function Store:Await(Path: StorePath, Timeout: number?): any
    local CorrectedTimeout = Timeout or DEFAULT_TIMEOUT
    local Got = self:Get(Path)

    -- ~= nil as it could be false
    if (Got ~= nil) then
        return Got
    end

    local Trace = debug.traceback()

    -- Proxy for timeout OR the awaiting event, as we don't want to fire the awaiting event on timeout incase other coroutines are listening
    local StringPath = GetPathString(Path or EMPTY_PATH)
    local ValueSignal = self:_GetValueChangedSignalFlat(StringPath)

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
Store.await = Store.Await

-- _GetValueChangedSignalFlat except takes a StorePath
function Store:GetValueChangedSignal(Path: StorePath): RBXScriptSignal
    return self:_GetValueChangedSignalFlat(GetPathString(Path))
end
Store.getValueChangedSignal = Store.GetValueChangedSignal

function Store:GetSubValueChangedSignal(Path: StorePath): RBXScriptSignal
    return self:_GetValueChangedSignalFlat(GetPathString(Path) .. "\255")
end

--[[
    Defers value changed events for paths to the next
    defer point. Useful for not rapidly updating non
    leaf nodes for many changes on those leaf nodes
    before a conceptual defer point (like beginning of
    Heartbeat). E.g. updating a Store 10 times in a frame
    and using a frame-long wait as defer point would only
    fire the root event once. Useful for UI performance or
    general state update hook performance.
]]
function Store:_DeferEventFlat(PathString: string, New: any?, Old: any?, Key: string, ParentPathName: string?)
    local Awaiting = self._Awaiting

    if (not Awaiting[PathString]) then
        return
    end

    local DeferredEvents = self._DeferredEvents -- TODO: order it
    DeferredEvents[PathString] = {New, Old, Key, ParentPathName}

    if (not self._Deferring) then
        self._Deferring = true

        self.DeferFunction(function()
            if (table.isfrozen(self)) then
                return
            end

            self._DeferredEvents = {}
            self._Deferring = false

            for PathName, Change in DeferredEvents do
                local Event = Awaiting[PathName]

                if (Event) then
                    local Value, Old = Change[1], Change[2]
                    Event:Fire(Value, Old, Value == Old)
                end

                local ParentPathName = Change[4]

                if (ParentPathName) then
                    local ParentEvent = Awaiting[ParentPathName .. "\255"]
        
                    if (ParentEvent) then
                        ParentEvent:Fire(Change[3], Change[1], Change[2])
                    end
                end
            end
        end)
    end
end

-- Creates or obtains the event corresponding to a path's value changing
function Store:_GetValueChangedSignalFlat(AwaitingPath: string, SubValue: boolean?)
    assert(AwaitingPath, ERR_AWAIT_PATH_NOT_GIVEN)
    assert(type(AwaitingPath) == TYPE_STRING, ERR_AWAIT_PATH_NOT_STRING)

    -- TODO: move these into Connect?
    local Awaiting = self._Awaiting
        local Event = Awaiting[AwaitingPath]

    if (Event) then
        return Event
    end

    Event = XSignal.new()
    Awaiting[AwaitingPath] = Event
    return Event
end

-- Fires a signal when an atom or table was changed in a merge
function Store:_PathWasChanged(PathName: string, Value: any?, Old: any?, Key: string, ParentPathName: string?)
    if (self.DeferFunction) then
        self:_DeferEventFlat(PathName, Value, Old, Key, ParentPathName)
    else
        local Awaiting = self._Awaiting
            local Event = Awaiting[PathName]

        if (Event) then
            Event:Fire(Value, Old, Value == Old)
        end

        if (ParentPathName) then
            local ParentEvent = Awaiting[ParentPathName .. "\255"]

            if (ParentEvent) then
                ParentEvent:Fire(Key, Value, Old)
            end
        end
    end

    if (self._DebugLog) then
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

-- Separate merge procedure since recursion is necessary and params would be inconvenient to the user
function Store:_Merge(ParentPath, Data, Into)
    local ExistingKey = next(Into)
    local LastType

    if (ExistingKey) then
        LastType = type(ExistingKey)
    end

    for Key, Value in Data do
        local ValuePath = ParentPath .. tostring(Key) .. FLAT_PATH_DELIMITER
        local ExistingValue = Into[Key]

        local KeyType = typeof(Key)
        local ExistingValueType = type(ExistingValue)

        if (not LastType) then
            LastType = KeyType
        end

        -- Mixed key types bad bad bad bad bad
        assert(KeyType == LastType, ERR_MIXED_KEYS)

        if (Value == ExistingValue) then
            -- No change, so no need to fire off any events (which would otherwise happen)
            continue
        end

        if (Value == REMOVE_NODE) then
            -- REMOVE_NODE is used in place of 'nil' in tables (since obviously
            -- nil-ed values won't exist, so this acts as a signifier to remove)

            if (ExistingValue == nil) then
                continue
            end

            if (ExistingValueType == TYPE_TABLE) then
                -- "Remove table" -> all awaiting events on sub-paths should be fired
                Into[Key] = nil

                PathTraverse(ExistingValue, ValuePath, function(NewPath, OldValue, Key, ParentPath)
                    self:_PathWasChanged(NewPath, nil, OldValue, Key, ParentPath)
                end)

                self:_PathWasChanged(ValuePath, nil, ExistingValue, Key, ParentPath)
                continue
            end

            -- "Remove atom" -> nullify, then signify path was changed to nil
            Into[Key] = nil
            self:_PathWasChanged(ValuePath, nil, ExistingValue, Key, ParentPath)
            continue
        end

        if (type(Value) == TYPE_TABLE) then
            -- Item is a sub-table -> recurse and then activate changed event (up-propagated)
            local IsNew = (ExistingValue == nil)

            if (IsNew) then
                ExistingValue = {}
                Into[Key] = ExistingValue
            end

            self:_Merge(ValuePath, Value, ExistingValue)

            if (IsNew) then
                self:_PathWasChanged(ValuePath, ExistingValue, nil, Key, ParentPath)
            else
                self:_PathWasChanged(ValuePath, ExistingValue, ExistingValue, Key, ParentPath)
            end

            continue
        end

        if (ExistingValueType == TYPE_TABLE) then
            -- Replacing a table -> fire all sub-paths with nil
            PathTraverse(ExistingValue, ValuePath, function(NewPath, OldValue, Key, ParentPath)
                self:_PathWasChanged(NewPath, nil, OldValue, Key, ParentPath)
            end)
        end

        -- Existing value is nil or not equal to new value -> put in new value
        Into[Key] = Value
        self:_PathWasChanged(ValuePath, Value, ExistingValue, Key, ParentPath)
    end
end

-- Turns debug logging on or off
function Store:SetDebugLog(DebugLog: boolean)
    self._DebugLog = DebugLog
end

Store._REMOVE_NODE = REMOVE_NODE
Store._PathTraverse = PathTraverse
Store._InternalMerge = InternalMerge
Store._GetPathString = GetPathString
Store._BuildFromPath = BuildFromPath

-- For testing
    function Store:_GetAwaitingCount(Path: StorePath): number
        return self._AwaitingRefs[GetPathString(Path)]
    end

    function Store:_RawGetValueChangedSignal(Path: StorePath): RBXScriptSignal
        return self._Awaiting[GetPathString(Path)]
    end
--

Cleaner.Wrap(Store)

export type Store = typeof(Store)

--[[
    -- Example usage

    local Test = Store.new()
    Test:SetDebugLog(true)
    Test:Merge({
        A = {
            B = {
                C = 5;
                D = 10;
            }
        }
    })

    print("---")

    Test:Merge({
        A = {
            B = {
                C = 10;
                D = REMOVE_NODE;
            }
        }
    })

    print("---")

    Test:Merge({
        A = {
            D = 2
        }
    })

    print("---")

    Test:Merge({
        A = REMOVE_NODE;
    })
]]

return Store