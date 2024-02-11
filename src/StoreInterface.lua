--!nonstrict

-- Allows easy command bar paste.
if (not script) then
	script = game:GetService("ReplicatedFirst").Vapor.GeneralStore
end

local XSignal = require(script.Parent.Parent:WaitForChild("XSignal"))
    type XSignal<T...> = XSignal.XSignal<T...>
local Store = require(script.Parent:WaitForChild("GeneralStore"))
    type StorePath = Store.StorePath

local TYPE_TABLE = "table"
local TYPE_NUMBER = "number"

local ERR_NOT_ARRAY = "Item was not an array"
local ERR_INCREMENT_NOT_NUMBER = "Invalid argument #1 (expected number, got %s)"
local ERR_INCREMENT_NO_EXISTING_VALUE = "Invalid existing value for %s (expected number, got %s)"

local REMOVE_NODE = Store._REMOVE_NODE
local BuildFromPath = Store._BuildFromPath

export type StandardMethods<Type> = {
    Get: ((any, Type?) -> (Type));
    Set: ((any, Type?) -> ());
    Await: ((any, number?, boolean?) -> (Type));
    Merge: ((any, any) -> ());

    XGet: ((any, StorePath) -> (Type));
    XSet: ((any, StorePath, Type, ...any) -> ());
    XAwait: ((any, StorePath) -> (Type));
    XMerge: ((any, StorePath, Type, ...any) -> ());

    IsMap: ((any) -> (boolean));
    IsLeaf: ((any) -> (boolean));
    IsArray: ((any) -> (boolean));
    IsEmpty: ((any) -> (boolean));
    IsContainer: ((any) -> (boolean));

    Extend: ((any, StorePath | {StorePath}) -> (any));
    SetDebugLog: ((any, boolean?) -> ());
    GetValueChangedSignal: ((any) -> (XSignal<Type, Type?>));
    GetSubValueChangedSignal: ((any) -> XSignal<string, any?, any?>);
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

local IsServer = game:GetService("RunService"):IsServer()

local StoreInterface = {}

local function _Extend(self, Key)
    if (type(Key) == "table") then
        local Last = self

        for _, SubKey in Key do
            Last = _Extend(Last, SubKey)
        end

        return Last
    end

    local Cache = self._Cache
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

function StoreInterface.new(StoreObject: Store.RawStore, Path: StorePath?)
    assert(StoreObject, "No StoreContainer object given!")

    local self = {
        _StoreObject = StoreObject;
        _Cache = {};
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
end

function StoreInterface:Set(...)
    self._StoreObject:Set(self._Path, ...)
end

function StoreInterface:Await(...)
    return self._StoreObject:Await(self._Path, ...)
end

function StoreInterface:Merge(Value)
    -- TODO: progressively build up path container internally too maybe?
    if (next(self._Path) == nil) then
        self._StoreObject:Merge(Value)
    else
        self._StoreObject:Merge(BuildFromPath(self._Path, Value == nil and REMOVE_NODE or Value))
    end
end

--[[
    X variants i.e. "extend then [do standard action]"
]]
function StoreInterface:XGet(Path, ...)
    return self:Extend(Path):Get(...)
end

function StoreInterface:XSet(Path, ...)
    self:Extend(Path):Set(...)
end

function StoreInterface:XAwait(Path, ...)
    return self:Extend(Path):Await(...)
end

function StoreInterface:XMerge(Path, ...)
    self:Extend(Path):Merge(...)
end

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
end

function StoreInterface:IsArray()
    return (self:IsContainer() and self:Get()[1] ~= nil)
end

function StoreInterface:IsEmpty()
    return (self:IsContainer() and next(self:Get()) == nil)
end

function StoreInterface:IsMap()
    return (self:IsContainer() and not self:IsArray() and next(self:Get()) ~= nil)
end

function StoreInterface:IsLeaf()
    return (self:Get() ~= nil and not self:IsContainer())
end

function StoreInterface:GetValueChangedSignal()
    return self._StoreObject:GetValueChangedSignal(self._Path)
end

function StoreInterface:GetSubValueChangedSignal()
    return self._StoreObject:GetSubValueChangedSignal(self._Path)
end

--[[
    Creates a new StoreInterface with an
    extension of the path.
]]
--[[ function StoreInterface:Extend(Extra)
    if (type(Extra) ~= TYPE_TABLE) then
        Extra = {Extra}
    end

    local Path = self._Path
    local PathLength = #Path
    local ExtraLength = #Extra

    local NewPath = table.create(PathLength + ExtraLength)

    for Index = 1, PathLength do
        table.insert(NewPath, Path[Index])
    end

    for Index = 1, ExtraLength do
        table.insert(NewPath, Extra[Index])
    end

    return StoreInterface.new(self._StoreObject, NewPath)
end ]]

StoreInterface.Extend = _Extend

function StoreInterface:SetDebugLog(DebugLog: boolean)
    self._StoreObject:SetDebugLog(DebugLog)
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

return StoreInterface