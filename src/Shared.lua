local TypeGuard = require(script.Parent.Parent:WaitForChild("TypeGuard"))

export type StoreKey = string | number
export type StorePath = {StoreKey}

local CachedPathTables = setmetatable({}, {__mode = "k"})

local TYPE_TABLE = "table"

local FLAT_PATH_DELIMITER = "^"
local EMPTY_STRING = ""

local ERR_NO_ITEMS_IN_PATH = "No items in path (no ascendants derivable)"
local ERR_NO_VALUE_GIVEN = "No value given!"
local ERR_NO_PATH_GIVEN = "No path given!"

local REMOVE_NODE = {_REMOVE_NODE = true}

-----------------------------------------------------------------------------------

-- Traverses each item in the table recursively, creating a path string for each
-- Not inclusive of root
local function PathTraverse(Root: any, Path: string, Callback: (string, any, string) -> ())
    for Key, Value in Root do
        local NewPath = Path .. tostring(Key) .. FLAT_PATH_DELIMITER

        if (type(Value) == TYPE_TABLE) then
            PathTraverse(Value, NewPath, Callback)
        end

        -- Pass: new path, value, parent path
        Callback(NewPath, Value, Path)
    end
end

local function GetPathString(Path: StorePath): string
    local PathString = CachedPathTables[Path]

    if (PathString) then
        return PathString
    end

    local Result = EMPTY_STRING

    for _, Value in Path do
        Result ..= tostring(Value) .. FLAT_PATH_DELIMITER
    end

    CachedPathTables[Path] = Result

    return Result
end

local function InternalMerge(Data: any, Into: any, BypassRemoveNode: boolean?)
    for Key, Value in Data do
        if ((not BypassRemoveNode) and Value == REMOVE_NODE) then
            Into[Key] = nil
            continue
        end

        if (typeof(Value) == TYPE_TABLE) then
            local Got = Into[Key]

            if (Got == nil) then
                Got = {}
                Into[Key] = Got
            end

            InternalMerge(Value, Got, BypassRemoveNode)
            continue
        end

        Into[Key] = Value
    end
end

local function BuildFromPath(Path: StorePath, Value: any): any
    assert(Path, ERR_NO_PATH_GIVEN)
    assert(Value ~= nil, ERR_NO_VALUE_GIVEN)

    local Length = #Path

    if (Length == 0) then
        return Value
    end

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

local ValidStorePathAtom = TypeGuard.String():Or(TypeGuard.Number())
local ValidStorePath = TypeGuard.Array(ValidStorePathAtom)

return {
    FlatPathDelimiter = FLAT_PATH_DELIMITER;
    RemoveNode = REMOVE_NODE;

    GetPathString = GetPathString;
    BuildFromPath = BuildFromPath;
    InternalMerge = InternalMerge;
    PathTraverse = PathTraverse;

    ValidStorePath = ValidStorePath;
};