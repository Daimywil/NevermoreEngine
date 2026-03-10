--!strict
--[=[
	Adds the loader instance so script.Parent.loader works.

	@class LoaderLinkCreator
]=]

local loader = script.Parent.Parent
local LoaderLinkUtils = require(loader.LoaderLink.LoaderLinkUtils)
local ReplicatorReferences = require(loader.Replication.ReplicatorReferences)

local LoaderLinkCreator = {}
LoaderLinkCreator.ClassName = "LoaderLinkCreator"
LoaderLinkCreator.__index = LoaderLinkCreator

export type LoaderLinkCreator = typeof(setmetatable(
	{} :: {
		_root: Instance,
		_references: ReplicatorReferences.ReplicatorReferences?,
		_hasLoaderCount: IntValue,
		_childRequiresLoaderCount: IntValue,
		_provideLoader: BoolValue,
		_lastProvidedLoader: Instance?,
	},
	{} :: typeof({ __index = LoaderLinkCreator })
))

function LoaderLinkCreator.new(
	root: Instance,
	references: ReplicatorReferences.ReplicatorReferences?,
	isRoot: boolean?
): LoaderLinkCreator
	assert(typeof(root) == "Instance", "Bad root")
	assert(ReplicatorReferences.isReplicatorReferences(references) or references == nil, "Bad references")

	local self = setmetatable({}, LoaderLinkCreator)

	self._root = root
	self._references = references

	self._childRequiresLoaderCount = Instance.new("IntValue")
	self._childRequiresLoaderCount.Value = isRoot and 1 or 0

	self._hasLoaderCount = Instance.new("IntValue")
	self._hasLoaderCount.Value = 0

	self._provideLoader = Instance.new("BoolValue")
	self._provideLoader.Value = false

	-- prevent frame delay
	self:_setupEventTracking()
	self:_setupRendering()

	return self :: LoaderLinkCreator
end

function LoaderLinkCreator._setupEventTracking(self: LoaderLinkCreator)
	for _, child in self._root:GetChildren() do
		self:_handleChildAdded(child)
	end

	-- Need to do this AFTER child added loop
	if self._references then
		self._references:ObserveReferenceChanged(loader, function(replicatedLoader: Instance?)
			if replicatedLoader and replicatedLoader ~= loader then
				(self :: any):_countLoaderReferences(replicatedLoader)
			end
		end)
	else
		(self :: any):_countLoaderReferences(loader)
	end

	-- Update state
	self._childRequiresLoaderCount.Changed:Connect(function()
		self:_updateProviderLoader()
	end)
	self._hasLoaderCount.Changed:Connect(function()
		self:_updateProviderLoader()
	end)
	self:_updateProviderLoader()
end

function LoaderLinkCreator._setupRendering(self: LoaderLinkCreator)
	if self._references then
		local function renderLoader()
			if self._provideLoader.Value then
				self:_renderLoaderWithReferences(self._references)
			end
		end

		self._provideLoader.Changed:Connect(renderLoader)
		renderLoader()
	else
		local function renderLoader()
			if self._provideLoader.Value then
				self:_doLoaderRender(loader)
			end
		end

		-- No references, just render as needed
		self._provideLoader.Changed:Connect(renderLoader)
		renderLoader()
	end
end

function LoaderLinkCreator._updateProviderLoader(self: LoaderLinkCreator)
	self._provideLoader.Value = (self._childRequiresLoaderCount.Value > 0) and self._hasLoaderCount.Value <= 0
end

function LoaderLinkCreator._handleChildAdded(self: LoaderLinkCreator, child: Instance)
	assert(typeof(child) == "Instance", "Bad child")

	if child:IsA("ModuleScript") then
		if child.Name == "loader" then
			if child ~= self._lastProvidedLoader then
				self:_addToHasLoaderCount(1)
			end
		else
			self:_incrementNeededLoader(1)
		end
	elseif child:IsA("Folder") then
		-- TODO: Maybe add to children with node_modules explicitly in its list.
		LoaderLinkCreator.new(child, self._references)
	end
end

function LoaderLinkCreator._renderLoaderWithReferences(
	self: LoaderLinkCreator,
	references: ReplicatorReferences.ReplicatorReferences
)
	references:ObserveReferenceChanged(loader, function(value: Instance?)
		if value then
			self:_doLoaderRender(value)
		end
	end)
end

function LoaderLinkCreator._doLoaderRender(self: LoaderLinkCreator, value: Instance)
	local loaderLink = LoaderLinkUtils.create(value, loader.Name)
	self._lastProvidedLoader = loaderLink

	loaderLink.Parent = self._root

	return loaderLink
end

function LoaderLinkCreator._incrementNeededLoader(self: LoaderLinkCreator, amount: number): () -> ()
	assert(type(amount) == "number", "Bad amount")

	self._childRequiresLoaderCount.Value = self._childRequiresLoaderCount.Value + amount
	return function()
		self._childRequiresLoaderCount.Value = self._childRequiresLoaderCount.Value - amount
	end
end

function LoaderLinkCreator._addToHasLoaderCount(self: LoaderLinkCreator, amount: number): () -> ()
	assert(type(amount) == "number", "Bad amount")

	self._hasLoaderCount.Value = self._hasLoaderCount.Value + amount
	return function()
		self._hasLoaderCount.Value = self._hasLoaderCount.Value - amount
	end
end

function LoaderLinkCreator._countLoaderReferences(self: LoaderLinkCreator, robloxInst: Instance)
	assert(typeof(robloxInst) == "Instance", "Bad robloxInst")

	-- TODO: Maybe handle loader reparenting more elegantly? this seems deeply unlikely.
	if robloxInst.Parent == self._root then
		self:_addToHasLoaderCount(1)
	end

	robloxInst:GetPropertyChangedSignal("Parent"):Connect(function()
		if robloxInst.Parent == self._root then
			self:_addToHasLoaderCount(1)
		end
	end)
end

return LoaderLinkCreator
