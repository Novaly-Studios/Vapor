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

        Server:InitServer()
        Client:InitClient()

        return Client, Server
    end

    -- Checks if two tables are equal
    local function Equivalent(Initial, Other)
        if (Initial == nil or Other == nil) then
            return false
        end

        for Key, Value in Initial do
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

            Server:InitServer()

            Server:Set({"A"}, true)
            Server:Set({"B", "C"}, 1000)
            Server:Set({"B", "C"}, 1125)

            Client:InitClient()

            expect(Client:Get().A).to.be.ok()
            expect(Client:Get().B).to.be.ok()
            expect(Client:Get().B.C).to.be.ok()

            expect(Client:Get().A).to.equal(true)
            expect(Client:Get().B.C).to.equal(1125)
        end)

        it("should set flat values", function()
            local Client, Server = GetTestObject()
            Server:Set({"A"}, true)
            Server:Set({"B"}, true)

            expect(Server:Get().A).to.equal(true)
            expect(Client:Get().A).to.equal(true)

            expect(Server:Get().B).to.equal(true)
            expect(Client:Get().B).to.equal(true)

            expect(Equivalent(Client:Get(), Server:Get())).to.equal(true)
        end)

        it("should set flat value 'false'", function()
            local Client, Server = GetTestObject()
            Server:Set({"A"}, false)
            Server:Set({"B"}, false)

            expect(Server:Get().A).to.equal(false)
            expect(Client:Get().A).to.equal(false)

            expect(Server:Get().B).to.equal(false)
            expect(Client:Get().B).to.equal(false)

            expect(Equivalent(Client:Get(), Server:Get())).to.equal(true)
        end)

        it("should set deep values", function()
            local Client, Server = GetTestObject()
            Server:Set({"A", "B", "C"}, 100)

            expect(Server:Get().A.B.C).to.equal(100)
            expect(Client:Get().A.B.C).to.equal(100)

            expect(Equivalent(Client:Get(), Server:Get())).to.equal(true)
        end)

        it("should throw on empty path i.e. root overwrite", function()
            local Client, Server = GetTestObject()

            expect(function()
                Server:Set({}, 100)
            end).to.throw()
        end)

        it("should set flat values in order", function()
            local Client, Server = GetTestObject()
            Server:Set({"A"}, true)
            Server:Set({"A"}, 9000)

            Server:Set({"B"}, true)
            Server:Set({"B"}, 1000)

            expect(Server:Get().A).to.equal(9000)
            expect(Client:Get().A).to.equal(9000)

            expect(Server:Get().B).to.equal(1000)
            expect(Client:Get().B).to.equal(1000)

            expect(Equivalent(Client:Get(), Server:Get())).to.equal(true)
        end)

        it("should set deep values in order", function()
            local Client, Server = GetTestObject()
            Server:Set({"A", "B", "C"}, 100)

            expect(Server:Get().A.B.C).to.equal(100)
            expect(Client:Get().A.B.C).to.equal(100)

            expect(Equivalent(Client:Get(), Server:Get())).to.equal(true)
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

                Server:Set(Path, FinalValue)
            end

            expect(Equivalent(Client:Get(), Server:Get())).to.equal(true)
        end)

        it("should convert keys to numeric when applicable", function()
            local Client, Server = GetTestObject()
            Server:Set({1, "201", "AHHH"}, true)

            expect(Client:Get()[1]).to.be.ok()
            expect(Client:Get()[1][201]).to.be.ok()
            expect(Client:Get()[1][201].AHHH).to.be.ok()

            expect(Equivalent(Client:Get(), Server:Get())).to.equal(true)
        end)

        it("should not allow mixed keys", function()
            local Client, Server = GetTestObject()

            expect(function()
                Server:Set({1}, true)
                Server:Set({"a"}, true)
            end).to.throw()

            expect(function()
                Server:Set({"a"}, true)
                Server:Set({1}, true)
            end).to.throw()
        end)

        it("should trigger await events for tables being overwritten by atoms", function()
            local Client, Server = GetTestObject()

            Server:Set({"One", "Two", "Three"}, true)

            local Fired1 = false
            local Fired2 = false
            local Fired3 = false

            Server:GetValueChangedSignal({"One", "Two", "Three", "Four"}):Connect(function(Value)
                -- Shouldn't fire for non-existent nodes
                Fired3 = true
            end)

            Server:GetValueChangedSignal({"One", "Two", "Three"}):Connect(function(Value)
                expect(Value).to.equal(nil)
                Fired1 = true
            end)

            Server:GetValueChangedSignal({"One"}):Connect(function(Value)
                expect(Value).to.equal(200)
                Fired2 = true
            end)

            expect(Fired1).to.equal(false)
            expect(Fired2).to.equal(false)
            expect(Fired3).to.equal(false)
            Server:Set({"One"}, 200)
            expect(Fired1).to.equal(true)
            expect(Fired2).to.equal(true)
            expect(Fired3).to.equal(false)
        end)

        it("should delete values when nil is passed", function()
            local Client, Server = GetTestObject()
            Server:Set({"HHH", "B"}, true)

            expect(Server:Get().HHH).to.be.ok()
            expect(Client:Get().HHH).to.be.ok()
            expect(Server:Get().HHH.B).to.be.ok()
            expect(Client:Get().HHH.B).to.be.ok()

            Server:Set({"HHH", "B"}, nil)

            expect(Server:Get().HHH.B).never.to.be.ok()
            expect(Client:Get().HHH.B).never.to.be.ok()

            expect(Equivalent(Client:Get(), Server:Get())).to.equal(true)
        end)
    end)

    describe("ReplicatedStore.Get", function()
        it("should return the main table with no arguments", function()
            local Client, Server = GetTestObject()
            expect(Client:Get()).to.equal(Client:Get())
            expect(Server:Get()).to.equal(Server:Get())
        end)

        it("should return nil for paths which do not exist", function()
            local Client, Server = GetTestObject()
            expect(Client:Get({"A", "B"})).never.to.be.ok()
            expect(Server:Get({"A", "B"})).never.to.be.ok()
        end)
    end)

    describe("ReplicatedStore.Set, ReplicatedStore.Get", function()
        it("should correctly retrieve flat values", function()
            local Client, Server = GetTestObject()
            expect(Client:Get({"A"})).never.to.be.ok()
            Server:Set({"A"}, true)
            expect(Client:Get({"A"})).to.be.ok()
        end)

        it("should correctly retrieve nested values", function()
            local Client, Server = GetTestObject()
            expect(Client:Get({"A", "B", "C"})).never.to.be.ok()
            Server:Set({"A", "B", "C"}, true)
            expect(Client:Get({"A", "B", "C"})).to.be.ok()
        end)

        --[[ it("should serialize a numberic index larger than int32 range", function()
            -- Only disable if FIX_FLOAT_KEYS == true
            local Client, Server = GetTestObject()
            Server:Set({10^24}, true)
            expect(Client:Get({10^24})).to.be.ok()
        end) ]]

        --[[ it("should serialize a large numberic index in nested keys", function()
            -- Only disable if FIX_FLOAT_KEYS == true
            local Client, Server = GetTestObject()
            Server:Set({"A"}, {
                {
                    {
                        {
                            [10^24] = true;
                        }
                    }
                }
            })
            expect(Client:Get({"A", 1, 1, 1, 10^24})).to.be.ok()
        end) ]]
    end)

    describe("ReplicatedStore.Await", function()
        it("should return if value is already present", function()
            local Client, Server = GetTestObject()
            Server:Set({"A"}, 1)
            expect(Client:Await({"A"})).to.equal(1)
        end)

        it("should return if value is already present on the server", function()
            local Client, Server = GetTestObject()
            Server:Set({"A"}, 1)
            expect(Server:Await({"A"})).to.equal(1)
        end)

        it("should await a flat value", function()
            local WAIT_TIME = 0.2
            local Client, Server = GetTestObject()

            task.spawn(function()
                task.wait(WAIT_TIME)
                Server:Set({"A"}, 1)
            end)

            local Time = os.clock()
            expect(Client:Await({"A"})).to.equal(1)
            expect(os.clock() - Time >= WAIT_TIME).to.equal(true)
        end)

        it("should await a flat value on the server", function()
            local WAIT_TIME = 0.2
            local Client, Server = GetTestObject()

            task.spawn(function()
                task.wait(WAIT_TIME)
                Server:Set({"A"}, 1)
            end)

            local Time = os.clock()
            expect(Server:Await({"A"})).to.equal(1)
            expect(os.clock() - Time >= WAIT_TIME).to.equal(true)
        end)

        it("should await a deep value", function()
            local WAIT_TIME = 0.2
            local Client, Server = GetTestObject()

            task.spawn(function()
                task.wait(WAIT_TIME)
                Server:Set({"A", "B", "C"}, 1)
            end)

            local Time = os.clock()
            expect(Client:Await({"A", "B", "C"})).to.equal(1)
            expect(os.clock() - Time >= WAIT_TIME).to.equal(true)
        end)

        it("should await a deep value on the server", function()
            local WAIT_TIME = 0.2
            local Client, Server = GetTestObject()

            task.spawn(function()
                task.wait(WAIT_TIME)
                Server:Set({"A", "B", "C"}, 1)
            end)

            local Time = os.clock()
            expect(Server:Await({"A", "B", "C"})).to.equal(1)
            expect(os.clock() - Time >= WAIT_TIME).to.equal(true)
        end)

        it("should await a values in sub-tables", function()
            local WAIT_TIME = 0.2
            local Client, Server = GetTestObject()

            task.spawn(function()
                task.wait(WAIT_TIME)
                Server:Set({"A", "B"}, {
                    TEST = 1;
                })
                Server:Set({"C"}, {
                    D = 2;
                })
            end)

            local Time = os.clock()

            task.spawn(function()
                expect(Client:Await({"A", "B", "TEST"})).to.equal(1)
            end)

            expect(Client:Await({"C", "D"})).to.equal(2)
            expect(os.clock() - Time >= WAIT_TIME).to.equal(true)
        end)

        it("should await a values in sub-tables on server", function()
            local WAIT_TIME = 0.2
            local Client, Server = GetTestObject()

            task.spawn(function()
                task.wait(WAIT_TIME)
                Server:Set({"A", "B"}, {
                    TEST = 1;
                })
                Server:Set({"C"}, {
                    D = 2;
                })
            end)

            local Time = os.clock()

            task.spawn(function()
                expect(Server:Await({"A", "B", "TEST"})).to.equal(1)
            end)

            expect(Server:Await({"C", "D"})).to.equal(2)
            expect(os.clock() - Time >= WAIT_TIME).to.equal(true)
        end)

        it("should timeout", function()
            local TIMEOUT = 0.2
            local Client, _Server = GetTestObject()

            local Time = os.clock()

            expect(pcall(function()
                Client:Await({"A"}, TIMEOUT)
            end)).to.equal(false)

            expect(os.clock() - Time >= TIMEOUT).to.equal(true)
        end)
    end)
end