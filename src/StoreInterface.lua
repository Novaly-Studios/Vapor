--!native
--!optimize 2
--!nonstrict

-- Allows easy command bar paste.
if (not script) then
	script = game:GetService("ReplicatedFirst").Vapor.StoreInterface
end

local RunService = game:GetService("RunService")

local XSignal = require(script.Parent.Parent.XSignal)
    type XSignal<T...> = XSignal.XSignal<T...>
local GeneralStore = require(script.Parent.GeneralStore)
    type GeneralStorePath = GeneralStore.GeneralStorePath

local ERR_INCREMENT_NO_EXISTING_VALUE = "Invalid existing value for %s (expected number, got %s)"
local ERR_INCREMENT_NOT_NUMBER = "Invalid argument #1 (expected number, got %s)"
local ERR_NOT_ARRAY = "Item was not an array"

local BuildFromPath = GeneralStore._BuildFromPath
local RemoveNode = GeneralStore._RemoveNode
local IsServer = RunService:IsServer()

export type StandardMethods<Type> = {
    GetSubValueChangedSignal: ((any) -> XSignal<string, any?, any?>);
    GetValueChangedSignal: ((any) -> (XSignal<Type, Type?>));
    ExclusiveSync: ((any, {Player}?) -> ());
    SetDebugLog: ((any, boolean?) -> ());
    Extend: ((any, GeneralStorePath | {GeneralStorePath}) -> (any));

    Await: ((any, number?, boolean?) -> (Type));
    Merge: ((any, any) -> ());
    Get: ((any, Type?) -> (Type));
    Set: ((any, Type?) -> ());
}

export type Node<Type> = StandardMethods<Type> & Type

export type CollectionNode<Key, Value> = {[Key]: Node<Value>}

export type ArrayNode<Type> = {
    [number]: Node<Type> & {
        Remove: ((any, number) -> (Type));
        Insert: ((any, Type, number?) -> (number));
    };
}

export type NumberNode = Node<number> & {
    Increment: ((any, number?, number?, ...any) -> (number));
}

local WEAK_VALUE_MT = {__mode = "v"}

local StoreInterface = {}

local function _Extend(self, Key)
    if (type(Key) == "table") then
        local Last = self
        for _, SubKey in Key do
            Last = _Extend(Last, SubKey)
        end
        return Last
    end

    local Cache = rawget(self, "_Cache")
    if (not Cache) then
        Cache = {}
        self._Cache = Cache
    end

    local Cached = Cache[Key]
    if (Cached) then
        return Cached
    end

    if (IsServer and not getmetatable(Cache)) then
        setmetatable(Cache, WEAK_VALUE_MT)
    end

    local NewPath = table.clone(self._Path)
    table.insert(NewPath, Key)
    Cached = StoreInterface.new(self._StoreObject, NewPath)
    Cache[Key] = Cached
    return Cached
end

function StoreInterface:__index(Key: string | {string})
    return rawget(self, Key) or StoreInterface[Key] or _Extend(self, Key)
end

function StoreInterface.new(StoreObject: GeneralStore.GeneralStoreStructure, Path: GeneralStorePath?)
    local self = {
        _StoreObject = assert(StoreObject, "No StoreContainer object given!");
        _Cache = nil;
        _Path = Path or {};
    }
    return setmetatable(self, StoreInterface)
end

function StoreInterface:Get(...)
    return self._StoreObject.Get(self._Path, ...)
end

function StoreInterface:Set(...)
    self._StoreObject.Set(self._Path, ...)
end

function StoreInterface:Await(...)
    return self._StoreObject.Await(self._Path, ...)
end

function StoreInterface:Merge(Value, SendTo)
    if (next(self._Path) == nil) then
        self._StoreObject.Merge(Value, SendTo)
    else
        self._StoreObject.Merge(BuildFromPath(self._Path, Value == nil and RemoveNode or Value), SendTo)
    end
end

function StoreInterface:Increment(ByAmount, DefaultValue, ...)
    assert(type(ByAmount) == "number" or ByAmount == nil, ERR_INCREMENT_NOT_NUMBER:format(type(ByAmount)))

    local ExistingValue = self:Get()

    if (DefaultValue and ExistingValue == nil) then
        ExistingValue = DefaultValue
        self:Set(DefaultValue)
    else
        assert(type(ExistingValue) == "number", ERR_INCREMENT_NO_EXISTING_VALUE:format(tostring(self), type(ExistingValue)))
    end

    local NewValue = ExistingValue + (ByAmount or 1)
    self:Set(NewValue, ...)
    return NewValue
end

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

function StoreInterface:GetValueChangedSignal()
    return self._StoreObject.GetValueChangedSignal(self._Path)
end

function StoreInterface:GetSubValueChangedSignal()
    return self._StoreObject.GetSubValueChangedSignal(self._Path)
end

--- Creates a new StoreInterface with an
--- extension of the path.
StoreInterface.Extend = _Extend

function StoreInterface:ExclusiveSync(Players)
    assert(type(Players) == "table", "Players must be a table or '*'")
    self._StoreObject.ExclusiveSync(self._Path, Players)
end

function StoreInterface:SetDebugLog(DebugLog: boolean)
    self._StoreObject.SetDebugLog(DebugLog)
end

function StoreInterface:Destroy()
end

--[[
    -- Example w/ typed structure & autocomplete:

    local Root = StoreInterface.new(Store) :: MapNode<{
        TestArray: ArrayNode<MapNode<{
            X: NumberNode;
            Y: NumberNode;
            Something: MapNode<{
                Value: StringNode;
            }>;
        }>>;
    }>;

    local Result = Root.TestArray[1].Something.Value:Await()
]]

return table.freeze(StoreInterface)