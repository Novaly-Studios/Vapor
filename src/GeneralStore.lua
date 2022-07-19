local script = script

-- Allows easy command bar paste
if (not script) then
    script = game:GetService("ReplicatedFirst").Vapor.GeneralStore
end

local TypeGuard = require(script.Parent.Parent:WaitForChild("TypeGuard"))
local Cleaner = require(script.Parent.Parent:WaitForChild("Cleaner"))
local XSignal = require(script.Parent.Parent:WaitForChild("XSignal"))

local Shared = require(script.Parent:WaitForChild("Shared"))

type StoreKey = Shared.StoreKey
type StorePath = Shared.StorePath

local ValidStorePath = Shared.ValidStorePath
local GetPathString = Shared.GetPathString
local BuildFromPath = Shared.BuildFromPath
local PathTraverse = Shared.PathTraverse
local RemoveNode = Shared.RemoveNode

local WEAK_KEY_MT = {__mode = "k"}

local FLAT_PATH_DELIMITER = Shared.FlatPathDelimiter
local EMPTY_PATH_ARRAY = {}
local EMPTY_STRING = ""

-- Types
local TYPE_NUMBER = "number"
local TYPE_TABLE = "table"

-- Logs, warnings & errors
local NAME_PREFIX = "[GeneralStore] "

local WARN_INFINITE_WAIT = NAME_PREFIX .. "Potentially infinite wait on '%s'.\n%s"
local LOG_CHANGE = NAME_PREFIX .. "Change %s = %s"

local ERR_STORE_TIMEOUT_REACHED = NAME_PREFIX .. "Store timeout reached on path: %s (%ds)"
local ERR_MIXED_VALUES = NAME_PREFIX .. "Attempted to insert using mixed values with value homogeneity enabled"
local ERR_MIXED_KEYS = NAME_PREFIX .. "Attempted to insert using mixed keys with key homogeneity enabled"

-- Settings
local VALIDATE_PARAMS = true -- Check the types for various functions? (Worse performance but better debugging if true)
local DEFAULT_TIMEOUT = 120 -- Await timeout, prevents memory leaks
local TIMEOUT_WARN = 10 -- When to warn user in possible timeout case

-----------------------------------------------------------------------------------

-- @todo GeneralStore.Move(PathA, PathB)
-- @todo GeneralStore.Swap(PathA, PathB)
-- @todo GeneralStore.MergeUsingPathArray(PathArray, Value)
-- @todo GeneralStore.ClearUsingPathString(PathString)

--- A store which wraps a normal Lua table, allowing for changed signals,
--- child-parent associations, and more. Note: all mutation of the store
--- MUST be achieved through GeneralStore methods, or it will become
--- desynced.
local GeneralStore = {}
GeneralStore.__index = GeneralStore
GeneralStore.Type = "GeneralStore"

local ConstructorParams = TypeGuard.Params(TypeGuard.Function():Optional(), TypeGuard.Object():Optional())
--- Creates a new GeneralStore object.
function GeneralStore.new(DeferFunction, DefaultStructure: any?)
    ConstructorParams(DeferFunction, DefaultStructure)

    local StoreStructure = {}
    local FlatRefs = {[EMPTY_STRING] = StoreStructure}

    local self = {
        _Store = StoreStructure; -- The main table root
        _Awaiting = setmetatable({}, WEAK_KEY_MT); -- For association of path strings to XSignals which fire for changes on that respective path
        _NodeToPath = setmetatable({}, WEAK_KEY_MT); -- For associations of nodes to their path strings
        _PathToValue = FlatRefs; -- For O(1) access on known paths using their strings
        _PathToParentPath = {}; -- For associations of child nodes to their parent node

        _Deferring = false;
        _DeferFunction = DeferFunction;
        _DeferredEvents = {}; -- Caches the latest data on changed events and fires at a defer point

        _DebugLog = false; -- Log any changes to output
        _EnforceHomogeneousKeys = true; -- For all keys in a node, they must be the same type
        _EnforceHomogeneousAtoms = true; -- For all non-table values in a node, they must be the same type
    };

    local Object = setmetatable(self, GeneralStore)

    if (DefaultStructure) then
        -- Not possible to hook into changed events using this, since it occurs in construction
        Object:Merge(DefaultStructure)
    end

    return Object
