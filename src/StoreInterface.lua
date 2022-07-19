local TypeGuard = require(script.Parent.Parent:WaitForChild("TypeGuard"))
local Cleaner = require(script.Parent.Parent:WaitForChild("Cleaner"))
local XSignal = require(script.Parent.Parent:WaitForChild("XSignal"))
    type Signal<T> = XSignal.XSignal<T>

local Shared = require(script.Parent:WaitForChild("Shared"))
    local RemoveNode = Shared.RemoveNode
    local BuildFromPath = Shared.BuildFromPath
    type StorePath = Shared.StorePath
local TableUtil = require(script.Parent.Parent:WaitForChild("TableUtil"))
    local Merge1D = TableUtil.Array.Merge1D

local ReplicatedStore = require(script.Parent:WaitForChild("ReplicatedStore"))
local GeneralStore = require(script.Parent:WaitForChild("GeneralStore"))

local VALIDATE_PARAMS = true
local TYPE_TABLE = "table"

local ValidStorePath = Shared.ValidStorePath
local GetPathString = Shared.GetPathString

local StoreInterface = {}
StoreInterface.__index = StoreInterface

local ConstructorParams = TypeGuard.Params(TypeGuard.Object():OfClass(ReplicatedStore):Or(TypeGuard.Object():OfClass(GeneralStore)):FailMessage("Arg #1 supplied must be a ReplicatedStore or a GeneralStore"), ValidStorePath:Optional())
--- Creates a new StoreInterface object.
function StoreInterface.new(StoreObject: any, Path: StorePath?): typeof(StoreInterface)
    if (VALIDATE_PARAMS) then
        ConstructorParams(StoreObject, Path)
    end

    Path = Path or {}

    local self = {
        _StoreObject = StoreObject;
        _PathString = GetPathString(Path);
        _Path = Path;
    };

    return setmetatable(self, StoreInterface)
end

--- Gets a value in the real store.
function StoreInterface:Get(DefaultValue: any?): any?
    return self._StoreObject:GetUsingPathString(self._PathString, DefaultValue)
end
StoreInterface.get = StoreInterface.Get

--- Sets a value in the real store.
function StoreInterface:Set(...)
    self._StoreObject:SetUsingPathArray(self._Path, ...)
end
StoreInterface.set = StoreInterface.Set

--- Waits for a value in the real store to exist.
function StoreInterface:Await(Timeout: number?, BypassError: boolean?): any?
    return self._StoreObject:AwaitUsingPathString(self._PathString, Timeout, BypassError)
end
StoreInterface.await = StoreInterface.Await

--- Merges a table into the real store. Does NOT start at the path, starts at the root.
function StoreInterface:Merge(Value: any?)
    -- TODO: progressively build up path container internally too maybe?
    if (next(self._Path) == nil) then
        self._StoreObject:Merge(Value)
    else
        self._StoreObject:Merge(BuildFromPath(self._Path, Value == nil and RemoveNode or Value))
    end

    --[[ self._StoreObject:Merge(BuildFromPath(self._Path, Value == nil and RemoveNode or Value)) ]]
end
StoreInterface.merge = StoreInterface.Merge

--- Extends this StoreInterface's path by a new path and gets the value corresponding to that path.
function StoreInterface:XGet(Path): any?
    return self:Extend(Path):Get()
end
StoreInterface.xGet = StoreInterface.XGet

--- Extends this StoreInterface's path by a new path and sets the value corresponding to that path.
function StoreInterface:XSet(Path, ...)
    self:Extend(Path):Set(...)
end
StoreInterface.xSet = StoreInterface.XSet

--- Extends this StoreInterface's path by a new path and waits for the value corresponding to that path to exist.
function StoreInterface:XAwait(Path, Timeout: number?, BypassError: boolean?): any?
    return self:Extend(Path):Await(Timeout, BypassError)
end
StoreInterface.xAwait = StoreInterface.XAwait

--- Extends this StoreInterface's path by a new path and merges a table into the value corresponding on that path.
function StoreInterface:XMerge(Path, ...)
    self:Extend(Path):Merge(...)
end
StoreInterface.xMerge = StoreInterface.XMerge

--- Increments a numerical value in the real store, with an optional default value if it doesn't exist.
--- Note: temporarily deoptimizes replicated store merge batching.
function StoreInterface:Increment(ByAmount: number, DefaultValue: number?, ...): number
    return self._StoreObject:IncrementUsingPathArray(self._Path, ByAmount, DefaultValue, ...)
end
StoreInterface.increment = StoreInterface.Increment

--- Removes a value from an array in the real store.
function StoreInterface:ArrayRemove(...): (any?, number)
    return self._StoreObject:ArrayRemoveUsingPathString(self._PathString, ...)
end
StoreInterface.arrayRemove = StoreInterface.ArrayRemove

--- Inserts a value into an array in the real store.
function StoreInterface:ArrayInsert(...): number?
    return self._StoreObject:ArrayInsertUsingPathString(self._PathString, ...)
end
StoreInterface.arrayInsert = StoreInterface.ArrayInsert

-- TODO: port these to GeneralStore
--[[ function StoreInterface:IsContainer()
    return (type(self:Get()) == TYPE_TABLE)
end; StoreInterface.isContainer = StoreInterface.IsContainer

function StoreInterface:IsArray()
    return (self:IsContainer() and self:Get()[1] ~= nil)
end; StoreInterface.isArray = StoreInterface.IsArray

function StoreInterface:IsEmpty()
    return (self:IsContainer() and next(self:Get()) == nil)
end; StoreInterface.isEmpty = StoreInterface.IsEmpty

function StoreInterface:IsMap()
    return (self:IsContainer() and not self:IsArray() and next(self:Get()) ~= nil)
end; StoreInterface.isMap = StoreInterface.IsMap

function StoreInterface:IsLeaf()
    return (self:Get() ~= nil and not self:IsContainer())
end StoreInterface.isLeaf = StoreInterface.IsLeaf ]]

--- Gets a value changed signal from the real store.
function StoreInterface:GetValueChangedSignal(): typeof(XSignal)
    return self._StoreObject:GetValueChangedSignalUsingPathArray(self._Path)
end
StoreInterface.getValueChangedSignal = StoreInterface.GetValueChangedSignal

--- Creates a new StoreInterface with an extension of the path.
function StoreInterface:Extend(Extra: any): typeof(StoreInterface)
    return StoreInterface.new(self._StoreObject, Merge1D(self._Path, (type(Extra) == TYPE_TABLE and Extra or {Extra})))
end
StoreInterface.extend = StoreInterface.Extend

--- Sets debug logging on/off for the whole store.
function StoreInterface:SetDebugLog(DebugLog: boolean)
    self._StoreObject:SetDebugLog(DebugLog)
end
StoreInterface.setDebugLog = StoreInterface.SetDebugLog

function StoreInterface:Destroy()
end

Cleaner.Wrap(StoreInterface)

return StoreInterface