--!strict
--[=[
	Monitors dependencies primarily for replication. Handles the following scenarios.

	This system dynamically replicates whatever state exists in the tree except we
	filter out server-specific assets while any client-side assets are still replicated
	even if deeper in the tree.

	By separating out the replication component of the loader from the loading logic
	we can more easily support hot reloading and future loading scenarios.

	Repliation rules:
	1. Replicate the whole tree, including any changes
	2. Module scripts named Server are replaced with a folder
	3. Module scripts that are in server mode won't replicate unless a client dependency is needed or found.
	4. Once we hit a "Template" object we stop trying to be smart since Mesh parts are not API accessible.
	5. References are preserved for ObjectValues.

	This system is designed to minimize changes such that hot reloading can be easily
	implemented.

	Right now it fails to be performance friendly with module scripts under another
	module script.

	@class Replicator
]=]

local loader = script.Parent.Parent

local ReplicationType = require(loader.Replication.ReplicationType)
local ReplicationTypeUtils = require(loader.Replication.ReplicationTypeUtils)
local ReplicatorReferences = require(loader.Replication.ReplicatorReferences)

local Replicator = {}
Replicator.ClassName = "Replicator"
Replicator.__index = Replicator

export type Replicator = typeof(setmetatable(
	{} :: {
		_replicationStarted: boolean,
		_references: ReplicatorReferences.ReplicatorReferences,
		_target: ObjectValue,
		_replicatedDescendantCount: IntValue,
		_hasReplicatedDescendants: BoolValue,
		_replicationType: StringValue,
	},
	{} :: typeof({ __index = Replicator })
))

--[=[
	Constructs a new Replicator which will do the syncing.

	@param references ReplicatorReferences
	@return Replicator
]=]
function Replicator.new(references: ReplicatorReferences.ReplicatorReferences): Replicator
	local self = setmetatable({}, Replicator)

	assert(ReplicatorReferences.isReplicatorReferences(references), "Bad references")

	self._references = references
	self._replicationStarted = false

	self._target = Instance.new("ObjectValue")
	self._target.Value = nil

	self._replicatedDescendantCount = Instance.new("IntValue")
	self._replicatedDescendantCount.Name = "Replicator_ReplicatedDescendantCount"
	self._replicatedDescendantCount.Value = 0

	self._hasReplicatedDescendants = Instance.new("BoolValue")
	self._hasReplicatedDescendants.Name = "Replicator_HasReplicatedDescendants"
	self._hasReplicatedDescendants.Value = false

	self._replicationType = Instance.new("StringValue")
	self._replicationType.Name = "Replicator_ReplicationType"
	self._replicationType.Value = ReplicationType.SHARED

	self._replicatedDescendantCount.Changed:Connect(function()
		self._hasReplicatedDescendants.Value = self._replicatedDescendantCount.Value > 0
	end)

	return self
end

--[=[
	Replicates children from the given root

	@param root Instance
]=]
function Replicator.ReplicateFrom(self: Replicator, root: Instance)
	assert(typeof(root) == "Instance", "Bad root")
	if self._replicationStarted then
		(error :: any)("[Replicator] - Replication already started")
	end

	self._replicationStarted = true

	for _, child in root:GetChildren() do
		self:_handleChildAdded(child)
	end
end

--[=[
	Returns true if the argument is a replicator

	@param replicator any?
	@return boolean
]=]
function Replicator.isReplicator(replicator: any): boolean
	return type(replicator) == "table" and getmetatable(replicator :: any) == Replicator
end

--[=[
	Returns the replicated descendant count value.
	@return IntValue
]=]
function Replicator.GetReplicatedDescendantCountValue(self: Replicator): IntValue
	return self._replicatedDescendantCount
end

--[=[
	Sets the replication type for this replicator

	@param replicationType ReplicationType
]=]
function Replicator.SetReplicationType(self: Replicator, replicationType: ReplicationType.ReplicationType)
	assert(ReplicationTypeUtils.isReplicationType(replicationType), "Bad replicationType")

	self._replicationType.Value = replicationType
end

--[=[
	Sets the target for the replicator where the results will be parented.

	@param target Instance?
]=]
function Replicator.SetTarget(self: Replicator, target: Instance?)
	assert(typeof(target) == "Instance" or target == nil, "Bad target")

	self._target.Value = target
