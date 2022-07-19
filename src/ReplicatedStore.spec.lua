return function()
    local MockRemoteEvent = require(script.Parent:WaitForChild("MockRemoteEvent"))
    local ReplicatedStore = require(script.Parent:WaitForChild("ReplicatedStore"))

    -- Obtains client and server test objects, and a fake remote event between them
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

        return Client, Server
    end

    -- Checks if two tables are equal
    local function Equivalent(Initial, Other)
        for InitialKey, InitialValue in Initial do
            local OtherValue = Other[InitialKey]

            if (OtherValue == nil) then
                return false
            end

            if (type(InitialValue) == "table") then
                if (not Equivalent(InitialValue, OtherValue)) then
                    return false
                end
            elseif (OtherValue ~= InitialValue) then
                return false
            end
        end

        for OtherKey in Other do
            if (Initial[OtherKey] == nil) then
                return false
            end
        end

        return true
    end

    describe("ReplicatedStore.new", function()
        it("should construct", function()
            expect(function()
                GetTestObject()
            end).never.to.throw()
        end)
    end)

    describe("ReplicatedStore.Set", function()
        it("should sync initial state", function()
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

            Server:SetUsingPathArray({"A"}, true)
            Server:SetUsingPathArray({"B", "C"}, 1000)
            Server:SetUsingPathArray({"B", "C"}, 1125)

            Client:InitClient()

            expect(Client:GetUsingPathArray().A).to.be.ok()
            expect(Client:GetUsingPathArray().B).to.be.ok()
            expect(Client:GetUsingPathArray().B.C).to.be.ok()

            expect(Client:GetUsingPathArray().A).to.equal(true)
            expect(Client:GetUsingPathArray().B.C).to.equal(1125)
        end)

        it("should set flat values", function()
            local Client, Server = GetTestObject()
            Server:SetUsingPathArray({"A"}, true)
            Server:SetUsingPathArray({"B"}, true)

            expect(Server:GetUsingPathArray().A).to.equal(true)
            expect(Client:GetUsingPathArray().A).to.equal(true)

            expect(Server:GetUsingPathArray().B).to.equal(true)
            expect(Client:GetUsingPathArray().B).to.equal(true)

            expect(Equivalent(Client:GetUsingPathArray(), Server:GetUsingPathArray())).to.equal(true)
        end)

        it("should set flat value 'false'", function()
            local Client, Server = GetTestObject()
            Server:SetUsingPathArray({"A"}, false)
            Server:SetUsingPathArray({"B"}, false)

            expect(Server:GetUsingPathArray().A).to.equal(false)
            expect(Client:GetUsingPathArray().A).to.equal(false)

            expect(Server:GetUsingPathArray().B).to.equal(false)
            expect(Client:GetUsingPathArray().B).to.equal(false)

            expect(Equivalent(Client:GetUsingPathArray(), Server:GetUsingPathArray())).to.equal(true)
        end)

        it("should set deep values", function()
            local Client, Server = GetTestObject()
            Server:SetUsingPathArray({"A", "B", "C"}, 100)

            expect(Server:GetUsingPathArray().A.B.C).to.equal(100)
            expect(Client:GetUsingPathArray().A.B.C).to.equal(100)

            expect(Equivalent(Client:GetUsingPathArray(), Server:GetUsingPathArray())).to.equal(true)
        end)

        it("should throw on empty path i.e. root overwrite", function()
            local Client, Server = GetTestObject()

            expect(function()
                Server:SetUsingPathArray({}, 100)
            end).to.throw()
        end)

        it("should set flat values in order", function()
            local Client, Server = GetTestObject()
            Server:SetUsingPathArray({"A"}, true)
            Server:SetUsingPathArray({"A"}, 9000)

            Server:SetUsingPathArray({"B"}, true)
            Server:SetUsingPathArray({"B"}, 1000)

            expect(Server:GetUsingPathArray().A).to.equal(9000)
            expect(Client:GetUsingPathArray().A).to.equal(9000)

            expect(Server:GetUsingPathArray().B).to.equal(1000)
            expect(Client:GetUsingPathArray().B).to.equal(1000)

            expect(Equivalent(Client:GetUsingPathArray(), Server:GetUsingPathArray())).to.equal(true)
        end)

        it("should set deep values in order", function()
            local Client, Server = GetTestObject()
            Server:SetUsingPathArray({"A", "B", "C"}, 100)

            expect(Server:GetUsingPathArray().A.B.C).to.equal(100)
            expect(Client:GetUsingPathArray().A.B.C).to.equal(100)

            expect(Equivalent(Client:GetUsingPathArray(), Server:GetUsingPathArray())).to.equal(true)
        end)

        it("should send and receive large sample data", function()
            -- TODO: remove mixed keys
            local Client, Server = GetTestObject()
            local Generator = Random.new(os.clock())

            for _ = 1, 100 do
                local Path = {}
                local FinalValue = (Generator:NextNumber() > 0.5 and Generator:NextInteger(1, 10e8) or tostring(Generator:NextInteger(1, 10e8)))

                for Depth = 1, Generator:NextInteger(1, 5) do
                    Path[Depth] = (Generator:NextNumber() > 0.5 and Generator:NextInteger(1, 10e8) or tostring(Generator:NextInteger(1, 10e8)))
                end

                Server:SetUsingPathArray(Path, FinalValue)
            end

            expect(Equivalent(Client:GetUsingPathArray(), Server:GetUsingPathArray())).to.equal(true)
        end)

        it("should convert keys to numeric when applicable", function()
            local Client, Server = GetTestObject()
            Server:SetUsingPathArray({1, "201", "AHHH"}, true)

            expect(Client:GetUsingPathArray()[1]).to.be.ok()
            expect(Client:GetUsingPathArray()[1][201]).to.be.ok()
            expect(Client:GetUsingPathArray()[1][201].AHHH).to.be.ok()

            expect(Equivalent(Client:GetUsingPathArray(), Server:GetUsingPathArray())).to.equal(true)
        end)

        it("should not allow mixed keys", function()
            local Client, Server = GetTestObject()

            expect(function()
                Server:SetUsingPathArray({1}, true)
                Server:SetUsingPathArray({"a"}, true)
            end).to.throw()

            expect(function()
                Server:SetUsingPathArray({"a"}, true)
                Server:SetUsingPathArray({1}, true)
            end).to.throw()
        end)

        it("should trigger await events for tables being overwritten by atoms", function()
            local Client, Server = GetTestObject()

            Server:SetUsingPathArray({"One", "Two", "Three"}, true)

            local Fired1 = false
            local Fired2 = false
            local Fired3 = false

            Server:GetValueChangedSignalUsingPathArray({"One", "Two", "Three", "Four"}):Connect(function(Value)
                -- Shouldn't fire for non-existent nodes
                Fired3 = true
            end)

            Server:GetValueChangedSignalUsingPathArray({"One", "Two", "Three"}):Connect(function(Value)
                expect(Value).to.equal(nil)
                Fired1 = true
            end)

            Server:GetValueChangedSignalUsingPathArray({"One"}):Connect(function(Value)
                expect(Value).to.equal(200)
                Fired2 = true
            end)

            expect(Fired1).to.equal(false)
            expect(Fired2).to.equal(false)
            expect(Fired3).to.equal(false)
            Server:SetUsingPathArray({"One"}, 200)
            expect(Fired1).to.equal(true)
            expect(Fired2).to.equal(true)
            expect(Fired3).to.equal(false)
        end)

        it("should delete values when nil is passed", function()
            local Client, Server = GetTestObject()
            Server:SetUsingPathArray({"HHH", "B"}, true)

            expect(Server:GetUsingPathArray().HHH).to.be.ok()
            expect(Client:GetUsingPathArray().HHH).to.be.ok()
            expect(Server:GetUsingPathArray().HHH.B).to.be.ok()
            expect(Client:GetUsingPathArray().HHH.B).to.be.ok()

            Server:SetUsingPathArray({"HHH", "B"}, nil)

            expect(Server:GetUsingPathArray().HHH.B).never.to.be.ok()
            expect(Client:GetUsingPathArray().HHH.B).never.to.be.ok()

            expect(Equivalent(Client:GetUsingPathArray(), Server:GetUsingPathArray())).to.equal(true)
        end)
    end)

    describe("ReplicatedStore.Merge", function()
        it("should batch merges correctly with value creation", function()
            local Client, Server = GetTestObject()
            Server.DeferFunction = function(Func)
                task.delay(0.1, Func)
            end

            Server:Merge({
                X = {
                    P = 1;
                };
            })
            Server:Merge({
                X = {
                    Q = 1;
                };
            })
            Server:Merge({
                X = {
                    R = 1;
                };
            })

            expect(Server:GetUsingPathArray().X.P).to.equal(1)
            expect(Server:GetUsingPathArray().X.Q).to.equal(1)
            expect(Server:GetUsingPathArray().X.R).to.equal(1)

            expect(Client:GetUsingPathArray().X).to.equal(nil)

            expect(Equivalent(Client:GetUsingPathArray(), Server:GetUsingPathArray())).to.equal(false)

            task.wait(0.1)

            expect(Server:GetUsingPathArray().X.P).to.equal(1)
            expect(Server:GetUsingPathArray().X.Q).to.equal(1)
            expect(Server:GetUsingPathArray().X.R).to.equal(1)
            expect(Client:GetUsingPathArray().X.P).to.equal(1)
            expect(Client:GetUsingPathArray().X.Q).to.equal(1)
            expect(Client:GetUsingPathArray().X.R).to.equal(1)

            expect(Equivalent(Client:GetUsingPathArray(), Server:GetUsingPathArray())).to.equal(true)
        end)
    end)

    describe("ReplicatedStore.Get", function()
        it("should return the main table with no arguments", function()
            local Client, Server = GetTestObject()
            expect(Client:GetUsingPathArray()).to.equal(Client:GetUsingPathArray())
            expect(Server:GetUsingPathArray()).to.equal(Server:GetUsingPathArray())
        end)

        it("should return nil for paths which do not exist", function()
            local Client, Server = GetTestObject()
            expect(Client:GetUsingPathArray({"A", "B"})).never.to.be.ok()
            expect(Server:GetUsingPathArray({"A", "B"})).never.to.be.ok()
        end)
    end)

    describe("ReplicatedStore.SetUsingPathArray, ReplicatedStore.GetUsingPathArray", function()
        it("should correctly retrieve flat values", function()
            local Client, Server = GetTestObject()
            expect(Client:GetUsingPathArray({"A"})).never.to.be.ok()
            Server:SetUsingPathArray({"A"}, true)
            expect(Client:GetUsingPathArray({"A"})).to.be.ok()
        end)

        it("should correctly retrieve nested values", function()
            local Client, Server = GetTestObject()
            expect(Client:GetUsingPathArray({"A", "B", "C"})).never.to.be.ok()
            Server:SetUsingPathArray({"A", "B", "C"}, true)
            expect(Client:GetUsingPathArray({"A", "B", "C"})).to.be.ok()
        end)
    end)

    describe("ReplicatedStore.Await", function()
        it("should return if value is already present", function()
            local Client, Server = GetTestObject()
            Server:SetUsingPathArray({"A"}, 1)
            expect(Client:AwaitUsingPathArray({"A"})).to.equal(1)
        end)

        it("should return if value is already present on the server", function()
            local Client, Server = GetTestObject()
            Server:SetUsingPathArray({"A"}, 1)
            expect(Server:AwaitUsingPathArray({"A"})).to.equal(1)
        end)

        it("should await a flat value", function()
            local WAIT_TIME = 0.2
            local Client, Server = GetTestObject()

            task.spawn(function()
                task.wait(WAIT_TIME)
                Server:SetUsingPathArray({"A"}, 1)
            end)

            local Time = os.clock()
            expect(Client:AwaitUsingPathArray({"A"})).to.equal(1)
            expect(os.clock() - Time >= WAIT_TIME).to.equal(true)
        end)

        it("should await a flat value on the server", function()
            local WAIT_TIME = 0.2
            local Client, Server = GetTestObject()

            task.spawn(function()
                task.wait(WAIT_TIME)
                Server:SetUsingPathArray({"A"}, 1)
            end)

            local Time = os.clock()
            expect(Server:AwaitUsingPathArray({"A"})).to.equal(1)
            expect(os.clock() - Time >= WAIT_TIME).to.equal(true)
        end)

        it("should await a deep value", function()
            local WAIT_TIME = 0.2
            local Client, Server = GetTestObject()

            task.spawn(function()
                task.wait(WAIT_TIME)
                Server:SetUsingPathArray({"A", "B", "C"}, 1)
            end)

            local Time = os.clock()
            expect(Client:AwaitUsingPathArray({"A", "B", "C"})).to.equal(1)
            expect(os.clock() - Time >= WAIT_TIME).to.equal(true)
        end)

        it("should await a deep value on the server", function()
            local WAIT_TIME = 0.2
            local Client, Server = GetTestObject()

            task.spawn(function()
                task.wait(WAIT_TIME)
                Server:SetUsingPathArray({"A", "B", "C"}, 1)
            end)

            local Time = os.clock()
            expect(Server:AwaitUsingPathArray({"A", "B", "C"})).to.equal(1)
            expect(os.clock() - Time >= WAIT_TIME).to.equal(true)
        end)

        it("should await a values in sub-tables", function()
            local WAIT_TIME = 0.2
            local Client, Server = GetTestObject()

            task.spawn(function()
                task.wait(WAIT_TIME)
                Server:SetUsingPathArray({"A", "B"}, {
                    TEST = 1;
                })
                Server:SetUsingPathArray({"C"}, {
                    D = 2;
                })
            end)

            local Time = os.clock()

            task.spawn(function()
                expect(Client:AwaitUsingPathArray({"A", "B", "TEST"})).to.equal(1)
            end)

            expect(Client:AwaitUsingPathArray({"C", "D"})).to.equal(2)
            expect(os.clock() - Time >= WAIT_TIME).to.equal(true)
        end)

        it("should await a values in sub-tables on server", function()
            local WAIT_TIME = 0.2
            local Client, Server = GetTestObject()

            task.spawn(function()
                task.wait(WAIT_TIME)
                Server:SetUsingPathArray({"A", "B"}, {
                    TEST = 1;
                })
                Server:SetUsingPathArray({"C"}, {
                    D = 2;
                })
            end)

            local Time = os.clock()

            task.spawn(function()
                expect(Server:AwaitUsingPathArray({"A", "B", "TEST"})).to.equal(1)
            end)

            expect(Server:AwaitUsingPathArray({"C", "D"})).to.equal(2)
            expect(os.clock() - Time >= WAIT_TIME).to.equal(true)
        end)

        it("should timeout", function()
            local TIMEOUT = 0.2
            local Client, _Server = GetTestObject()

            local Time = os.clock()

            expect(pcall(function()
                Client:AwaitUsingPathArray({"A"}, TIMEOUT)
            end)).to.equal(false)

            expect(os.clock() - Time >= TIMEOUT).to.equal(true)
        end)
    end)
end