end

local SetHomogeneousKeysEnforcedParams = TypeGuard.Params(TypeGuard.Boolean())
--- Enabled homogeneous key checking (two keys in a node cannot differ in type).
function GeneralStore:SetHomogeneousKeysEnforced(Enabled: boolean)
    SetHomogeneousKeysEnforcedParams(Enabled)
    self._EnforceHomogeneousKeys = Enabled
end

local SetHomogeneousValuesEnforcementParams = TypeGuard.Params(TypeGuard.Boolean())
--- Enabled homogeneous value checking (two different value types cannot co-exist in a node, except for tables).
function GeneralStore:SetHomogeneousValuesEnforcement(Enabled: boolean)
    SetHomogeneousValuesEnforcementParams(Enabled)
    self._EnforceHomogeneousValues = Enabled
end

--- Clears the whole store, releasing all the awaiting events.
function GeneralStore:Destroy()
    self:ClearUsingPathArray(EMPTY_PATH_ARRAY)
end

local ClearUsingPathArrayParams = TypeGuard.Params(ValidStorePath)
--- Clears a node from the store at a path.
function GeneralStore:ClearUsingPathArray(Path: StorePath?)
    Path = Path or EMPTY_PATH_ARRAY

    if (VALIDATE_PARAMS) then
        ClearUsingPathArrayParams(Path)
    end

    local ValuePath = GetPathString(Path)
    local Value = self:GetUsingPathString(ValuePath)
    assert(typeof(Value) == TYPE_TABLE, "Path was not a node: " .. tostring(ValuePath))

    local FinalMerge = BuildFromPath(Path, {})

    for Key in Value do
        FinalMerge[Key] = RemoveNode
    end

    self:Merge(FinalMerge)
end
GeneralStore.clearUsingPathArray = GeneralStore.ClearUsingPathArray

local GetUsingPathStringParams = TypeGuard.Params(TypeGuard.String():Optional())
--- Finds a value from the store corresponding to the given path defined by a string.
function GeneralStore:GetUsingPathString(PathString: string?, DefaultValue: any?): any?
    PathString = PathString or EMPTY_STRING

    if (VALIDATE_PARAMS) then
        GetUsingPathStringParams(PathString)
    end

    local Found = self._PathToValue[PathString]

    if (Found == nil) then
        Found = DefaultValue
    end

    return Found
end
GeneralStore.GetUsingPathString = GeneralStore.GetUsingPathString

local GetUsingPathArrayParams = TypeGuard.Params(ValidStorePath:Optional())
--- Finds a value from the store corresponding to the given path defined by an array.
function GeneralStore:GetUsingPathArray(Path: StorePath?, DefaultValue: any?): any?
    Path = Path or EMPTY_PATH_ARRAY

    if (VALIDATE_PARAMS) then
        GetUsingPathArrayParams(Path)
    end

    return self:GetUsingPathString(GetPathString(Path), DefaultValue)
end
GeneralStore.getUsingPathArray = GeneralStore.GetUsingPathArray

