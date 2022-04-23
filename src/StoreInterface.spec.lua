return function()
    local ReplicatedStore = require(script.Parent:WaitForChild("ReplicatedStore"))
    local MockRemoteEvent = require(script.Parent:WaitForChild("MockRemoteEvent"))
    local StoreInterface = require(script.Parent:WaitForChild("StoreInterface"))

    local function GetTestObject()
        local ClientRemote = MockRemoteEvent.new()
        local ServerRemote = MockRemoteEvent.new()

        ClientRemote.OnFire = function(...)
            ServerRemote.Bind:Fire(...)
        end

        ServerRemote.OnFire = function(...)
            ClientRemote.Bind:Fire(...)
        end

        local Client = ReplicatedStore.new(ClientRemote, false)
        local Server = ReplicatedStore.new(ServerRemote, true)

        Client._TestMode = true
        Server._TestMode = true

        Server:InitServer()
        Client:InitClient()

        local ContainerClient = StoreInterface.new(Client)
        local ContainerServer = StoreInterface.new(Server)

        return ContainerClient, ContainerServer, Client, Server
    end

    local function Equivalent(Initial, Other)
        if (Initial == nil or Other == nil) then
            return false
        end

        for Key, Value in pairs(Initial) do
            local OtherValue = Other[Key]

            if (OtherValue == nil) then
                return false
            end

            if (type(Value) ~= type(OtherValue)) then
                return false
            end

            if (type(Value) == "table") then
                if (not Equivalent(Value, OtherValue)) then
                    return false
                end
            elseif (Value ~= OtherValue) then
                return false
            end
        end

        return true
    end

    describe("StoreInterface.new", function()
        it("should construct", function()
            expect(function()
                GetTestObject()
            end).never.to.throw()
        end)
    end)

    describe("StoreInterface.Get, StoreInterface.Set, StoreInterface.Extend", function()
        it("should return the blank root alone", function()
            local _, Server, _, ServerReplication = GetTestObject()
            expect(Server:Get()).to.equal(ServerReplication._Store._Store)
        end)

        it("should return a flat item", function()
            local Client, Server, ClientReplication, ServerReplication = GetTestObject()

            local ServerTest = Server:Extend("Test")
            ServerTest:Set(30)
            expect(ServerTest:Get()).to.equal(30)
            expect(ServerReplication:Get({"Test"})).to.equal(30)

            local ClientTest = Client:Extend("Test")
            expect(ClientTest:Get()).to.equal(30)
            expect(ClientReplication:Get({"Test"})).to.equal(30)
        end)

        it("should return a deep item", function()
            local Client, Server, ClientReplication, ServerReplication = GetTestObject()

            local ServerTest = Server:Extend("Test")
                local ServerTest2 = ServerTest:Extend("Test2")

            ServerTest2:Set(30)
            expect(ServerTest2:Get()).to.equal(30)
            expect(ServerReplication:Get({"Test", "Test2"})).to.equal(30)

            local ClientTest = Client:Extend("Test")
                local ClientTest2 = ClientTest:Extend("Test2")

            expect(ClientTest2:Get()).to.equal(30)
            expect(ClientReplication:Get({"Test", "Test2"})).to.equal(30)
        end)
    end)

    describe("StoreInterface.Await", function()
        it("should immediately return a flat item", function()
            local Client, Server, _, _ = GetTestObject()

            local ServerTest = Server:Extend("Test")
            ServerTest:Set(30)
            expect(ServerTest:Await()).to.equal(30)

            local ClientTest = Client:Extend("Test")
            expect(ClientTest:Await()).to.equal(30)
        end)

        it("should immediately return a deep item", function()
            local Client, Server, _, _ = GetTestObject()

            local Level1Server = Server:Extend("Level1")
                local Level2Server = Level1Server:Extend("Level2")
                Level2Server:Set(1234)

            expect(Level2Server:Await()).to.equal(1234)

            local Level1Client = Client:Extend("Level1")
                local Level2Client = Level1Client:Extend("Level2")
                expect(Level2Client:Await()).to.equal(1234)
        end)

        it("should return a flat item when present", function()
            local Client, Server, _, _ = GetTestObject()

            local ServerTest = Server:Extend("Test")

            task.delay(0.5, function()
                ServerTest:Set(30)
            end)

            expect(ServerTest:Await()).to.equal(30)

            local ClientTest = Client:Extend("Test")
            expect(ClientTest:Await()).to.equal(30)
        end)

        it("should return a deep item when present", function()
            local Client, Server, _, _ = GetTestObject()

            local Level1Server = Server:Extend("Level1")
                local Level2Server = Level1Server:Extend("Level2")

            task.delay(0.5, function()
                Level2Server:Set(1234)
            end)

            expect(Level2Server:Await()).to.equal(1234)

            local Level1Client = Client:Extend("Level1")
                local Level2Client = Level1Client:Extend("Level2")
                expect(Level2Client:Await()).to.equal(1234)
        end)
    end)

    describe("StoreInterface.IsContainer, StoreInterface.IsArray, StoreInterface.IsMap, StoreInterface.IsLeaf", function()
        it("should not satisfy any of the four types if nil", function()
            local Client, Server, _, _ = GetTestObject()

            local TestServer = Server:Extend("Test")
            expect(TestServer:IsContainer()).to.equal(false)
            expect(TestServer:IsArray()).to.equal(false)
            expect(TestServer:IsMap()).to.equal(false)
            expect(TestServer:IsLeaf()).to.equal(false)

            local TestClient = Client:Extend("Test")
            expect(TestClient:IsContainer()).to.equal(false)
            expect(TestClient:IsArray()).to.equal(false)
            expect(TestClient:IsMap()).to.equal(false)
            expect(TestClient:IsLeaf()).to.equal(false)
        end)

        it("should detect when an item is a container", function()
            local Client, Server, _, _ = GetTestObject()

            local TestServer = Server:Extend("Test")
            TestServer:Set({})
            expect(TestServer:IsContainer()).to.equal(true)
            expect(TestServer:IsArray()).to.equal(false)
            expect(TestServer:IsMap()).to.equal(false)
            expect(TestServer:IsLeaf()).to.equal(false)

            local TestClient = Client:Extend("Test")
            expect(TestClient:IsContainer()).to.equal(true)
            expect(TestClient:IsArray()).to.equal(false)
            expect(TestClient:IsMap()).to.equal(false)
            expect(TestClient:IsLeaf()).to.equal(false)
        end)

        it("should detect when an item is an array", function()
            local Client, Server, _, _ = GetTestObject()

            local TestServer = Server:Extend("Test")
            TestServer:Set({1, 2, 3})
            expect(TestServer:IsContainer()).to.equal(true)
            expect(TestServer:IsArray()).to.equal(true)
            expect(TestServer:IsMap()).to.equal(false)
            expect(TestServer:IsLeaf()).to.equal(false)

            local TestClient = Client:Extend("Test")
            expect(TestClient:IsContainer()).to.equal(true)
            expect(TestClient:IsArray()).to.equal(true)
            expect(TestClient:IsMap()).to.equal(false)
            expect(TestClient:IsLeaf()).to.equal(false)
        end)

        it("should detect when an item is a map", function()
            local Client, Server, _, _ = GetTestObject()

            local TestServer = Server:Extend("Test")
            TestServer:Set({a = 1, b = 2})
            expect(TestServer:IsContainer()).to.equal(true)
            expect(TestServer:IsArray()).to.equal(false)
            expect(TestServer:IsMap()).to.equal(true)
            expect(TestServer:IsLeaf()).to.equal(false)

            local TestClient = Client:Extend("Test")
            expect(TestClient:IsContainer()).to.equal(true)
            expect(TestClient:IsArray()).to.equal(false)
            expect(TestClient:IsMap()).to.equal(true)
            expect(TestClient:IsLeaf()).to.equal(false)
        end)

        it("should detect when an item is a leaf", function()
            local Client, Server, _, _ = GetTestObject()

            local TestServer = Server:Extend("Test")
            TestServer:Set(1234)
            expect(TestServer:IsContainer()).to.equal(false)
            expect(TestServer:IsArray()).to.equal(false)
            expect(TestServer:IsMap()).to.equal(false)
            expect(TestServer:IsLeaf()).to.equal(true)

            local TestClient = Client:Extend("Test")
            expect(TestClient:IsContainer()).to.equal(false)
            expect(TestClient:IsArray()).to.equal(false)
            expect(TestClient:IsMap()).to.equal(false)
            expect(TestClient:IsLeaf()).to.equal(true)
        end)
    end)

    describe("StoreInterface.Increment", function()
        it("should throw if a number is not passed", function()
            local _, Server, _, _ = GetTestObject()

            local TestServer = Server:Extend("Test")
            TestServer:Set(0)

            expect(function()
                TestServer:Increment(true)
            end).to.throw()

            expect(function()
                TestServer:Increment({})
            end).to.throw()

            expect(function()
                TestServer:Increment(1)
            end).never.to.throw()
        end)

        it("should throw if existing value is not a number", function()
            local _, Server, _, _ = GetTestObject()

            local TestServer = Server:Extend("Test")
            TestServer:Set(true)

            expect(function()
                TestServer:Increment(1)
            end).to.throw()
        end)

        it("should accept numeric values if the existing value is a number", function()
            local _, Server, _, _ = GetTestObject()

            local TestServer = Server:Extend("Test")
            TestServer:Set(0)

            expect(function()
                TestServer:Increment(1)
            end).never.to.throw()
        end)

        it("should increment existing numeric values", function()
            local _, Server, _, _ = GetTestObject()

            local TestServer = Server:Extend("Test")
            TestServer:Set(0)
            expect(TestServer:Get()).to.equal(0)
            TestServer:Increment(1)
            expect(TestServer:Get()).to.equal(1)
            TestServer:Increment(2)
            expect(TestServer:Get()).to.equal(3)
        end)

        it("should increment by 1 by default", function()
            local _, Server, _, _ = GetTestObject()

            local TestServer = Server:Extend("Test")
            TestServer:Set(0)
            expect(TestServer:Get()).to.equal(0)
            TestServer:Increment()
            expect(TestServer:Get()).to.equal(1)
            TestServer:Increment()
            expect(TestServer:Get()).to.equal(2)
        end)
    end)

    describe("StoreInterface.GetValueChangedSignal", function()
        it("return the signal", function()
            local Client, Server, _, _ = GetTestObject()

            local TestServer = Server:Extend("Test")
            local TestClient = Client:Extend("Test")

            local ConnectionServer = TestServer:GetValueChangedSignal():Connect(function(_) end)
            local ConnectionClient = TestClient:GetValueChangedSignal():Connect(function(_) end)

            expect(ConnectionServer).to.be.ok()
            expect(ConnectionClient).to.be.ok()

            ConnectionServer:Disconnect()
            ConnectionClient:Disconnect()
        end)

        it("should fire on value change", function()
            local Client, Server, _, _ = GetTestObject()

            local TestServer = Server:Extend("Test")
            local TestClient = Client:Extend("Test")

            local ClientValue, ServerValue

            local ConnectionServer = TestServer:GetValueChangedSignal():Connect(function(Value)
                ServerValue = Value
            end)

            local ConnectionClient = TestClient:GetValueChangedSignal():Connect(function(Value)
                ClientValue = Value
            end)

            expect(ClientValue).never.to.be.ok()
            expect(ServerValue).never.to.be.ok()

            TestServer:Set(1234)

            expect(ClientValue).to.equal(1234)
            expect(ServerValue).to.equal(1234)

            ConnectionServer:Disconnect()
            ConnectionClient:Disconnect()
        end)
    end)

    describe("StoreInterface.Insert", function()
        it("should allow an empty array", function()
            local _, Server, _, _ = GetTestObject()
            local TestServer = Server:Extend("Test")

            TestServer:Set({})
            TestServer:Insert(1)
        end)

        it("should reject a non-array", function()
            local _, Server, _, _ = GetTestObject()
            local TestServer = Server:Extend("Test")

            TestServer:Set(1234)

            expect(function()
                TestServer:Insert(1)
            end).to.throw()

            TestServer:Set("")

            expect(function()
                TestServer:Insert(1)
            end).to.throw()

            TestServer:Set({
                Test = true
            })

            expect(function()
                TestServer:Insert(1)
            end).to.throw()

            TestServer:Set(true)

            expect(function()
                TestServer:Insert(1)
            end).to.throw()
        end)

        it("should insert into an empty array", function()
            local Client, Server, _, _ = GetTestObject()

            local TestServer = Server:Extend("Test")
            local TestClient = Client:Extend("Test")

            TestServer:Set({})
            TestServer:Insert(1)

            expect(TestServer:Get()[1]).to.equal(1)
            expect(TestClient:Get()[1]).to.equal(1)
        end)

        it("should insert multiple times into an array", function()
            local Client, Server, _, _ = GetTestObject()

            local TestServer = Server:Extend("Test")
            local TestClient = Client:Extend("Test")

            TestServer:Set({})
            TestServer:Insert(1)
            TestServer:Insert(2)
            TestServer:Insert(3)

            expect(TestServer:Get()[1]).to.equal(1)
            expect(TestServer:Get()[2]).to.equal(2)
            expect(TestServer:Get()[3]).to.equal(3)
            expect(TestClient:Get()[1]).to.equal(1)
            expect(TestClient:Get()[2]).to.equal(2)
            expect(TestClient:Get()[3]).to.equal(3)
        end)

        it("should shift everything up for mid-array inserts", function()
            local _, Server, _, _ = GetTestObject()

            local TestServer1 = Server:Extend("Test1")
            TestServer1:Set({1})
            TestServer1:Insert(2, 123)
            TestServer1:Insert(1, 456)

            expect(TestServer1:Get()[1]).to.equal(456)
            expect(TestServer1:Get()[2]).to.equal(1)
            expect(TestServer1:Get()[3]).to.equal(123)
        end)
    end)

    describe("StoreInterface.Remove", function()
        it("should allow an empty array", function()
            local _, Server, _, _ = GetTestObject()
            local TestServer = Server:Extend("Test")

            TestServer:Set({})
            TestServer:Remove()
        end)

        it("should allow an array with 1 item", function()
            local _, Server, _, _ = GetTestObject()
            local TestServer = Server:Extend("Test")

            TestServer:Set({1})
            TestServer:Remove()
        end)

        it("should reject a non-array", function()
            local _, Server, _, _ = GetTestObject()
            local TestServer = Server:Extend("Test")

            TestServer:Set(1234)

            expect(function()
                TestServer:Remove()
            end).to.throw()

            TestServer:Set("")

            expect(function()
                TestServer:Remove()
            end).to.throw()

            TestServer:Set({
                Test = true
            })

            expect(function()
                TestServer:Remove()
            end).to.throw()

            TestServer:Set(true)

            expect(function()
                TestServer:Remove()
            end).to.throw()
        end)

        it("should remove from a non-empty array multiple times", function()
            local Client, Server, _, _ = GetTestObject()

            local TestServer = Server:Extend("Test")
            local TestClient = Client:Extend("Test")

            TestServer:Set({1, 2, 3})
            TestServer:Remove()
            expect(TestServer:Get()[1]).to.equal(1)
            expect(TestServer:Get()[2]).to.equal(2)
            expect(TestServer:Get()[3]).to.equal(nil)
            TestServer:Remove()
            expect(TestServer:Get()[1]).to.equal(1)
            expect(TestServer:Get()[2]).to.equal(nil)
            expect(TestServer:Get()[3]).to.equal(nil)
            TestServer:Remove()
            expect(TestServer:Get()[1]).to.equal(nil)
            expect(TestServer:Get()[2]).to.equal(nil)
            expect(TestServer:Get()[3]).to.equal(nil)

            expect(TestServer:IsEmpty()).to.equal(true)
            expect(TestClient:IsEmpty()).to.equal(true)
        end)

        it("should remove from a mid-position and shift down", function()
            local _, Server, _, _ = GetTestObject()

            local TestServer = Server:Extend("Test")
            TestServer:Set({1, 2, 3})
            TestServer:Remove(2)

            expect(TestServer:Get()[1]).to.equal(1)
            expect(TestServer:Get()[2]).to.equal(3)
        end)

        it("should return the removed item and index", function()
            local _, Server, _, _ = GetTestObject()

            local TestServer = Server:Extend("Test")
            TestServer:Set({1, 2, 3})
            local Value, Index = TestServer:Remove(2)
            expect(Value).to.equal(2)
            expect(Index).to.equal(2)

            expect(TestServer:Get()[1]).to.equal(1)
            expect(TestServer:Get()[2]).to.equal(3)
        end)
    end)
end