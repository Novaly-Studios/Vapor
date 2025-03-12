local InstanceReplication = require(script.InstanceReplication)
local ReplicatedStore = require(script.ReplicatedStore)

local StoreInterface = require(script.StoreInterface)
    export type Node<T> = StoreInterface.Node<T>
    export type ArrayNode<T> = StoreInterface.ArrayNode<T>
    export type CollectionNode<K, V> = StoreInterface.CollectionNode<K, V>

local GeneralStore = require(script.GeneralStore)
    export type GeneralStoreStructure = GeneralStore.GeneralStoreStructure

return table.freeze({
    InstanceReplication = InstanceReplication;
    ReplicatedStore = ReplicatedStore;
    StoreInterface = StoreInterface;
    GeneralStore = GeneralStore;
})