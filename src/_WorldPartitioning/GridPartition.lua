local DEFAULT_GRID_SIZE = 50
local DEFAULT_SPACE_MULTIPLIER = Vector3.new(1, 0, 1) -- Exclude Y axis

local GridPartition = {}
GridPartition.__index = GridPartition

function GridPartition.new(GridSize: number?, SpaceMultiplier: Vector3?)
    local self = {
        Grid = {};
        GridSize = GridSize or DEFAULT_GRID_SIZE;
        SpaceMultiplier = SpaceMultiplier or DEFAULT_SPACE_MULTIPLIER;
        ElementToChunks = {};
    };

    return setmetatable(self, GridPartition)
end

function GridPartition:Translate(AtPosition: Vector3): Vector3
    local Resolution = self.GridSize

    return self.SpaceMultiplier * Vector3.new(
        math.floor(AtPosition.X / Resolution),
        math.floor(AtPosition.Y / Resolution),
        math.floor(AtPosition.Z / Resolution)
    )
end

function GridPartition:Get(AtPosition: Vector3, Offset: Vector3?)
    local Grid = self.Grid

    if (Offset) then
        return Grid[self:Translate(AtPosition) + Offset]
    end

    return Grid[self:Translate(AtPosition)]
end

function GridPartition:GetSurrounding(AtPosition: Vector3, Length: number?)
    Length = Length or 1

    local Result = table.create((Length * 2 + 1) ^ 3)

    for X = -Length, Length do
        for Y = -Length, Length do
            for Z = -Length, Length do
                table.insert(Result, self:Get(AtPosition, Vector3.new(X, Y, Z)))
            end
        end
    end

    return Result
end

function GridPartition:Register(AtPosition: Vector3, Element, NoTranslate: boolean?)
    if (not NoTranslate) then
        AtPosition = self:Translate(AtPosition)
    end

    -- Put in chunk
    local Grid = self.Grid
    local Intersections = Grid[AtPosition]

    if (not Intersections) then
        Intersections = {}
        Grid[AtPosition] = Intersections
    end

    if (not Intersections[Element]) then
        Intersections[Element] = true
    end

    -- Put in element-to-chunks
    local ElementToChunks = self.ElementToChunks
    local ChunksForElement = ElementToChunks[Element]

    if (not ChunksForElement) then
        ChunksForElement = {}
        ElementToChunks[Element] = ChunksForElement
    end

    ChunksForElement[AtPosition] = true
end

function GridPartition:Remove(AtPosition: Vector3, Element, NoTranslate: boolean?)
    if (not NoTranslate) then
        AtPosition = self:Translate(AtPosition)
    end

    -- Remove from chunk
    local Grid = self.Grid
    local Intersections = Grid[AtPosition]

    if (not Intersections) then
        return
    end

    Intersections[Element] = nil

    if (next(Intersections) == nil) then
        Grid[AtPosition] = nil
    end

    -- Remove chunk from element-to-chunks
    local ElementToChunks = self.ElementToChunks
    local ChunksForElement = ElementToChunks[Element]
    ChunksForElement[AtPosition] = nil

    if (next(ChunksForElement) == nil) then
        ElementToChunks[Element] = nil
    end
end

function GridPartition:Reposition(AtPosition: Vector3, Element)
    local ChunksForElement = self.ElementToChunks[Element]

    if (ChunksForElement) then
        for Position in pairs(ChunksForElement) do
            self:Remove(Position, Element, true)
        end
    end

    self:Register(AtPosition, Element)
    self:UpdateVisualization()
end

function GridPartition:UpdateVisualization()
    local GridSize = self.GridSize
    local HalfGridSize = GridSize / 2

    local Workspace = game:GetService("Workspace")
    local Existing = Workspace:FindFirstChild("SHGrid")

    if (Existing) then
        Existing:Destroy()
    end

    local NewGrid = Instance.new("Model")
    NewGrid.Name = "SHGrid"

    local ElementCount = 0

    for _ in pairs(self.ElementToChunks) do
        ElementCount += 1
    end

    for Position, Elements in pairs(self.Grid) do
        local ElementCountInGrid = 0

        for _ in pairs(Elements) do
            ElementCountInGrid += 1
        end

        local Part = Instance.new("Part")
        Part.Transparency = 1
        Part.Locked = true
        Part.Anchored = true
        Part.Size = Vector3.new(GridSize, GridSize, GridSize)
        Part.Position = Vector3.new(
            Position.X * GridSize + HalfGridSize,
            Position.Y * GridSize + HalfGridSize,
            Position.Z * GridSize + HalfGridSize
        )

        local Brightness = math.min(1, ElementCountInGrid / ElementCount)

        local SelectionBox = Instance.new("SelectionBox")
        SelectionBox.Adornee = Part
        SelectionBox.Color3 = Color3.new(Brightness, Brightness, Brightness)
        SelectionBox.LineThickness = 0.5
        SelectionBox.Parent = Part

        Part.Parent = NewGrid
    end

    NewGrid.Parent = Workspace
end

return GridPartition

--[[ local Test = GridPartition.new(100)

local function Update(Part)
    Test:Reposition(Vector3.new(Part.Position.X, 0, Part.Position.Z), Part)
    Test:UpdateVisualization()
end

local Connections = {}

for _, Item in pairs(workspace:GetChildren()) do
    if (not Item:IsA("BasePart") or Item.Name ~= "Part") then
        continue
    end

    table.insert(Connections, Item:GetPropertyChangedSignal("Position"):Connect(function()
        Update(Item)
    end))

    Update(Item)
end ]]

--[[ task.wait(30)

for _, Connection in pairs(Connections) do
    Connection:Disconnect()
end ]]