end

--[=[
	Gets the current target for the replicator.

	@return Instance?
]=]
function Replicator.GetTarget(self: Replicator): Instance?
	return self._target.Value
end

--[=[
	Gets a value representing if there's any replicated children. Used to
	avoid leaking more server-side information than needed for the user.

	@return BoolValue
]=]
function Replicator.GetHasReplicatedChildrenValue(self: Replicator): BoolValue
	return self._hasReplicatedDescendants
end

function Replicator.GetReplicationTypeValue(self: Replicator): StringValue
	return self._replicationType
end

function Replicator._handleChildAdded(self: Replicator, child: Instance)
	self:_renderChild(child)
end

function Replicator._renderChild(self: Replicator, child: Instance)
	local replicator = Replicator.new(self._references)
	self:_setupReplicatorDescendantCount(replicator)

	if child:IsA("Folder") then
		self:_setupReplicatorTypeFromFolderName(replicator, child)
	else
		self:_setupReplicatorType(replicator)
	end

	local replicationTypeValue = replicator:GetReplicationTypeValue()
	self:_replicateBasedUponMode(replicator, replicationTypeValue.Value :: ReplicationType.ReplicationType, child)

	replicator:ReplicateFrom(child)
end

function Replicator._replicateBasedUponMode(
	self: Replicator,
	replicator: Replicator,
	replicationType: ReplicationType.ReplicationType,
	child: Instance
)
	if replicationType == ReplicationType.SERVER then
		return self:_doReplicationServer(replicator, child)
	elseif replicationType == ReplicationType.SHARED or replicationType == ReplicationType.CLIENT then
		return self:_doReplicationClient(replicator, child)
	else
		error("[Replicator] - Unknown replicationType")
	end
end

function Replicator._doReplicationServer(self: Replicator, replicator: Replicator, child: Instance)
	local hasReplicatedChildren = replicator:GetHasReplicatedChildrenValue()

	if hasReplicatedChildren.Value then
		self:_doServerClone(replicator, child)
	end
end

function Replicator._doServerClone(self: Replicator, replicator: Replicator, child: Instance)
	-- Always a folder to prevent information from leaking...
	local copy = Instance.new("Folder")

	self:_setupNameReplication(child, copy)
	self:_setupParentReplication(copy)
	self:_setupReference(child, copy)

	-- Setup replication for this specific instance.
	self:_setupReplicatorTarget(replicator, copy)
end

function Replicator._doReplicationClient(self: Replicator, replicator: Replicator, child: Instance)
	if child:IsA("ModuleScript") then
		self:_setupReplicatedDescendantCountAdd(1)

		self:_doModuleScriptCloneClient(replicator, child)
	elseif child:IsA("Folder") then
		local copy = Instance.new("Folder")

		self:_doStandardReplication(replicator, child, copy)
	elseif child:IsA("ObjectValue") then
		local copy = Instance.new("ObjectValue")

		self:_setupObjectValueReplication(child, copy)
		self:_doStandardReplication(replicator, child, copy)
	else
		-- selene: allow(incorrect_standard_library_use)
		local copy = Instance.fromExisting(child)

		-- TODO: Maybe do better
		self:_setupReplicatedDescendantCountAdd(1)
		self:_doStandardReplication(replicator, child, copy)
	end
end

function Replicator._doModuleScriptCloneClient(self: Replicator, replicator: Replicator, child: Instance)
	local copy = Instance.fromExisting(child)

	self:_doStandardReplication(replicator, child, copy)
end

function Replicator._doStandardReplication(self: Replicator, replicator: Replicator, child: Instance, copy: Instance)
	self:_setupTagReplication(child, copy)
	self:_setupNameReplication(child, copy)
	self:_setupParentReplication(copy)
	self:_setupReference(child, copy)

	-- Setup replication for this specific instance.
	self:_setupReplicatorTarget(replicator, copy)
end

function Replicator._setupReplicatedDescendantCountAdd(self: Replicator, amount: number)
	-- Do this replication count here so when the source changes we don't
	-- have any flickering.
	self._replicatedDescendantCount.Value += amount
end