local SetUsingPathArrayParams = TypeGuard.Params(ValidStorePath:Optional())
--- Sets down a path; constructs tables if none are present along the way.
function GeneralStore:SetUsingPathArray(Path: StorePath, Value: any?, DoMerge: boolean?)
    Path = Path or EMPTY_PATH_ARRAY

    if (VALIDATE_PARAMS) then
        SetUsingPathArrayParams(Path)
    end

    -- Set on root path -> error
    -- TODO: calling set on the root path and passing a table as the value should clear the store & set the new values
    local ExistingValue = self:GetUsingPathString(GetPathString(Path))
    assert(ExistingValue ~= self._Store, "Cannot overwrite root table")

    -- Set using table -> remove previous value and overwrite (we don't want to merge 'set' tables in - unintuitive)
    if (type(Value) == TYPE_TABLE and ExistingValue and not DoMerge) then
        self:Merge(BuildFromPath(Path, RemoveNode))
    end

    self:Merge(BuildFromPath(Path, Value == nil and RemoveNode or Value))
end
GeneralStore.setUsingPathArray = GeneralStore.SetUsingPathArray

local AwaitUsingPathArrayParams = TypeGuard.Params(ValidStorePath, TypeGuard.Number():Optional(), TypeGuard.Boolean():Optional())
--- Waits until a value is not nil at the given path defined by an array. The default timeout is 120 seconds.
function GeneralStore:AwaitUsingPathArray(Path: StorePath?, Timeout: number?, BypassError: boolean?): any?
    Path = Path or EMPTY_PATH_ARRAY

    if (VALIDATE_PARAMS) then
        AwaitUsingPathArrayParams(Path, Timeout, BypassError)
    end

    return self:AwaitUsingPathString(GetPathString(Path), Timeout, BypassError)
end
GeneralStore.awaitUsingPathArray = GeneralStore.AwaitUsingPathArray

local AwaitUsingPathStringParams = TypeGuard.Params(TypeGuard.String(), TypeGuard.Number():Optional(), TypeGuard.Boolean():Optional())
--- Waits until a value is not nil at the given path defined by a string. The default timeout is 120 seconds.
function GeneralStore:AwaitUsingPathString(PathString: string, Timeout: number?, BypassError: boolean?)
    if (VALIDATE_PARAMS) then
        AwaitUsingPathStringParams(PathString, Timeout, BypassError)
    end

    local CorrectedTimeout = Timeout or DEFAULT_TIMEOUT
    local Got = self:GetUsingPathString(PathString)

    -- ~= nil as it could be false
    if (Got ~= nil) then
        return Got
    end

    -- Timeout warning
    local TimeoutCoroutine = task.delay(TIMEOUT_WARN, function()
        warn(WARN_INFINITE_WAIT:format(PathString, debug.traceback()))
    end)

    local Result = self:GetValueChangedSignalUsingPathString(PathString):Wait(CorrectedTimeout, false)
    task.cancel(TimeoutCoroutine)

    if (Result == nil and not BypassError) then
        error(ERR_STORE_TIMEOUT_REACHED:format(PathString, CorrectedTimeout))
    end

    return Result
end
GeneralStore.awaitUsingPathString = GeneralStore.AwaitUsingPathString

local GetValueChangedSignalUsingPathArrayParams = TypeGuard.Params(ValidStorePath:Optional())
-- Finds or creates a Signal which fires whenever the value at the given path defined by an array changes or is up-propagated.
function GeneralStore:GetValueChangedSignalUsingPathArray(Path: StorePath?): typeof(XSignal)
    Path = Path or EMPTY_PATH_ARRAY

    if (VALIDATE_PARAMS) then
        GetValueChangedSignalUsingPathArrayParams(Path)
    end

    return self:GetValueChangedSignalUsingPathString(GetPathString(Path))
end
GeneralStore.getValueChangedSignalUsingPathArray = GeneralStore.GetValueChangedSignalUsingPathArray
GeneralStore.GetValueChangedSignal = GeneralStore.GetValueChangedSignalUsingPathArray
GeneralStore.getValueChangedSignal = GeneralStore.GetValueChangedSignalUsingPathArray

local GetValueChangedSignalUsingPathStringParams = TypeGuard.Params(TypeGuard.String():Optional())
-- Finds or creates a Signal which fires whenever the value at the given path defined by a string changes or is up-propagated.
function GeneralStore:GetValueChangedSignalUsingPathString(Path: string?): typeof(XSignal)
    Path = Path or EMPTY_STRING

    if (VALIDATE_PARAMS) then
        GetValueChangedSignalUsingPathStringParams(Path)
    end

    local Awaiting = self._Awaiting
    local Found = Awaiting[Path]

    if (Found) then
        return Found
    end

    Found = XSignal.new()
    Awaiting[Path] = Found
    return Found
end
GeneralStore.getValueChangedSignalUsingPathString = GeneralStore.GetValueChangedSignalUsingPathString

local SetMergeUsingPathArrayParams = TypeGuard.Params(ValidStorePath)
--- Merges a value into the store at the given path defined by an array. This will not overwrite existing tables, but will merge into them instead.
function GeneralStore:SetMergeUsingPathArray(Path: StorePath, Value: any?)
    if (VALIDATE_PARAMS) then
        SetMergeUsingPathArrayParams(Path)
    end

    self:Merge(BuildFromPath(Path, Value == nil and RemoveNode or Value))
end
GeneralStore.setMergeUsingPathArray = GeneralStore.SetMergeUsingPathArray

local MergeParams = TypeGuard.Params(TypeGuard.Object():Or(TypeGuard.Array()))
--- Merges a data structure into the existing store's structure.
function GeneralStore:Merge(Data: any)
    if (VALIDATE_PARAMS) then
        MergeParams(Data)
    end

    local StoreData = self._Store
    self:_Merge(EMPTY_STRING, Data, StoreData)
    self:_PathWasChanged(EMPTY_STRING, StoreData)
end
GeneralStore.merge = GeneralStore.Merge

--- Defers value changed events for paths to the next
--- defer point. Useful for not rapidly updating non
--- leaf nodes for many changes on those leaf nodes
--- before a conceptual defer point (like beginning of
--- Heartbeat). Will only fire once with the latest value.
function GeneralStore:_DeferEventFlat(PathString: string, New: any?)
    local Awaiting = self._Awaiting

    if (not Awaiting[PathString]) then
        return
    end

    local DeferredEvents = self._DeferredEvents -- TODO: we might want to fire these in order
    DeferredEvents[PathString] = New

    if (not self._Deferring) then
        self._Deferring = true

        self._DeferFunction(function()
            if (table.isfrozen(self)) then
                return
            end

            for PathName, Change in DeferredEvents do
                local Event = Awaiting[PathName]

                if (Event) then
                    Event:Fire(Change)
                end
            end

            self._DeferredEvents = {}
            self._Deferring = false
        end)
    end
end

-- Fires a signal when an atom or table was changed in a merge.
function GeneralStore:_PathWasChanged(PathName: string, Value: any?, ParentPath: string)
    self._PathToValue[PathName] = Value -- This has to be set first so coroutines resumed after see the correct state, otherwise weird issues with consecutive Awaits

    if (Value == nil) then
        self._PathToParentPath[PathName] = nil
    elseif (PathName ~= EMPTY_STRING) then
        self._PathToParentPath[PathName] = ParentPath
    end

    if (typeof(Value) == TYPE_TABLE) then
        self._NodeToPath[Value] = PathName
    end

    if (self._DeferFunction) then
        self:_DeferEventFlat(PathName, Value)
    else
        local Event = self._Awaiting[PathName]

        if (Event) then
            Event:Fire(Value)
        end
    end

    if (self._DebugLog) then
        print(LOG_CHANGE:format(PathName == EMPTY_STRING and "ROOT" or PathName, tostring(Value)))
    end
end

-- Separate merge procedure since recursion is necessary and params would be inconvenient to the user.
function GeneralStore:_Merge(ParentPath, Data, Into)
    local LastKeyType, LastValueType
    local EnforceHomogeneousKeys = self._EnforceHomogeneousKeys
    local EnforceHomogeneousValues = self._EnforceHomogeneousValues

    if (EnforceHomogeneousKeys) then
        local ExistingKey = next(Into)

        if (ExistingKey) then
            LastKeyType = typeof(ExistingKey)
        end
    end

    if (EnforceHomogeneousValues) then
        for _, Value in Data do
            local ValueType = typeof(Value)

            if (ValueType == TYPE_TABLE) then
                continue
            end

            LastValueType = ValueType
            break
        end
    end

    for Key, Value in Data do
        local ValuePath = ParentPath .. tostring(Key) .. FLAT_PATH_DELIMITER
        local ExistingValue = Into[Key]
        local ExistingValueType = typeof(ExistingValue)

        -- Only one key type can exist in a node
        if (EnforceHomogeneousKeys) then
            local KeyType = typeof(Key)

            if (not LastKeyType) then
                LastKeyType = KeyType
            end

            -- Mixed key types bad bad bad bad bad
            assert(KeyType == LastKeyType, ERR_MIXED_KEYS)
        end

        -- Only one value type can co-exist with table value types in a node
        if (EnforceHomogeneousValues and LastValueType) then
            assert(ExistingValueType == TYPE_TABLE or ExistingValueType == LastValueType, ERR_MIXED_VALUES)
        end

        -- No change, so no need to fire off any events (which would otherwise happen)
        if (Value == ExistingValue) then
            continue
        end

        -- REMOVE_NODE is used in place of 'nil' in tables (since obviously
        -- nil-ed values won't exist, so this acts as a signifier to remove)
        if (Value == RemoveNode) then
            if (ExistingValue == nil) then
                continue
            end

            -- "Remove table" -> all awaiting events on sub-paths should be fired
            if (ExistingValueType == TYPE_TABLE) then
                Into[Key] = nil

                PathTraverse(ExistingValue, ValuePath, function(NewPath, _, NewPathParent)
                    self:_PathWasChanged(NewPath, nil, NewPathParent)
                end)

                self:_PathWasChanged(ValuePath, nil, ParentPath)
                continue
            end

            -- "Remove atom" -> nullify, then signify path was changed to nil
            Into[Key] = nil
            self:_PathWasChanged(ValuePath, nil, ParentPath)
            continue
        end

        -- Item is a sub-table -> recurse and then activate changed event (up-propagated)
        if (typeof(Value) == TYPE_TABLE) then
            if (ExistingValue == nil) then
                ExistingValue = {}
                Into[Key] = ExistingValue
            end

            self:_Merge(ValuePath, Value, ExistingValue)
            self:_PathWasChanged(ValuePath, ExistingValue, ParentPath)
            continue
        end

        -- Replacing a table -> fire all sub-paths with nil
        if (ExistingValueType == TYPE_TABLE) then
            PathTraverse(ExistingValue, ValuePath, function(NewPath, _, NewPathParent)
                self:_PathWasChanged(NewPath, nil, NewPathParent)
            end)
        end

        -- Existing value is nil or not equal to new value -> put in new value
        Into[Key] = Value
        self:_PathWasChanged(ValuePath, Value, ParentPath)
    end
end

local ArrayInsertUsingPathArrayParams = TypeGuard.Params(ValidStorePath, TypeGuard.Any(), TypeGuard.Number():Optional())
--- Inserts a value into an array node with an optional index.
function GeneralStore:ArrayInsertUsingPathArray(Path: StorePath, Value: any, At: number?): number
    if (VALIDATE_PARAMS) then
        ArrayInsertUsingPathArrayParams(Path, Value, At)
    end

    return self:ArrayInsertUsingPathString(GetPathString(Path), Value, At)
end
GeneralStore.arrayInsertUsingPathArray = GeneralStore.ArrayInsertUsingPathArray

local ArrayInsertUsingPathStringParams = TypeGuard.Params(TypeGuard.String(), TypeGuard.Any(), TypeGuard.Number():Optional())
--- Inserts a value into an array node with an optional index given a specifc path string to an array.
function GeneralStore:ArrayInsertUsingPathString(PathString: string, Value: any, At: number?): number
    if (VALIDATE_PARAMS) then
        ArrayInsertUsingPathStringParams(PathString, Value, At)
    end

    local Found = self:GetUsingPathString(PathString)

    local First = next(Found)
    assert(First == nil or typeof(First) == TYPE_NUMBER, "Cannot insert into non-array")

    At = At or #Found + 1
    table.insert(Found, At, Value)

    for Index = #Found, At, -1 do
        local ChangedPathString = PathString .. tostring(Index) .. FLAT_PATH_DELIMITER
        local NewValue = Found[Index]

        self:_PathWasChanged(ChangedPathString, NewValue, PathString)

        if (typeof(NewValue) == TYPE_TABLE) then
            PathTraverse(NewValue, ChangedPathString, function(NewPath, SubValue, NewPathParent)
                self:_PathWasChanged(NewPath, SubValue, NewPathParent)
            end)
        end
    end

    self:_UpPropagate(PathString)

    return At
end
GeneralStore.arrayInsertUsingPathString = GeneralStore.ArrayInsertUsingPathString

local ArrayRemoveUsingPathArrayParams = TypeGuard.Params(ValidStorePath, TypeGuard.Number():Optional())
--- Removes an element from an array node with an optional specific index.
function GeneralStore:ArrayRemoveUsingPathArray(Path: StorePath, At: number?): (any?, number)
    if (VALIDATE_PARAMS) then
        ArrayRemoveUsingPathArrayParams(Path, At)
    end

    return self:ArrayRemoveUsingPathString(GetPathString(Path), At)
end
GeneralStore.arrayRemoveUsingPathArray = GeneralStore.ArrayRemoveUsingPathArray

local ArrayRemoveUsingPathStringParams = TypeGuard.Params(TypeGuard.String(), TypeGuard.Number():Optional())
--- Removes an element from an array node with an optional specific index given a specifc path string to an array.
function GeneralStore:ArrayRemoveUsingPathString(PathString: string, At: number?): (any?, number)
    if (VALIDATE_PARAMS) then
        ArrayRemoveUsingPathStringParams(PathString, At)
    end

    local Found = self:GetUsingPathString(PathString)

    local First = next(Found)
    assert(First == nil or typeof(First) == TYPE_NUMBER, "Cannot insert into non-array")

    local OriginalSize = #Found

    if (OriginalSize == 0) then
        return nil, 0
    end

    At = At or OriginalSize

    local RemovingValue = Found[At]
    local RemovingPath = PathString .. tostring(At) .. FLAT_PATH_DELIMITER

    if (typeof(RemovingValue) == TYPE_TABLE) then
        PathTraverse(RemovingValue, RemovingPath, function(NewPath, _, NewPathParent)
            self:_PathWasChanged(NewPath, nil, NewPathParent)
        end)
    end

    table.remove(Found, At)

    for Index = OriginalSize, At, -1 do
        local ChangedPathString = PathString .. tostring(Index) .. FLAT_PATH_DELIMITER
        local NewValue = Found[Index]

        self:_PathWasChanged(ChangedPathString, NewValue, PathString)

        if (typeof(NewValue) == TYPE_TABLE) then
            PathTraverse(NewValue, ChangedPathString, function(NewPath, SubValue, NewPathParent)
                self:_PathWasChanged(NewPath, SubValue, NewPathParent)
            end)
        end
    end

    self:_UpPropagate(PathString)

    return RemovingValue, At
end
GeneralStore.arrayRemoveUsingPathString = GeneralStore.ArrayRemoveUsingPathString

local IncrementUsingPathArrayParams = TypeGuard.Params(ValidStorePath, TypeGuard.Number():Optional(), TypeGuard.Number():Optional())
--- Increments a numerical value at a given path.
function GeneralStore:IncrementUsingPathArray(Path: StorePath, By: number?, Default: number?): number
    if (VALIDATE_PARAMS) then
        IncrementUsingPathArrayParams(Path, By, Default)
    end

    By = By or 1

    local RootPath = GetPathString(Path)
    local Found = self:GetUsingPathString(RootPath)

    if (Found == nil) then
        if (Default == nil) then
            error("Found no parent for path: " .. RootPath)
        end

        Found = Default
    end

    local Result = Found + By
    local FoundType = typeof(Found)

    if (FoundType ~= TYPE_NUMBER) then
        error(("Cannot increment non-number at path '%s' (got %s)"):format(RootPath, FoundType))
    end

    self:SetUsingPathArray(Path, Result)
    return Result
end
GeneralStore.incrementUsingPathArray = GeneralStore.IncrementUsingPathArray

local GetPathFromNodeParams = TypeGuard.Params(TypeGuard.Object())
--- Returns the path string of a given node - works for nodes but not atoms.
function GeneralStore:GetPathFromNode(Node: any): string?
    if (VALIDATE_PARAMS) then
        GetPathFromNodeParams(Node)
    end

    return self._NodeToPath[Node]
end

local GetParentPathFromPathStringParams = TypeGuard.Params(TypeGuard.String())
--- Attempts to find the parent of a given path - works for nodes & atoms.
function GeneralStore:GetParentPathFromPathString(Path: string): any?
    if (VALIDATE_PARAMS) then
        GetParentPathFromPathStringParams(Path)
    end

    return self._PathToParentPath[Path]
end

local GetParentFromNodeParams = TypeGuard.Params(TypeGuard.Object())
--- Attempts to find the parent of a given node - works for nodes but not atoms.
function GeneralStore:GetParentFromNode(Node: any): any?
    if (VALIDATE_PARAMS) then
        GetParentFromNodeParams(Node)
    end

    local NodePath = self:GetPathFromNode(Node)

    if (not NodePath) then
        return nil
    end

    local NodeParentPath = self:GetParentPathFromPathString(NodePath)

    if (not NodeParentPath) then
        return nil
    end

    return self:GetUsingPathString(NodeParentPath)
end
GeneralStore.getParentFromNode = GeneralStore.GetParentFromNode

local IsNodeAncestorOfParams = TypeGuard.Params(TypeGuard.Object(), TypeGuard.Object())
--- Checks if node A is an ancestor of node B.
function GeneralStore:IsNodeAncestorOf(A: any, B: any): boolean
    if (VALIDATE_PARAMS) then
        IsNodeAncestorOfParams(A, B)
    end

    local Parent = self:GetParentFromNode(B)

    while (Parent) do
        if (Parent == A) then
            return true
        end

        Parent = self:GetParentFromNode(Parent)
    end

    return false
end
GeneralStore.isNodeAncestorOf = GeneralStore.IsNodeAncestorOf

--- Checks if node A is a descendant of node B.
function GeneralStore:IsNodeDescendantOf(A: any, B: any): boolean
    return self:IsNodeAncestorOf(B, A)
end
GeneralStore.isNodeDescendantOf = GeneralStore.IsNodeDescendantOf

local IsPathStringAncestorOfPathParamsString = TypeGuard.Params(TypeGuard.String(), TypeGuard.String())
--- Checks if path A is an ancestor of path B.
function GeneralStore:IsPathStringAncestorOfPathString(A: string, B: string): boolean
    if (VALIDATE_PARAMS) then
        IsPathStringAncestorOfPathParamsString(A, B)
    end

    local Parent = self:GetParentPathFromPathString(B)

    while (Parent) do
        if (Parent == A) then
            return true
        end

        Parent = self:GetParentPathFromPathString(Parent)
    end

    return false
end
GeneralStore.isPathStringAncestorOfPathString = GeneralStore.IsPathStringAncestorOfPathString

--- Checks if path A is a descendant of path B.
function GeneralStore:IsPathStringDescendantOfPathString(A: string, B: string): boolean
    return self:IsPathStringAncestorOfPathString(B, A)
end
GeneralStore.isPathStringDescendantOfPathString = GeneralStore.IsPathStringDescendantOfPathString

--- Fires changed connections for all ascendant nodes of a given path.
function GeneralStore:_UpPropagate(FromPath: string)
    local Path = FromPath

    while (Path) do
        local ParentPath = self:GetParentPathFromPathString(Path)
        self:_PathWasChanged(Path, self:GetUsingPathString(Path), ParentPath)
        Path = ParentPath
    end
end

local DebugLogParams = TypeGuard.Params(TypeGuard.Boolean())
-- Turns debug logging on or off, i.e. when DebugLog is on, it will log any data changes to the console.
function GeneralStore:SetDebugLog(DebugLog: boolean)
    if (VALIDATE_PARAMS) then
        DebugLogParams(DebugLog)
    end

    self._DebugLog = DebugLog
end
GeneralStore.setDebugLog = GeneralStore.SetDebugLog

Cleaner.Wrap(GeneralStore)

return GeneralStore