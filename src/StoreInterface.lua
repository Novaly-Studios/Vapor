--!nonstrict
local TableUtil = require(script.Parent.Parent:WaitForChild("TableUtil"))
    local Array = TableUtil.Array
        local Merge1D = Array.Merge1D
local Cleaner = require(script.Parent.Parent:WaitForChild("Cleaner"))
local Signal = require(script.Parent.Parent:WaitForChild("Signal"))
    type Signal<T> = Signal.Type<T>
local Store = require(script.Parent:WaitForChild("GeneralStore"))
    type StorePath = Store.StorePath

local TYPE_TABLE = "table"
local TYPE_NUMBER = "number"

local ERR_NOT_ARRAY = "Item was not an array"
local ERR_INCREMENT_NOT_NUMBER = "Invalid argument #1 (expected number, got %s)"
local ERR_INCREMENT_NO_EXISTING_VALUE = "Invalid existing value for %s (expected number, got %s)"

local BuildFromPath = Store._BuildFromPath
local REMOVE_NODE = Store._REMOVE_NODE

export type Type<T> = {
    Get: ((Type<T>) -> (T?));
    Set: ((Type<T>, T) -> ());
    Await: ((Type<T>) -> (T));
    Merge: ((Type<T>, T) -> ());

    XGet: ((Type<T>, StorePath) -> (T?));
    XSet: ((Type<T>, StorePath, T) -> ());
    XAwait: ((Type<T>, StorePath) -> (T));
    XMerge: ((Type<T>, StorePath, T) -> ());

    IsMap: ((Type<T>) -> (boolean));
    IsLeaf: ((Type<T>) -> (boolean));
    IsArray: ((Type<T>) -> (boolean));
    IsEmpty: ((Type<T>) -> (boolean));
    IsContainer: ((Type<T>) -> (boolean));

    -- Number manipulation functions
    Increment: ((Type<T>, number?, number?) -> (number));

    -- Array manipulation functions
    Remove: ((Type<T>, number) -> (T));
    Insert: ((Type<T>, T, number?) -> (number));

    GetValueChangedSignal: ((Type<T>) -> (Signal<T>));

    Extend: ((Type<T>, StorePath) -> (Type<any>));
}

local StoreInterface = {}
StoreInterface.__index = StoreInterface

function StoreInterface.new(StoreObject: Store.RawStore, Path: StorePath)
    assert(StoreObject, "No StoreContainer object given!")

    local self = {
        _StoreObject = StoreObject;
        _Path = Path or {};
    };

    return setmetatable(self, StoreInterface)
end

--[[
    Standard get/set/await/etc. for manipulating
    and reading data.
]]
function StoreInterface:Get(...)
    return self._StoreObject:Get(self._Path, ...)
end; StoreInterface.get = StoreInterface.Get

function StoreInterface:Set(...)
    self._StoreObject:Set(self._Path, ...)
end; StoreInterface.set = StoreInterface.Set

function StoreInterface:Await(...)
    return self._StoreObject:Await(self._Path, ...)
end; StoreInterface.await = StoreInterface.Await

function StoreInterface:Merge(Value)
    -- TODO: progressively build up path container internally too maybe?
    if (next(self._Path) == nil) then
        self._StoreObject:Merge(Value)
    else
        self._StoreObject:Merge(BuildFromPath(self._Path, Value == nil and REMOVE_NODE or Value))
    end
end; StoreInterface.merge = StoreInterface.Merge

--[[
    X variants i.e. "extend then [do standard action]"
]]
function StoreInterface:XGet(Path, ...)
    return self:Extend(Path):Get(...)
end; StoreInterface.xGet = StoreInterface.XGet

function StoreInterface:XSet(Path, ...)
    self:Extend(Path):Set(...)
end; StoreInterface.xSet = StoreInterface.XSet

function StoreInterface:XAwait(Path, ...)
    return self:Extend(Path):Await(...)
end; StoreInterface.xAwait = StoreInterface.XAwait

function StoreInterface:XMerge(Path, ...)
    self:Extend(Path):Merge(...)
end; StoreInterface.xMerge = StoreInterface.XMerge

-- Numeric value functions
    function StoreInterface:Increment(ByAmount, DefaultValue, ...)
        assert(type(ByAmount) == TYPE_NUMBER or ByAmount == nil, ERR_INCREMENT_NOT_NUMBER:format(type(ByAmount)))

        local ExistingValue = self:Get()

        if (DefaultValue and ExistingValue == nil) then
            ExistingValue = DefaultValue
            self:Set(DefaultValue)
        else
            assert(type(ExistingValue) == TYPE_NUMBER, ERR_INCREMENT_NO_EXISTING_VALUE:format(tostring(self), type(ExistingValue)))
        end

        local NewValue = ExistingValue + (ByAmount or 1)
        self:Set(NewValue, ...)
        return NewValue
    end; StoreInterface.increment = StoreInterface.Increment

-- Array functions
    function StoreInterface:Remove(Index)
        assert(self:IsArray() or self:IsEmpty(), ERR_NOT_ARRAY)

        local Array = self:Get()
        local Size = #Array
        Index = Index or Size
        local Temp = Array[Index]

        if (Size > 0) then
            table.remove(Array, Index)
            self:Set(Array)
        end

        return Temp, Index
    end

    function StoreInterface:Insert(...)
        assert(self:IsArray() or self:IsEmpty(), ERR_NOT_ARRAY)

        local Array = self:Get()
        table.insert(Array, ...)
        self:Set(Array)
    end

function StoreInterface:IsContainer()
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
end StoreInterface.isLeaf = StoreInterface.IsLeaf

function StoreInterface:GetValueChangedSignal()
    return self._StoreObject:GetValueChangedSignal(self._Path)
end; StoreInterface.getValueChangedSignal = StoreInterface.GetValueChangedSignal

--[[
    Creates a new StoreInterface with an
    extension of the path.
]]
function StoreInterface:Extend(Extra)
    if (type(Extra) ~= TYPE_TABLE) then
        Extra = {Extra}
    end

    return StoreInterface.new(self._StoreObject, Merge1D(self._Path, Extra))
end; StoreInterface.extend = StoreInterface.Extend

function StoreInterface:SetDebugLog(DebugLog: boolean)
    self._StoreObject:SetDebugLog(DebugLog)
end; StoreInterface.setDebugLog = StoreInterface.SetDebugLog

function StoreInterface:Destroy()
end

Cleaner.Wrap(StoreInterface)

return StoreInterface