--[[
	Sets up the replicator target so children can be parented into the
	instance.

	Sets the target to the copy

	@param maid Maid
	@param replicator Replicator
	@param copy Instance
]]
function Replicator._setupReplicatorTarget(_self: Replicator, replicator: Replicator, copy: Instance)
	replicator:SetTarget(copy)
end

--[[
	Adds the children count of a child replicator to this replicators
	count.

	We use this to determine if we need to build the whole tree or not.

	@param maid Maid
	@param replicator Replicator
]]
function Replicator._setupReplicatorDescendantCount(self: Replicator, replicator: Replicator)
	local replicatedChildrenCount = replicator:GetReplicatedDescendantCountValue()
	local lastValue = replicatedChildrenCount.Value
	self._replicatedDescendantCount.Value += lastValue

	replicatedChildrenCount.Changed:Connect(function()
		local value = replicatedChildrenCount.Value
		local delta = value - lastValue
		lastValue = value
		self._replicatedDescendantCount.Value += delta
	end)
end

--[[
	Sets up references from original to the copy. This allows

	@param maid Maid
	@param child Instance
	@param copy Instance
]]
function Replicator._setupReference(self: Replicator, child: Instance, copy: Instance)
	-- Setup references
	self._references:SetReference(child, copy)
end

--[[
	Sets up replication type from the folder name. This sort of thing controls
	replication hierarchy for instances we want to have.

	@param maid Maid
	@param replicator
	@param child Instance
]]
function Replicator._setupReplicatorTypeFromFolderName(self: Replicator, replicator: Replicator, child: Instance)
	replicator:SetReplicationType(self:_getFolderReplicationType(child.Name))
end

function Replicator._setupReplicatorType(self: Replicator, replicator)
	replicator:SetReplicationType(self._replicationType.Value)
end

--[[
	Sets up name replication explicitly.

	@param maid Maid
	@param child Instance
	@param copy Instance
]]
function Replicator._setupNameReplication(_self: Replicator, child: Instance, copy: Instance)
	copy.Name = child.Name
end

--[[
	Sets up the parent replication.

	@param maid Maid
	@param copy Instance
]]
function Replicator._setupParentReplication(self: Replicator, copy: Instance)
	copy.Parent = self._target.Value
end

--[[
	Sets up tag replication explicitly.

	@param maid Maid
	@param child Instance
	@param copy Instance
]]
function Replicator._setupTagReplication(_self: Replicator, child: Instance, copy: Instance)
	for _, tag in child:GetTags() do
		copy:AddTag(tag)
	end

	child.Changed:Connect(function(property)
		if property == "Tags" then
			local ourTagSet: { [string]: true } = {}
			for _, tag in copy:GetTags() do
				ourTagSet[tag] = true
			end

			for _, tag in child:GetTags() do
				if not ourTagSet[tag] then
					copy:AddTag(tag)
				end

				ourTagSet[tag] = nil
			end

			for tag, _ in ourTagSet do
				copy:RemoveTag(tag)
			end
		end
	end)
end

--[[
	Sets up the object value replication to point towards new values.

	@param maid Maid
	@param child Instance
	@param copy Instance
]]
function Replicator._setupObjectValueReplication(self: Replicator, child: ObjectValue, copy: Instance)
	self:_doObjectValueReplication(child, copy)
end

function Replicator._doObjectValueReplication(self: Replicator, child: ValueBase, copy: Instance)
	assert(typeof(child) == "Instance", "Bad child")
	assert(typeof(copy) == "Instance", "Bad copy")

	local childValue: Instance? = (child :: any).Value
	if childValue then
		self._references:ObserveReferenceChanged(childValue, function(newValue)
			if newValue then
				(copy :: any).Value = newValue
			else
				-- Fall back to original value (pointing outside of tree)
				newValue = childValue
			end
		end)
	else
		(copy :: any).Value = nil

		return nil
	end
end

--[[
	Computes folder replication type based upon the folder name
	and inherited folder replication type.

	@param childName string
]]
function Replicator._getFolderReplicationType(self: Replicator, childName: string): ReplicationType.ReplicationType
	assert(type(childName) == "string", "Bad childName")

	local replicationType: ReplicationType.ReplicationType =
		self._replicationType.Value :: ReplicationType.ReplicationType

	return ReplicationTypeUtils.getFolderReplicationType(childName, replicationType)
end

return Replicator
