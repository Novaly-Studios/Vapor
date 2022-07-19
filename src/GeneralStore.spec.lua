return function()
    local GeneralStore = require(script.Parent:WaitForChild("GeneralStore"))
    local Shared = require(script.Parent:WaitForChild("Shared"))

    local function GetTestObject()
        local Result = GeneralStore.new()
        return Result, Result
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

    describe("new", function()
        it("should construct", function()
            expect(function()
                GetTestObject()
            end).never.to.throw()
        end)
    end)

    describe("SetUsingPathArray", function()
        it("should set flat values", function()
            local TestStore = GetTestObject()
            TestStore:SetUsingPathArray({"A"}, true)
            expect(TestStore._Store.A).to.equal(true)
        end)

        it("should set flat value 'false'", function()
            local TestStore = GetTestObject()
            TestStore:SetUsingPathArray({"A"}, false)
            expect(TestStore._Store.A).to.equal(false)
        end)

        it("should set deep values", function()
            local TestStore = GetTestObject()
            TestStore:SetUsingPathArray({"A", "B", "C"}, 100)
            expect(TestStore._Store.A.B.C).to.equal(100)
        end)

        it("should throw on empty path i.e. root overwrite", function()
            local TestStore = GetTestObject()

            expect(function()
                TestStore:SetUsingPathArray({}, 100)
            end).to.throw()
        end)

        it("should set flat values in order", function()
            local TestStore = GetTestObject()
            TestStore:SetUsingPathArray({"A"}, true)
            TestStore:SetUsingPathArray({"A"}, 9000)

            TestStore:SetUsingPathArray({"B"}, true)
            TestStore:SetUsingPathArray({"B"}, 1000)

            expect(TestStore._Store.A).to.equal(9000)
            expect(TestStore._Store.B).to.equal(1000)
        end)

        it("should set deep values in order", function()
            local TestStore = GetTestObject()
            TestStore:SetUsingPathArray({"A", "B", "C"}, 100)
            expect(TestStore._Store.A.B.C).to.equal(100)
        end)

        it("should not allow mixed keys", function()
            local TestStore = GetTestObject()

            expect(function()
                TestStore:SetUsingPathArray({1}, true)
                TestStore:SetUsingPathArray({"a"}, true)
            end).to.throw()

            expect(function()
                TestStore:SetUsingPathArray({"a"}, true)
                TestStore:SetUsingPathArray({1}, true)
            end).to.throw()
        end)

        it("should trigger await events for tables being overwritten by atoms", function()
            local TestStore = GetTestObject()

            TestStore:SetUsingPathArray({"One", "Two", "Three"}, true)

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
            TestStore:SetUsingPathArray({"One"}, 200)
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

            TestStore:SetUsingPathArray({"A"}, {
                B = {};
            })

            expect(next(TestStore:GetUsingPathArray().A.B)).to.equal(nil)
        end)
    end)

    describe("Merge", function()
        it("should change nothing given an empty table", function()
            local TestStore = GetTestObject()
            expect(next(TestStore:GetUsingPathArray())).to.equal(nil)
        end)

        it("should merge a flat value", function()
            local TestStore = GetTestObject()
            TestStore:Merge({
                A = 123;
            })

            expect(TestStore:GetUsingPathArray().A).to.be.ok()
            expect(TestStore:GetUsingPathArray().A).to.equal(123)

            expect(Equivalent(TestStore:GetUsingPathArray(), {
                A = 123;
            })).to.equal(true)
        end)

        it("should merge multiple flat values", function()
            local TestStore = GetTestObject()
            TestStore:Merge({
                A = 123;
                B = 456;
            })

            expect(TestStore:GetUsingPathArray().A).to.be.ok()
            expect(TestStore:GetUsingPathArray().A).to.equal(123)

            expect(TestStore:GetUsingPathArray().B).to.be.ok()
            expect(TestStore:GetUsingPathArray().B).to.equal(456)

            expect(Equivalent(TestStore:GetUsingPathArray(), {
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

            expect(TestStore:GetUsingPathArray().A).to.be.ok()
            expect(TestStore:GetUsingPathArray().A).to.equal(123)

            expect(TestStore:GetUsingPathArray().B).to.be.ok()
            expect(TestStore:GetUsingPathArray().B).to.equal(456)

            expect(Equivalent(TestStore:GetUsingPathArray(), {
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

            expect(TestStore:GetUsingPathArray().A).to.be.ok()
            expect(TestStore:GetUsingPathArray().A).to.equal(789)

            expect(TestStore:GetUsingPathArray().B).to.be.ok()
            expect(TestStore:GetUsingPathArray().B).to.equal(456)

            expect(Equivalent(TestStore:GetUsingPathArray(), {
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

            expect(TestStore:GetUsingPathArray().A).to.be.ok()
            expect(TestStore:GetUsingPathArray().A.B).to.be.ok()
            expect(TestStore:GetUsingPathArray().A.B.C).to.be.ok()
            expect(TestStore:GetUsingPathArray().A.B.C).to.equal(10)

            expect(Equivalent(TestStore:GetUsingPathArray(), {
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

            expect(TestStore:GetUsingPathArray().A).to.be.ok()
            expect(TestStore:GetUsingPathArray().A.B).to.be.ok()
            expect(TestStore:GetUsingPathArray().A.B.C).to.be.ok()
            expect(TestStore:GetUsingPathArray().A.B.C).to.equal(10)
            expect(TestStore:GetUsingPathArray().A.E).to.be.ok()
            expect(TestStore:GetUsingPathArray().A.E).to.equal(30)
            expect(TestStore:GetUsingPathArray().A.B.D).to.be.ok()
            expect(TestStore:GetUsingPathArray().A.B.D).to.equal(20)

            expect(Equivalent(TestStore:GetUsingPathArray(), {
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

            expect(TestStore:GetUsingPathArray().A).to.be.ok()
            expect(TestStore:GetUsingPathArray().A.B).to.be.ok()
            expect(TestStore:GetUsingPathArray().A.B.C).to.be.ok()
            expect(TestStore:GetUsingPathArray().A.B.C).to.equal(40)
            expect(TestStore:GetUsingPathArray().A.E).to.be.ok()
            expect(TestStore:GetUsingPathArray().A.E).to.equal(30)
            expect(TestStore:GetUsingPathArray().A.B.D).to.be.ok()
            expect(TestStore:GetUsingPathArray().A.B.D).to.equal(20)

            expect(Equivalent(TestStore:GetUsingPathArray(), {
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

            expect(TestStore:GetUsingPathArray().A).to.be.ok()

            TestStore:Merge({
                A = Shared.RemoveNode;
            })

            expect(TestStore:GetUsingPathArray().A).never.to.be.ok()
        end)

        it("should remove a structure on a flat level", function()
            local TestStore = GetTestObject()
            TestStore:Merge({
                A = {
                    B = 10;
                };
            })

            expect(TestStore:GetUsingPathArray().A).to.be.ok()

            TestStore:Merge({
                A = Shared.RemoveNode;
            })

            expect(TestStore:GetUsingPathArray().A).never.to.be.ok()
        end)

        it("should remove a nested atom", function()
            local TestStore = GetTestObject()
            TestStore:Merge({
                A = {
                    B = 10;
                };
            })

            expect(TestStore:GetUsingPathArray().A).to.be.ok()

            TestStore:Merge({
                A = {
                    B = Shared.RemoveNode;
                };
            })

            expect(TestStore:GetUsingPathArray().A).to.be.ok()
            expect(TestStore:GetUsingPathArray().A.B).never.to.be.ok()
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

            expect(TestStore:GetUsingPathArray().A).to.be.ok()
            expect(TestStore:GetUsingPathArray().A.B).to.be.ok()
            expect(TestStore:GetUsingPathArray().A.B.C).to.be.ok()

            TestStore:Merge({
                A = {
                    B = Shared.RemoveNode;
                };
            })

            expect(TestStore:GetUsingPathArray().A).to.be.ok()
            expect(TestStore:GetUsingPathArray().A.B).never.to.be.ok()
        end)
    end)

    describe("GetUsingPathString", function()
        it("should reject non-string paths", function()
            local TestStore = GetTestObject()

            expect(function()
                TestStore:GetUsingPathString({})
            end).to.throw()

            expect(function()
                TestStore:GetUsingPathString({"X"})
            end).to.throw()

            expect(function()
                TestStore:GetUsingPathString(1)
            end).to.throw()

            expect(function()
                TestStore:GetUsingPathString("Test")
            end).never.to.throw()
        end)

        it("should accept nil as the path", function()
            local TestStore = GetTestObject()

            expect(function()
                TestStore:GetUsingPathString(nil)
            end).never.to.throw()
        end)

        it("should obtain correct values after a flat merge & delete", function()
            local TestStore = GetTestObject()
            TestStore:Merge({
                X = 1;
                Y = 2;
                Z = 3;
            })

            expect(TestStore:GetUsingPathString("X^")).to.equal(1)
            expect(TestStore:GetUsingPathString("Y^")).to.equal(2)
            expect(TestStore:GetUsingPathString("Z^")).to.equal(3)
            expect(TestStore:GetUsingPathString("")).to.equal(TestStore._Store)

            TestStore:Merge({
                X = Shared.RemoveNode;
                Y = Shared.RemoveNode;
                Z = Shared.RemoveNode;
            })

            expect(TestStore:GetUsingPathString("X^")).never.to.be.ok()
            expect(TestStore:GetUsingPathString("Y^")).never.to.be.ok()
            expect(TestStore:GetUsingPathString("Z^")).never.to.be.ok()
            expect(TestStore:GetUsingPathString("")).to.equal(TestStore._Store)
        end)

        it("should obtain correct values after a deep merge & delete", function()
            local TestStore = GetTestObject()
            TestStore:Merge({
                X = 1;
                Y = 2;
                Z = {
                    P = 123;
                    Q = 456;
                };
            })

            expect(TestStore:GetUsingPathString("X^")).to.equal(1)
            expect(TestStore:GetUsingPathString("Y^")).to.equal(2)
            expect(TestStore:GetUsingPathString("Z^")).to.equal(TestStore:GetUsingPathString().Z)
            expect(TestStore:GetUsingPathString("Z^P^")).to.equal(123)
            expect(TestStore:GetUsingPathString("Z^Q^")).to.equal(456)
            expect(TestStore:GetUsingPathString("")).to.equal(TestStore._Store)

            TestStore:Merge({
                Z = {P = Shared.RemoveNode};
            })

            expect(TestStore:GetUsingPathString("X^")).to.equal(1)
            expect(TestStore:GetUsingPathString("Y^")).to.equal(2)
            expect(TestStore:GetUsingPathString("Z^")).to.equal(TestStore:GetUsingPathString().Z)
            expect(TestStore:GetUsingPathString("Z^P^")).to.equal(nil)
            expect(TestStore:GetUsingPathString("Z^Q^")).to.equal(456)
            expect(TestStore:GetUsingPathString("")).to.equal(TestStore._Store)

            TestStore:Merge({
                Z = Shared.RemoveNode;
            })

            expect(TestStore:GetUsingPathString("X^")).to.equal(1)
            expect(TestStore:GetUsingPathString("Y^")).to.equal(2)
            expect(TestStore:GetUsingPathString("Z^")).to.equal(nil)
            expect(TestStore:GetUsingPathString("Z^P^")).to.equal(nil)
            expect(TestStore:GetUsingPathString("Z^Q^")).to.equal(nil)
            expect(TestStore:GetUsingPathString("")).to.equal(TestStore._Store)

            TestStore:Merge({
                X = Shared.RemoveNode;
                Y = Shared.RemoveNode;
            })

            expect(TestStore:GetUsingPathString("X^")).to.equal(nil)
            expect(TestStore:GetUsingPathString("Y^")).to.equal(nil)
            expect(TestStore:GetUsingPathString("Z^")).to.equal(nil)
            expect(TestStore:GetUsingPathString("Z^P^")).to.equal(nil)
            expect(TestStore:GetUsingPathString("Z^Q^")).to.equal(nil)
            expect(TestStore:GetUsingPathString("")).to.equal(TestStore._Store)
        end)
    end)

    describe("GetPathFromNode", function()
        it("should reject non-table values for path param", function()
            local TestStore = GetTestObject()

            expect(function()
                TestStore:GetPathFromNode(nil)
            end).to.throw()

            expect(function()
                TestStore:GetPathFromNode(1)
            end).to.throw()

            expect(function()
                TestStore:GetPathFromNode("X")
            end).to.throw()
        end)

        it("should obtain paths for shallow & deep nodes", function()
            local TestStore = GetTestObject()
            TestStore:Merge({
                Z = {
                    P = {};
                    Q = {
                        R = {};
                    };
                };
            })

            expect(TestStore:GetPathFromNode(TestStore:GetUsingPathString().Z)).to.equal("Z^")
            expect(TestStore:GetPathFromNode(TestStore:GetUsingPathString().Z.P)).to.equal("Z^P^")
            expect(TestStore:GetPathFromNode(TestStore:GetUsingPathString().Z.Q)).to.equal("Z^Q^")
            expect(TestStore:GetPathFromNode(TestStore:GetUsingPathString().Z.Q.R)).to.equal("Z^Q^R^")
            expect(TestStore:GetPathFromNode(TestStore:GetUsingPathString())).to.equal("")
        end)
    end)

    describe("GetParentPathFromPathString", function()
        it("should reject non-string paths & accept string paths", function()
            local TestStore = GetTestObject()

            expect(function()
                TestStore:GetParentPathFromPathString()
            end).to.throw()

            expect(function()
                TestStore:GetParentPathFromPathString({})
            end).to.throw()

            expect(function()
                TestStore:GetParentPathFromPathString({"X"})
            end).to.throw()

            expect(function()
                TestStore:GetParentPathFromPathString(1)
            end).to.throw()

            expect(function()
                TestStore:GetParentPathFromPathString("Test")
            end).never.to.throw()
        end)

        it("should give the parent of shallow paths (the root path / empty string)", function()
            local TestStore = GetTestObject()

            TestStore:Merge({
                X = 1;
                Y = 2;
                Z = 3;
            })

            expect(TestStore:GetParentPathFromPathString("X^")).to.equal("")
            expect(TestStore:GetParentPathFromPathString("Y^")).to.equal("")
            expect(TestStore:GetParentPathFromPathString("Z^")).to.equal("")
        end)

        it("should give the parent of deep paths", function()
            local TestStore = GetTestObject()
            TestStore:Merge({
                X = 1;
                Y = 2;
                Z = {
                    P = 123;
                    Q = 456;
                    R = {
                        Test = false;
                    };
                };
            })

            expect(TestStore:GetParentPathFromPathString("X^")).to.equal("")
            expect(TestStore:GetParentPathFromPathString("Y^")).to.equal("")
            expect(TestStore:GetParentPathFromPathString("Z^")).to.equal("")
            expect(TestStore:GetParentPathFromPathString("Z^P^")).to.equal("Z^")
            expect(TestStore:GetParentPathFromPathString("Z^Q^")).to.equal("Z^")
            expect(TestStore:GetParentPathFromPathString("Z^R^")).to.equal("Z^")
            expect(TestStore:GetParentPathFromPathString("Z^R^Test^")).to.equal("Z^R^")
        end)

        it("should de-associate parent paths for removed values at given paths", function()
            local TestStore = GetTestObject()
            TestStore:Merge({
                X = 1;
                Y = 2;
                Z = {
                    P = 123;
                    Q = 456;
                    R = {
                        Test = false;
                    };
                };
            })

            TestStore:Merge({
                X = Shared.RemoveNode;
                Y = Shared.RemoveNode;
                Z = Shared.RemoveNode;
            })

            expect(TestStore:GetParentPathFromPathString("X^")).to.equal(nil)
            expect(TestStore:GetParentPathFromPathString("Y^")).to.equal(nil)
            expect(TestStore:GetParentPathFromPathString("Z^")).to.equal(nil)
            expect(TestStore:GetParentPathFromPathString("Z^P^")).to.equal(nil)
            expect(TestStore:GetParentPathFromPathString("Z^Q^")).to.equal(nil)
            expect(TestStore:GetParentPathFromPathString("Z^R^")).to.equal(nil)
            expect(TestStore:GetParentPathFromPathString("Z^R^Test^")).to.equal(nil)
        end)
    end)

    describe("IsPathStringAncestorOfPathString", function()
        it("should reject non-string paths & accept 2 string paths", function()
            local TestStore = GetTestObject()

            expect(function()
                TestStore:IsPathStringAncestorOfPathString()
            end).to.throw()

            expect(function()
                TestStore:IsPathStringAncestorOfPathString({})
            end).to.throw()

            expect(function()
                TestStore:IsPathStringAncestorOfPathString({"X"})
            end).to.throw()

            expect(function()
                TestStore:IsPathStringAncestorOfPathString(1)
            end).to.throw()

            expect(function()
                TestStore:IsPathStringAncestorOfPathString("Test")
            end).to.throw()

            expect(function()
                TestStore:IsPathStringAncestorOfPathString("Test", "Test")
            end).never.to.throw()
        end)

        it("should return true for correct ancestors (flat)", function()
            local TestStore = GetTestObject()
            TestStore:Merge({
                X = 1;
                Y = 2;
                Z = 3;
            })

            expect(TestStore:IsPathStringAncestorOfPathString("", "")).to.equal(false)
            expect(TestStore:IsPathStringAncestorOfPathString("", "X^")).to.equal(true)
            expect(TestStore:IsPathStringAncestorOfPathString("X^", "X^")).to.equal(false)
            expect(TestStore:IsPathStringAncestorOfPathString("", "Y^")).to.equal(true)
            expect(TestStore:IsPathStringAncestorOfPathString("Y^", "Y^")).to.equal(false)
            expect(TestStore:IsPathStringAncestorOfPathString("", "Z^")).to.equal(true)
            expect(TestStore:IsPathStringAncestorOfPathString("Z^", "Z^")).to.equal(false)
        end)

        it("should return true for correct ancestors (deep)", function()
            local TestStore = GetTestObject()
            TestStore:Merge({
                X = 1;
                Y = 2;
                Z = {
                    P = 123;
                    Q = 456;
                    R = {
                        Test = false;
                    };
                };
            })

            expect(TestStore:IsPathStringAncestorOfPathString("", "")).to.equal(false)
            expect(TestStore:IsPathStringAncestorOfPathString("", "X^")).to.equal(true)
            expect(TestStore:IsPathStringAncestorOfPathString("X^", "X^")).to.equal(false)
            expect(TestStore:IsPathStringAncestorOfPathString("", "Y^")).to.equal(true)
            expect(TestStore:IsPathStringAncestorOfPathString("Y^", "Y^")).to.equal(false)
            expect(TestStore:IsPathStringAncestorOfPathString("", "Z^")).to.equal(true)
            expect(TestStore:IsPathStringAncestorOfPathString("Z^", "Z^")).to.equal(false)
            expect(TestStore:IsPathStringAncestorOfPathString("", "Z^P^")).to.equal(true)
            expect(TestStore:IsPathStringAncestorOfPathString("Z^P^", "Z^P^")).to.equal(false)
            expect(TestStore:IsPathStringAncestorOfPathString("Z^", "Z^P^")).to.equal(true)
            expect(TestStore:IsPathStringAncestorOfPathString("", "Z^Q^")).to.equal(true)
            expect(TestStore:IsPathStringAncestorOfPathString("Z^", "Z^Q^")).to.equal(true)
            expect(TestStore:IsPathStringAncestorOfPathString("Z^Q^", "Z^Q^")).to.equal(false)
            expect(TestStore:IsPathStringAncestorOfPathString("", "Z^R^")).to.equal(true)
            expect(TestStore:IsPathStringAncestorOfPathString("Z^", "Z^R^")).to.equal(true)
            expect(TestStore:IsPathStringAncestorOfPathString("Z^R^", "Z^R^")).to.equal(false)
            expect(TestStore:IsPathStringAncestorOfPathString("", "Z^R^Test^")).to.equal(true)
            expect(TestStore:IsPathStringAncestorOfPathString("Z^", "Z^R^Test^")).to.equal(true)
            expect(TestStore:IsPathStringAncestorOfPathString("Z^R^", "Z^R^Test^")).to.equal(true)
            expect(TestStore:IsPathStringAncestorOfPathString("Z^R^Test^", "Z^R^Test^")).to.equal(false)
        end)
    end)

    describe("IsNodeAncestorOf", function()
        it("should reject non-table nodes & accept 2 table nodes", function()
            local TestStore = GetTestObject()

            expect(function()
                TestStore:IsNodeAncestorOf()
            end).to.throw()

            expect(function()
                TestStore:IsNodeAncestorOf({})
            end).to.throw()

            expect(function()
                TestStore:IsNodeAncestorOf(1)
            end).to.throw()

            expect(function()
                TestStore:IsNodeAncestorOf("Test")
            end).to.throw()

            expect(function()
                TestStore:IsNodeAncestorOf({}, {})
            end).never.to.throw()
        end)

        it("should return true for correct ancestors (flat)", function()
            local TestStore = GetTestObject()
            TestStore:Merge({
                X = {};
                Y = {};
                Z = {};
            })

            local Root = TestStore:GetUsingPathString()

            expect(TestStore:IsNodeAncestorOf(Root, Root)).to.equal(false)
            expect(TestStore:IsNodeAncestorOf(Root, Root.X)).to.equal(true)
            expect(TestStore:IsNodeAncestorOf(Root.X, Root.X)).to.equal(false)
            expect(TestStore:IsNodeAncestorOf(Root, Root.Y)).to.equal(true)
            expect(TestStore:IsNodeAncestorOf(Root.Y, Root.Y)).to.equal(false)
            expect(TestStore:IsNodeAncestorOf(Root, Root.Z)).to.equal(true)
            expect(TestStore:IsNodeAncestorOf(Root.Z, Root.Z)).to.equal(false)
        end)
    end)

    describe("ArrayInsertUsingPathArray", function()
        it("should validate that the node at the target path is an array", function()
            local TestStore = GetTestObject()

            -- Inserting into a nil value is undefined
            expect(function()
                TestStore:ArrayInsertUsingPathArray({"X"}, 1)
            end).to.throw()

            -- Inserting into a string value is undefined
            TestStore:Merge({
                X = "AHHHH";
            })

            expect(function()
                TestStore:ArrayInsertUsingPathArray({"X"}, 1)
            end).to.throw()

            -- Inserting into an object is undefined
            TestStore:SetUsingPathArray({"X"}, nil)
            TestStore:SetUsingPathArray({"X"}, {Y = true})

            expect(function()
                TestStore:ArrayInsertUsingPathArray({"X"}, 1)
            end).to.throw()

            TestStore:SetUsingPathArray({"X"}, nil)

            -- Now it's an array, so it should work
            TestStore:Merge({
                X = {};
            })

            expect(function()
                TestStore:ArrayInsertUsingPathArray({"X"}, 1)
                TestStore:ArrayInsertUsingPathArray({"X"}, 2)
                TestStore:ArrayInsertUsingPathArray({"X"}, 3)
            end).never.to.throw()
        end)

        it("should insert values into the last position given no index", function()
            local TestStore = GetTestObject()
            TestStore:Merge({
                Array = {};
            })

            local Array = TestStore:GetUsingPathArray().Array

            TestStore:ArrayInsertUsingPathArray({"Array"}, 1)
            expect(Array[1]).to.equal(1)
            expect(Array[2]).to.equal(nil)

            TestStore:ArrayInsertUsingPathArray({"Array"}, 2)
            expect(Array[1]).to.equal(1)
            expect(Array[2]).to.equal(2)
            expect(Array[3]).to.equal(nil)

            TestStore:ArrayInsertUsingPathArray({"Array"}, 3)
            expect(Array[1]).to.equal(1)
            expect(Array[2]).to.equal(2)
            expect(Array[3]).to.equal(3)
            expect(Array[4]).to.equal(nil)
        end)

        it("should fire changed signals for inserted values", function()
            local TestStore = GetTestObject()
            TestStore:Merge({
                Array = {};
            })

            local ArrayChanged = 0
            local ArrayConnection = TestStore:GetValueChangedSignal({"Array"}):Connect(function()
                ArrayChanged += 1
            end)

            local LastValue = ""
            local XCount = 0
            local XYCount = 0
            local GotX, GotY
            local ArrayConnection1 = TestStore:GetValueChangedSignal({"Array", 1}):Connect(function(Value)
                LastValue = Value
            end)
            local ArrayConnection2 = TestStore:GetValueChangedSignal({"Array", 2}):Connect(function(Value)
                LastValue = Value
            end)
            local ArrayConnection3 = TestStore:GetValueChangedSignal({"Array", 3}):Connect(function(Value)
                LastValue = Value
            end)
            local ArrayConnection3X = TestStore:GetValueChangedSignal({"Array", 3, "X"}):Connect(function(Value)
                XCount += 1
                GotX = Value
            end)
            local ArrayConnection3XY = TestStore:GetValueChangedSignal({"Array", 3, "X", "Y"}):Connect(function(Value)
                XYCount += 1
                GotY = Value
            end)
            local ArrayConnection4X = TestStore:GetValueChangedSignal({"Array", 4, "X"}):Connect(function(Value)
                XCount += 1
            end)
            local ArrayConnection4XY = TestStore:GetValueChangedSignal({"Array", 4, "X", "Y"}):Connect(function(Value)
                XYCount += 1
            end)

            expect(ArrayChanged).to.equal(0)

            TestStore:ArrayInsertUsingPathArray({"Array"}, "X")
            expect(ArrayChanged).to.equal(1)
            expect(LastValue).to.equal("X")

            TestStore:ArrayInsertUsingPathArray({"Array"}, "Y")
            expect(ArrayChanged).to.equal(2)
            expect(LastValue).to.equal("Y")

            local Object = {X = {Y = {}}}
            expect(XCount).to.equal(0)
            expect(XYCount).to.equal(0)
            expect(GotX).never.to.be.ok()
            expect(GotY).never.to.be.ok()
            TestStore:ArrayInsertUsingPathArray({"Array"}, Object)
            expect(ArrayChanged).to.equal(3)
            expect(LastValue).to.equal(Object)
            expect(XCount).to.equal(1)
            expect(XYCount).to.equal(1)
            expect(GotX).to.equal(Object.X)
            expect(GotY).to.equal(Object.X.Y)

            TestStore:ArrayInsertUsingPathArray({"Array"}, "Z", 2)
            expect(ArrayChanged).to.equal(4)
            expect(LastValue).to.equal("Z")
            expect(XCount).to.equal(2)
            expect(XYCount).to.equal(2)

            local Array = TestStore:GetUsingPathArray({"Array"})
            expect(Array[1]).to.equal("X")
            expect(Array[2]).to.equal("Z")
            expect(Array[3]).to.equal("Y")
            expect(Array[4]).to.equal(Object)

            ArrayConnection:Disconnect()
            ArrayConnection1:Disconnect()
            ArrayConnection2:Disconnect()
            ArrayConnection3:Disconnect()
            ArrayConnection3X:Disconnect()
            ArrayConnection3XY:Disconnect()
            ArrayConnection4X:Disconnect()
            ArrayConnection4XY:Disconnect()
        end)

        it("should up-propagate", function()
            local TestStore = GetTestObject()
            TestStore:Merge({
                Array = {};
            })

            local RootChanged = 0
            local Connection = TestStore:GetValueChangedSignal({}):Connect(function()
                RootChanged += 1
            end)

            expect(RootChanged).to.equal(0)
            TestStore:ArrayInsertUsingPathArray({"Array"}, "Test")
            expect(RootChanged).to.equal(1)

            Connection:Disconnect()
        end)

        it("should insert values into an arbitrary position in the array given an index", function()
            local TestStore = GetTestObject()
            TestStore:Merge({
                Array = {};
            })

            local Array = TestStore:GetUsingPathArray().Array

            TestStore:ArrayInsertUsingPathArray({"Array"}, 1)
            expect(Array[1]).to.equal(1)
            expect(Array[2]).to.equal(nil)

            TestStore:ArrayInsertUsingPathArray({"Array"}, 2, 1)
            expect(Array[1]).to.equal(2)
            expect(Array[2]).to.equal(1)
            expect(Array[3]).to.equal(nil)

            TestStore:ArrayInsertUsingPathArray({"Array"}, 3, 1)
            expect(Array[1]).to.equal(3)
            expect(Array[2]).to.equal(2)
            expect(Array[3]).to.equal(1)
            expect(Array[4]).to.equal(nil)

            TestStore:ArrayInsertUsingPathArray({"Array"}, 1000, 2)
            expect(Array[1]).to.equal(3)
            expect(Array[2]).to.equal(1000)
            expect(Array[3]).to.equal(2)
            expect(Array[4]).to.equal(1)
            expect(Array[5]).to.equal(nil)
        end)
    end)

    describe("ArrayRemoveUsingPathArray", function()
        it("should validate that the node corresponding to a given path is an array", function()
            local TestStore = GetTestObject()
            TestStore:Merge({
                Map = {X = true};
                String = "";
                Number = 123;
            })

            expect(function()
                TestStore:ArrayRemoveUsingPathArray({"String"}, 1)
            end).to.throw()

            expect(function()
                TestStore:ArrayRemoveUsingPathArray({"Number"}, 1)
            end).to.throw()

            expect(function()
                TestStore:ArrayRemoveUsingPathArray({"Map"}, 1)
            end).to.throw()
        end)

        it("should accept an array node", function()
            local TestStore = GetTestObject()
            TestStore:Merge({
                Array = {};
            })

            expect(function()
                TestStore:ArrayRemoveUsingPathArray({"Array"})
            end).never.to.throw()

            TestStore:Merge({
                Array = {1, 2, 3};
            })

            expect(function()
                TestStore:ArrayRemoveUsingPathArray({"Array"})
            end).never.to.throw()
        end)

        it("should remove the last value from an array", function()
            local TestStore = GetTestObject()
            TestStore:Merge({
                Array = {1, 2, 3, 4};
            })

            local ArrayChanged = 0
            local ArrayConnection = TestStore:GetValueChangedSignal({"Array"}):Connect(function()
                ArrayChanged += 1
            end)

            local Count = {0, 0, 0, 0}
            local ConnectionPos1 = TestStore:GetValueChangedSignal({"Array", 1}):Connect(function()
                Count[1] += 1
            end)
            local ConnectionPos2 = TestStore:GetValueChangedSignal({"Array", 2}):Connect(function()
                Count[2] += 1
            end)
            local ConnectionPos3 = TestStore:GetValueChangedSignal({"Array", 3}):Connect(function()
                Count[3] += 1
            end)
            local ConnectionPos4 = TestStore:GetValueChangedSignal({"Array", 4}):Connect(function()
                Count[4] += 1
            end)

            local Array = TestStore:GetUsingPathArray({"Array"})
            expect(Array[1]).to.equal(1)
            expect(Array[2]).to.equal(2)
            expect(Array[3]).to.equal(3)
            expect(Array[4]).to.equal(4)
            expect(ArrayChanged).to.equal(0)

            expect(Count[1]).to.equal(0)
            expect(Count[2]).to.equal(0)
            expect(Count[3]).to.equal(0)
            expect(Count[4]).to.equal(0)

            TestStore:ArrayRemoveUsingPathArray({"Array"})
            expect(ArrayChanged).to.equal(1)
            expect(Array[1]).to.equal(1)
            expect(Array[2]).to.equal(2)
            expect(Array[3]).to.equal(3)
            expect(Array[4]).to.equal(nil)

            expect(Count[1]).to.equal(0)
            expect(Count[2]).to.equal(0)
            expect(Count[3]).to.equal(0)
            expect(Count[4]).to.equal(1)

            TestStore:ArrayRemoveUsingPathArray({"Array"})
            expect(ArrayChanged).to.equal(2)
            expect(Array[1]).to.equal(1)
            expect(Array[2]).to.equal(2)
            expect(Array[3]).to.equal(nil)

            expect(Count[1]).to.equal(0)
            expect(Count[2]).to.equal(0)
            expect(Count[3]).to.equal(1)
            expect(Count[4]).to.equal(1)

            TestStore:ArrayRemoveUsingPathArray({"Array"})
            expect(ArrayChanged).to.equal(3)
            expect(Array[1]).to.equal(1)
            expect(Array[2]).to.equal(nil)

            expect(Count[1]).to.equal(0)
            expect(Count[2]).to.equal(1)
            expect(Count[3]).to.equal(1)
            expect(Count[4]).to.equal(1)

            TestStore:ArrayRemoveUsingPathArray({"Array"})
            expect(ArrayChanged).to.equal(4)
            expect(Array[1]).to.equal(nil)

            expect(Count[1]).to.equal(1)
            expect(Count[2]).to.equal(1)
            expect(Count[3]).to.equal(1)
            expect(Count[4]).to.equal(1)

            -- Removals on empty arrays should not register any changes
            TestStore:ArrayRemoveUsingPathArray({"Array"})
            expect(ArrayChanged).to.equal(4)

            ArrayConnection:Disconnect()
            ConnectionPos1:Disconnect()
            ConnectionPos2:Disconnect()
            ConnectionPos3:Disconnect()
            ConnectionPos4:Disconnect()
        end)

        it("should allow removals from a specific index & fire changed for all successor elements", function()
            local TestStore = GetTestObject()
            TestStore:Merge({
                Array = {1, 2, 3, 4};
            })

            local Count = {0, 0, 0, 0}
            local Last = {}
            local ConnectionPos1 = TestStore:GetValueChangedSignal({"Array", 1}):Connect(function(Value)
                Count[1] += 1
                Last[1] = Value
            end)
            local ConnectionPos2 = TestStore:GetValueChangedSignal({"Array", 2}):Connect(function(Value)
                Count[2] += 1
                Last[2] = Value
            end)
            local ConnectionPos3 = TestStore:GetValueChangedSignal({"Array", 3}):Connect(function(Value)
                Count[3] += 1
                Last[3] = Value
            end)
            local ConnectionPos4 = TestStore:GetValueChangedSignal({"Array", 4}):Connect(function(Value)
                Count[4] += 1
                Last[4] = Value
            end)

            TestStore:ArrayRemoveUsingPathArray({"Array"}, 1)
            expect(Count[1]).to.equal(1)
            expect(Count[2]).to.equal(1)
            expect(Count[3]).to.equal(1)
            expect(Count[4]).to.equal(1)
            expect(Last[1]).to.equal(2)
            expect(Last[2]).to.equal(3)
            expect(Last[3]).to.equal(4)
            expect(Last[4]).to.equal(nil)

            TestStore:ArrayRemoveUsingPathArray({"Array"}, 2)
            expect(Count[1]).to.equal(1)
            expect(Count[2]).to.equal(2)
            expect(Count[3]).to.equal(2)
            expect(Count[4]).to.equal(1)
            expect(Last[1]).to.equal(2)
            expect(Last[2]).to.equal(4)
            expect(Last[3]).to.equal(nil)
            expect(Last[4]).to.equal(nil)

            ConnectionPos1:Disconnect()
            ConnectionPos2:Disconnect()
            ConnectionPos3:Disconnect()
            ConnectionPos4:Disconnect()
        end)

        it("should up-propagate for removed tables", function()
            local TestStore = GetTestObject()
            TestStore:Merge({
                Array = {1, 2, {X = true}, 4};
            })

            local ArrayChanged = 0
            local RootChanged = 0
            local XChanged = 0

            local ArrayConnection = TestStore:GetValueChangedSignal({"Array"}):Connect(function()
                ArrayChanged += 1
            end)
            local RootConnection = TestStore:GetValueChangedSignal({}):Connect(function()
                RootChanged += 1
            end)
            local XConnection = TestStore:GetValueChangedSignal({"Array", 3, "X"}):Connect(function()
                XChanged += 1
            end)

            expect(ArrayChanged).to.equal(0)
            expect(RootChanged).to.equal(0)
            expect(XChanged).to.equal(0)

            TestStore:ArrayRemoveUsingPathArray({"Array"}, 3)
            expect(ArrayChanged).to.equal(1)
            expect(RootChanged).to.equal(1)
            expect(XChanged).to.equal(1)

            ArrayConnection:Disconnect()
            RootConnection:Disconnect()
            XConnection:Disconnect()
        end)
    end)

    describe("IncrementUsingPathArray", function()
        it("should reject non-numeric values from corresponding paths", function()
            local TestStore = GetTestObject()
            TestStore:Merge({
                Test = {};
                Str = "";
            })

            expect(function()
                TestStore:IncrementUsingPathArray({"Test"})
            end).to.throw()

            expect(function()
                TestStore:IncrementUsingPathArray({"Test", "X", "Y"})
            end).to.throw()

            expect(function()
                TestStore:IncrementUsingPathArray({"Str"})
            end).to.throw()
        end)

        it("should accept paths which correspond to numeric values", function()
            local TestStore = GetTestObject()
            TestStore:Merge({
                Test = 1;
            })

            expect(function()
                TestStore:IncrementUsingPathArray({"Test"})
            end).never.to.throw()
        end)

        it("should increment the value at the given path with 1 by default", function()
            local TestStore = GetTestObject()
            TestStore:Merge({
                Test = 1;
            })

            TestStore:IncrementUsingPathArray({"Test"})
            expect(TestStore:GetUsingPathArray().Test).to.equal(2)

            TestStore:IncrementUsingPathArray({"Test"})
            expect(TestStore:GetUsingPathArray().Test).to.equal(3)

            TestStore:IncrementUsingPathArray({"Test"})
            expect(TestStore:GetUsingPathArray().Test).to.equal(4)
        end)

        it("should increment the value at a given path by a custom amount if specified", function()
            local TestStore = GetTestObject()
            TestStore:Merge({
                Test = 1;
            })

            TestStore:IncrementUsingPathArray({"Test"}, 2)
            expect(TestStore:GetUsingPathArray().Test).to.equal(3)

            TestStore:IncrementUsingPathArray({"Test"}, 3)
            expect(TestStore:GetUsingPathArray().Test).to.equal(6)

            TestStore:IncrementUsingPathArray({"Test"}, -1)
            expect(TestStore:GetUsingPathArray().Test).to.equal(5)

            TestStore:IncrementUsingPathArray({"Test"}, 0)
            expect(TestStore:GetUsingPathArray().Test).to.equal(5)
        end)

        it("should return the new value at the given path", function()
            local TestStore = GetTestObject()
            TestStore:Merge({
                Test = 1;
            })

            expect(TestStore:IncrementUsingPathArray({"Test"})).to.equal(2)
            expect(TestStore:IncrementUsingPathArray({"Test"})).to.equal(3)
            expect(TestStore:IncrementUsingPathArray({"Test"})).to.equal(4)
            expect(TestStore:IncrementUsingPathArray({"Test"}, -3)).to.equal(1)
        end)

        it("should set a default value if no value exists", function()
            local TestStore = GetTestObject()
            TestStore:IncrementUsingPathArray({"X", "Y", "Z"}, 1, 5)

            local InnerStore = TestStore:GetUsingPathArray()
            expect(InnerStore.X).to.be.ok()
            expect(InnerStore.X.Y).to.be.ok()
            expect(InnerStore.X.Y.Z).to.equal(6)

            TestStore:IncrementUsingPathArray({"X", "Y", "Z"}, 1, 5)
            expect(TestStore:GetUsingPathArray().X.Y.Z).to.equal(7)
        end)
    end)

    describe("GetUsingPathArray", function()
        it("should return the main table with no arguments", function()
            local TestStore = GetTestObject()
            expect(TestStore:GetUsingPathArray()).to.equal(TestStore._Store)
        end)

        it("should return nil for paths which do not exist", function()
            local TestStore = GetTestObject()
            expect(TestStore:GetUsingPathArray({"A", "B"})).never.to.be.ok()
            expect(TestStore:GetUsingPathArray({"A", "B"})).never.to.be.ok()
        end)
    end)

    describe("AwaitUsingPathArray", function()
        it("should return if value is already present", function()
            local TestStore = GetTestObject()
            TestStore:SetUsingPathArray({"A"}, 1)
            expect(TestStore:AwaitUsingPathArray({"A"})).to.equal(1)
        end)

        it("should await a flat value", function()
            local WAIT_TIME = 0.1
            local TestStore = GetTestObject()

            task.spawn(function()
                task.wait(WAIT_TIME)
                TestStore:SetUsingPathArray({"A"}, 1)
            end)

            local Time = os.clock()
            expect(TestStore:AwaitUsingPathArray({"A"})).to.equal(1)
            expect(os.clock() - Time >= WAIT_TIME).to.equal(true)
        end)

        it("should await a deep value", function()
            local WAIT_TIME = 0.1
            local TestStore = GetTestObject()

            task.spawn(function()
                task.wait(WAIT_TIME)
                TestStore:SetUsingPathArray({"A", "B", "C"}, 1)
            end)

            local Time = os.clock()
            expect(TestStore:AwaitUsingPathArray({"A", "B", "C"})).to.equal(1)
            expect(os.clock() - Time >= WAIT_TIME).to.equal(true)
        end)

        it("should await a values in sub-tables", function()
            local WAIT_TIME = 0.1
            local TestStore = GetTestObject()

            task.spawn(function()
                task.wait(WAIT_TIME)
                TestStore:SetUsingPathArray({"A", "B"}, {
                    TEST = 1;
                })
                TestStore:SetUsingPathArray({"C"}, {
                    D = 2;
                })
            end)

            local Time = os.clock()

            task.spawn(function()
                expect(TestStore:AwaitUsingPathArray({"A", "B", "TEST"})).to.equal(1)
            end)

            expect(TestStore:AwaitUsingPathArray({"C", "D"})).to.equal(2)
            expect(os.clock() - Time >= WAIT_TIME).to.equal(true)
        end)

        it("should timeout", function()
            local TIMEOUT = 0.1
            local TestStore = GetTestObject()

            local Time = os.clock()

            expect(pcall(function()
                TestStore:AwaitUsingPathArray({"A"}, TIMEOUT)
            end)).to.equal(false)

            expect(os.clock() - Time >= TIMEOUT).to.equal(true)
        end)
    end)

    describe("GetValueChangedSignal", function()
        it("should fire correctly", function()
            local TestStore = GetTestObject()
            local Value

            TestStore:GetValueChangedSignal({"A"}):Connect(function(NewValue)
                Value = NewValue
            end)

            expect(Value).never.to.be.ok()
            TestStore:SetUsingPathArray({"A"}, 20)
            expect(Value).to.equal(20)
        end)

        it("should implement Wait() correctly", function()
            local TestStore = GetTestObject()
            local Value

            task.spawn(function()
                Value = TestStore:GetValueChangedSignal({"A"}):Wait()
            end)

            expect(Value).never.to.be.ok()
            TestStore:SetUsingPathArray({"A"}, 20)
            expect(Value).to.equal(20)
        end)
    end)

    describe("Merge", function()
        it("should set a flat value", function()
            local TestStore = GetTestObject()

            TestStore:Merge({
                A = 1;
            })

            expect(TestStore:GetUsingPathArray({"A"})).to.equal(1)
        end)

        it("should overwrite a flat value", function()
            local TestStore = GetTestObject()

            TestStore:Merge({
                A = 1;
            })

            TestStore:Merge({
                A = 5;
            })

            expect(TestStore:GetUsingPathArray({"A"})).to.equal(5)
        end)
    end)
end