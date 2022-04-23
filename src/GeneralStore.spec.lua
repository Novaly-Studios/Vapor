return function()
    local Store = require(script.Parent:WaitForChild("GeneralStore"))

    local function GetTestObject()
        return Store.new()
    end

    -- Checks if two tables are equal
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

    describe("Store.new", function()
        it("should construct", function()
            expect(function()
                GetTestObject()
            end).never.to.throw()
        end)
    end)

    describe("Store.Set", function()
        it("should set flat values", function()
            local TestStore = GetTestObject()
            TestStore:Set({"A"}, true)
            expect(TestStore._Store.A).to.equal(true)
        end)

        it("should set flat value 'false'", function()
            local TestStore = GetTestObject()
            TestStore:Set({"A"}, false)
            expect(TestStore._Store.A).to.equal(false)
        end)

        it("should set deep values", function()
            local TestStore = GetTestObject()
            TestStore:Set({"A", "B", "C"}, 100)
            expect(TestStore._Store.A.B.C).to.equal(100)
        end)

        it("should throw on empty path i.e. root overwrite", function()
            local TestStore = GetTestObject()

            expect(function()
                TestStore:Set({}, 100)
            end).to.throw()
        end)

        it("should set flat values in order", function()
            local TestStore = GetTestObject()
            TestStore:Set({"A"}, true)
            TestStore:Set({"A"}, 9000)

            TestStore:Set({"B"}, true)
            TestStore:Set({"B"}, 1000)

            expect(TestStore._Store.A).to.equal(9000)
            expect(TestStore._Store.B).to.equal(1000)
        end)

        it("should set deep values in order", function()
            local TestStore = GetTestObject()
            TestStore:Set({"A", "B", "C"}, 100)
            expect(TestStore._Store.A.B.C).to.equal(100)
        end)

        it("should not allow mixed keys", function()
            local TestStore = GetTestObject()

            expect(function()
                TestStore:Set({1}, true)
                TestStore:Set({"a"}, true)
            end).to.throw()

            expect(function()
                TestStore:Set({"a"}, true)
                TestStore:Set({1}, true)
            end).to.throw()
        end)

        it("should trigger await events for tables being overwritten by atoms", function()
            local TestStore = GetTestObject()

            TestStore:Set({"One", "Two", "Three"}, true)

            local Fired1 = false
            local Fired2 = false
            local Fired3 = false

            TestStore:GetValueChangedSignal({"One", "Two", "Three", "Four"}):Connect(function(Value)
                -- Shouldn't fire for non-existent nodes
                Fired3 = true
            end)

            TestStore:GetValueChangedSignal({"One", "Two", "Three"}):Connect(function(Value)
                expect(Value).to.equal(nil)
                Fired1 = true
            end)

            TestStore:GetValueChangedSignal({"One"}):Connect(function(Value)
                expect(Value).to.equal(200)
                Fired2 = true
            end)

            expect(Fired1).to.equal(false)
            expect(Fired2).to.equal(false)
            expect(Fired3).to.equal(false)
            TestStore:Set({"One"}, 200)
            expect(Fired1).to.equal(true)
            expect(Fired2).to.equal(true)
            expect(Fired3).to.equal(false)
        end)

        it("should overwrite instead of merge table values", function()
            local TestStore = GetTestObject()

            TestStore:Merge({
                A = {
                    B = {
                        C = 2
                    }
                }
            })

            TestStore:Set({"A"}, {
                B = {};
            })

            expect(next(TestStore:Get().A.B)).to.equal(nil)
        end)
    end)

    describe("Store.Merge", function()
        it("should change nothing given an empty table", function()
            local TestStore = GetTestObject()
            expect(next(TestStore:Get())).to.equal(nil)
        end)

        it("should merge a flat value", function()
            local TestStore = GetTestObject()
            TestStore:Merge({
                A = 123;
            })

            expect(TestStore:Get().A).to.be.ok()
            expect(TestStore:Get().A).to.equal(123)

            expect(Equivalent(TestStore:Get(), {
                A = 123;
            })).to.equal(true)
        end)

        it("should merge multiple flat values", function()
            local TestStore = GetTestObject()
            TestStore:Merge({
                A = 123;
                B = 456;
            })

            expect(TestStore:Get().A).to.be.ok()
            expect(TestStore:Get().A).to.equal(123)

            expect(TestStore:Get().B).to.be.ok()
            expect(TestStore:Get().B).to.equal(456)

            expect(Equivalent(TestStore:Get(), {
                A = 123;
                B = 456;
            })).to.equal(true)
        end)

        it("should merge flat multiple times", function()
            local TestStore = GetTestObject()
            TestStore:Merge({
                A = 123;
            })
            TestStore:Merge({
                B = 456;
            })

            expect(TestStore:Get().A).to.be.ok()
            expect(TestStore:Get().A).to.equal(123)

            expect(TestStore:Get().B).to.be.ok()
            expect(TestStore:Get().B).to.equal(456)

            expect(Equivalent(TestStore:Get(), {
                A = 123;
                B = 456;
            })).to.equal(true)
        end)

        it("should merge flat multiple times with overwrites", function()
            local TestStore = GetTestObject()
            TestStore:Merge({
                A = 123;
            })
            TestStore:Merge({
                A = 789;
                B = 456;
            })

            expect(TestStore:Get().A).to.be.ok()
            expect(TestStore:Get().A).to.equal(789)

            expect(TestStore:Get().B).to.be.ok()
            expect(TestStore:Get().B).to.equal(456)

            expect(Equivalent(TestStore:Get(), {
                A = 789;
                B = 456;
            })).to.equal(true)
        end)

        it("should merge a deep value", function()
            local TestStore = GetTestObject()
            TestStore:Merge({
                A = {
                    B = {
                        C = 10;
                    };
                };
            })

            expect(TestStore:Get().A).to.be.ok()
            expect(TestStore:Get().A.B).to.be.ok()
            expect(TestStore:Get().A.B.C).to.be.ok()
            expect(TestStore:Get().A.B.C).to.equal(10)

            expect(Equivalent(TestStore:Get(), {
                A = {
                    B = {
                        C = 10;
                    };
                };
            })).to.equal(true)
        end)

        it("should merge multiple deep values", function()
            local TestStore = GetTestObject()
            TestStore:Merge({
                A = {
                    B = {
                        C = 10;
                    };
                };
            })

            TestStore:Merge({
                A = {
                    B = {
                        D = 20;
                    };
                    E = 30;
                };
            })

            expect(TestStore:Get().A).to.be.ok()
            expect(TestStore:Get().A.B).to.be.ok()
            expect(TestStore:Get().A.B.C).to.be.ok()
            expect(TestStore:Get().A.B.C).to.equal(10)
            expect(TestStore:Get().A.E).to.be.ok()
            expect(TestStore:Get().A.E).to.equal(30)
            expect(TestStore:Get().A.B.D).to.be.ok()
            expect(TestStore:Get().A.B.D).to.equal(20)

            expect(Equivalent(TestStore:Get(), {
                A = {
                    B = {
                        C = 10;
                        D = 20;
                    };
                    E = 30;
                };
            })).to.equal(true)
        end)

        it("should merge multiple deep values with overwrites", function()
            local TestStore = GetTestObject()
            TestStore:Merge({
                A = {
                    B = {
                        C = 10;
                    };
                };
            })

            TestStore:Merge({
                A = {
                    B = {
                        D = 20;
                        C = 40;
                    };
                    E = 30;
                };
            })

            expect(TestStore:Get().A).to.be.ok()
            expect(TestStore:Get().A.B).to.be.ok()
            expect(TestStore:Get().A.B.C).to.be.ok()
            expect(TestStore:Get().A.B.C).to.equal(40)
            expect(TestStore:Get().A.E).to.be.ok()
            expect(TestStore:Get().A.E).to.equal(30)
            expect(TestStore:Get().A.B.D).to.be.ok()
            expect(TestStore:Get().A.B.D).to.equal(20)

            expect(Equivalent(TestStore:Get(), {
                A = {
                    B = {
                        C = 40;
                        D = 20;
                    };
                    E = 30;
                };
            })).to.equal(true)
        end)

        it("should remove a flat atom", function()
            local TestStore = GetTestObject()
            TestStore:Merge({
                A = 20;
            })

            expect(TestStore:Get().A).to.be.ok()

            TestStore:Merge({
                A = Store._REMOVE_NODE;
            })

            expect(TestStore:Get().A).never.to.be.ok()
        end)

        it("should remove a structure on a flat level", function()
            local TestStore = GetTestObject()
            TestStore:Merge({
                A = {
                    B = 10;
                };
            })

            expect(TestStore:Get().A).to.be.ok()

            TestStore:Merge({
                A = Store._REMOVE_NODE;
            })

            expect(TestStore:Get().A).never.to.be.ok()
        end)

        it("should remove a nested atom", function()
            local TestStore = GetTestObject()
            TestStore:Merge({
                A = {
                    B = 10;
                };
            })

            expect(TestStore:Get().A).to.be.ok()

            TestStore:Merge({
                A = {
                    B = Store._REMOVE_NODE;
                };
            })

            expect(TestStore:Get().A).to.be.ok()
            expect(TestStore:Get().A.B).never.to.be.ok()
        end)

        it("should remove a nested structure", function()
            local TestStore = GetTestObject()
            TestStore:Merge({
                A = {
                    B = {
                        C = 10;
                    };
                };
            })

            expect(TestStore:Get().A).to.be.ok()
            expect(TestStore:Get().A.B).to.be.ok()
            expect(TestStore:Get().A.B.C).to.be.ok()

            TestStore:Merge({
                A = {
                    B = Store._REMOVE_NODE;
                };
            })

            expect(TestStore:Get().A).to.be.ok()
            expect(TestStore:Get().A.B).never.to.be.ok()
        end)
    end)

    describe("Store.Get", function()
        it("should return the main table with no arguments", function()
            local TestStore = GetTestObject()
            expect(TestStore:Get()).to.equal(TestStore._Store)
        end)

        it("should return nil for paths which do not exist", function()
            local TestStore = GetTestObject()
            expect(TestStore:Get({"A", "B"})).never.to.be.ok()
            expect(TestStore:Get({"A", "B"})).never.to.be.ok()
        end)
    end)

    describe("Store.Await", function()
        it("should return if value is already present", function()
            local TestStore = GetTestObject()
            TestStore:Set({"A"}, 1)
            expect(TestStore:Await({"A"})).to.equal(1)
        end)

        it("should await a flat value", function()
            local WAIT_TIME = 0.2
            local TestStore = GetTestObject()

            task.spawn(function()
                task.wait(WAIT_TIME)
                TestStore:Set({"A"}, 1)
            end)

            local Time = os.clock()
            expect(TestStore:Await({"A"})).to.equal(1)
            expect(os.clock() - Time >= WAIT_TIME).to.equal(true)
        end)

        it("should await a deep value", function()
            local WAIT_TIME = 0.2
            local TestStore = GetTestObject()

            task.spawn(function()
                task.wait(WAIT_TIME)
                TestStore:Set({"A", "B", "C"}, 1)
            end)

            local Time = os.clock()
            expect(TestStore:Await({"A", "B", "C"})).to.equal(1)
            expect(os.clock() - Time >= WAIT_TIME).to.equal(true)
        end)

        it("should bump up and down the reference counters", function()
            local WAIT_TIME = 0.2
            local TestStore = GetTestObject()

            task.spawn(function()
                task.wait(WAIT_TIME)
                TestStore:Set({"A", "B", "C"}, 1)
            end)

            expect(TestStore:_GetAwaitingCount({"A", "B", "C"})).never.to.be.ok()
            expect(TestStore:_RawGetValueChangedSignal({"A", "B", "C"})).never.to.be.ok()

            task.spawn(function()
                expect(TestStore:Await({"A", "B", "C"})).to.equal(1)
                expect(TestStore:_RawGetValueChangedSignal({"A", "B", "C"})).never.to.be.ok()
                expect(TestStore:_GetAwaitingCount({"A", "B", "C"})).never.to.be.ok()
            end)

            expect(TestStore:_GetAwaitingCount({"A", "B", "C"}) == 1).to.equal(true)
            expect(TestStore:_RawGetValueChangedSignal({"A", "B", "C"})).to.be.ok()

            task.wait(WAIT_TIME)
        end)

        it("should bump up and down the reference counters on multiple coroutines", function()
            local WAIT_TIME = 0.2
            local TestStore = GetTestObject()

            task.spawn(function()
                task.wait(WAIT_TIME)
                TestStore:Set({"A", "B", "C"}, 1)
            end)

            expect(TestStore:_GetAwaitingCount({"A", "B", "C"})).never.to.be.ok()
            expect(TestStore:_RawGetValueChangedSignal({"A", "B", "C"})).never.to.be.ok()

            local Completed = 0

            task.spawn(function()
                expect(TestStore:Await({"A", "B", "C"})).to.equal(1)
                Completed += 1
            end)

            task.spawn(function()
                expect(TestStore:Await({"A", "B", "C"})).to.equal(1)
                Completed += 1
            end)

            expect(TestStore:_GetAwaitingCount({"A", "B", "C"}) == 2).to.equal(true)
            expect(TestStore:_RawGetValueChangedSignal({"A", "B", "C"})).to.be.ok()

            while (Completed < 2) do
                task.wait(0.05)
            end

            expect(TestStore:_GetAwaitingCount({"A", "B", "C"})).never.to.be.ok()
            expect(TestStore:_RawGetValueChangedSignal({"A", "B", "C"})).never.to.be.ok()
        end)

        it("should bump up and down the reference counters on timeout", function()
            local WAIT_TIME = 0.2
            local TestStore = GetTestObject()

            -- TestStore
            expect(TestStore:_GetAwaitingCount({"A", "B", "C"})).never.to.be.ok()
            expect(TestStore:_RawGetValueChangedSignal({"A", "B", "C"})).never.to.be.ok()

            task.spawn(function()
                expect(pcall(function()
                    TestStore:Await({"A", "B", "C"}, WAIT_TIME)
                end)).to.equal(false)

                expect(TestStore:_RawGetValueChangedSignal({"A", "B", "C"})).never.to.be.ok()
                expect(TestStore:_GetAwaitingCount({"A", "B", "C"})).never.to.be.ok()
            end)

            expect(TestStore:_GetAwaitingCount({"A", "B", "C"}) == 1).to.equal(true)
            expect(TestStore:_RawGetValueChangedSignal({"A", "B", "C"})).to.be.ok()

            task.wait(WAIT_TIME)
        end)

        it("should bump up and down the reference counters on multiple coroutines on timeout", function()
            local WAIT_TIME = 0.2
            local TestStore = GetTestObject()

            task.spawn(function()
                task.wait(WAIT_TIME)
                TestStore:Set({"A", "B", "C"}, 1)
            end)

            expect(TestStore:_GetAwaitingCount({"A", "B", "C"})).never.to.be.ok()
            expect(TestStore:_RawGetValueChangedSignal({"A", "B", "C"})).never.to.be.ok()

            task.spawn(function()
                TestStore:Await({"A", "B", "C"})
            end)

            task.spawn(function()
                TestStore:Await({"A", "B", "C"})
            end)

            expect(TestStore:_GetAwaitingCount({"A", "B", "C"}) == 2).to.equal(true)
            expect(TestStore:_RawGetValueChangedSignal({"A", "B", "C"})).to.be.ok()

            task.wait(WAIT_TIME)

            expect(TestStore:_GetAwaitingCount({"A", "B", "C"})).never.to.be.ok()
            expect(TestStore:_RawGetValueChangedSignal({"A", "B", "C"})).never.to.be.ok()
        end)

        it("should await a values in sub-tables", function()
            local WAIT_TIME = 0.2
            local TestStore = GetTestObject()

            task.spawn(function()
                task.wait(WAIT_TIME)
                TestStore:Set({"A", "B"}, {
                    TEST = 1;
                })
                TestStore:Set({"C"}, {
                    D = 2;
                })
            end)

            local Time = os.clock()

            task.spawn(function()
                expect(TestStore:Await({"A", "B", "TEST"})).to.equal(1)
            end)

            expect(TestStore:Await({"C", "D"})).to.equal(2)
            expect(os.clock() - Time >= WAIT_TIME).to.equal(true)
        end)

        it("should timeout", function()
            local TIMEOUT = 0.2
            local TestStore = GetTestObject()

            local Time = os.clock()

            expect(pcall(function()
                TestStore:Await({"A"}, TIMEOUT)
            end)).to.equal(false)

            expect(os.clock() - Time >= TIMEOUT).to.equal(true)
        end)
    end)

    describe("Store.GetValueChangedSignal", function()
        it("should increment ref count on creation", function()
            local TestStore = GetTestObject()
            expect(TestStore:_GetAwaitingCount({"A"})).never.to.be.ok()

            TestStore:GetValueChangedSignal({"A"})
            expect(TestStore:_GetAwaitingCount({"A"})).to.equal(1)
            TestStore:GetValueChangedSignal({"A"})
            expect(TestStore:_GetAwaitingCount({"A"})).to.equal(2)
        end)

        it("should fire correctly", function()
            local TestStore = GetTestObject()
            local Value

            TestStore:GetValueChangedSignal({"A"}):Connect(function(NewValue)
                Value = NewValue
            end)

            expect(Value).never.to.be.ok()
            TestStore:Set({"A"}, 20)
            expect(Value).to.equal(20)
        end)

        it("should implement Wait() correctly", function()
            local TestStore = GetTestObject()
            local Value

            task.spawn(function()
                Value = TestStore:GetValueChangedSignal({"A"}):Wait()
            end)

            expect(Value).never.to.be.ok()
            TestStore:Set({"A"}, 20)
            expect(Value).to.equal(20)
        end)

        it("should release ref count on disconnect", function()
            local TestStore = GetTestObject()

            expect(TestStore:_GetAwaitingCount({"A"})).never.to.be.ok()
            expect(TestStore:_GetAwaitingCount({"A"})).never.to.be.ok()

            local TestStoreConnection1 = TestStore:GetValueChangedSignal({"A"}):Connect(function() end)
            local TestStoreConnection2 = TestStore:GetValueChangedSignal({"A"}):Connect(function() end)

            expect(TestStore:_GetAwaitingCount({"A"})).to.equal(2)
            TestStoreConnection1:Disconnect()
            expect(TestStore:_GetAwaitingCount({"A"})).to.equal(1)
            TestStoreConnection2:Disconnect()
            expect(TestStore:_GetAwaitingCount({"A"})).never.to.be.ok()
        end)
    end)

    describe("Store.Merge", function()
        it("should set a flat value", function()
            local TestStore = GetTestObject()

            TestStore:Merge({
                A = 1;
            })

            expect(TestStore:Get({"A"})).to.equal(1)
        end)

        it("should overwrite a flat value", function()
            local TestStore = GetTestObject()

            TestStore:Merge({
                A = 1;
            })

            TestStore:Merge({
                A = 5;
            })

            expect(TestStore:Get({"A"})).to.equal(5)
        end)
    end)
end