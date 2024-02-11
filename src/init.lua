local GeneralStore = require(script:WaitForChild("GeneralStore"));
export type RawStore = GeneralStore.RawStore;
export type Store = GeneralStore.Store;

local StoreInterface = require(script:WaitForChild("StoreInterface"));
export type Node<T> = StoreInterface.Node<T>;
export type ArrayNode<T> = StoreInterface.ArrayNode<T>;
export type CollectionNode<K, V> = StoreInterface.CollectionNode<K, V>;

local ReplicatedStore = require(script:WaitForChild("ReplicatedStore"));
export type ReplicatedStore = ReplicatedStore.ReplicatedStore;

local InstanceReplication = require(script:WaitForChild("InstanceReplication"));

return {
    GeneralStore = GeneralStore;
    StoreInterface = StoreInterface;
    ReplicatedStore = ReplicatedStore;
    InstanceReplication = InstanceReplication;
};