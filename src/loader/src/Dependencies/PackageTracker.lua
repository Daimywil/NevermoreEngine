--!strict
--[=[
	For each package, track subdependent packages and packages

	@class PackageTracker
]=]

local loader = script.Parent.Parent
local DependencyUtils = require(loader.Dependencies.DependencyUtils)
local ReplicationType = require(loader.Replication.ReplicationType)
local ReplicationTypeUtils = require(loader.Replication.ReplicationTypeUtils)

local PackageTracker = {}
PackageTracker.ClassName = "PackageTracker"
PackageTracker.__index = PackageTracker

export type ModuleScriptInfo = {
	moduleScript: ModuleScript,
	replicationType: ReplicationType.ReplicationType,
}

export type PackageTrackerProvider = {
	FindPackageTracker: (self: PackageTrackerProvider, instance: Instance) -> PackageTracker?,
	AddPackageRoot: (self: PackageTrackerProvider, instance: Instance) -> PackageTracker,
}

export type PackageTracker = typeof(setmetatable(
	{} :: {
		_packageTrackerProvider: PackageTrackerProvider,
		_packageRoot: Instance,
		_subpackagesMap: { [string]: Instance },
		_subpackagesTrackerList: { PackageTracker },
		_packageModuleScriptMap: { [string]: ModuleScriptInfo },
	},
	{} :: typeof({ __index = PackageTracker })
))

function PackageTracker.new(packageTrackerProvider: PackageTrackerProvider, packageRoot: Instance): PackageTracker
	assert(packageTrackerProvider, "No packageTrackerProvider")
	assert(typeof(packageRoot) == "Instance", "Bad packageRoot")

	local self = setmetatable({}, PackageTracker)

	self._packageTrackerProvider = assert(packageTrackerProvider, "No packageTrackerProvider")
	self._packageRoot = assert(packageRoot, "No packageRoot")

	self._subpackagesMap = {} :: { [string]: Instance }
	self._subpackagesTrackerList = {} :: { PackageTracker }
	self._packageModuleScriptMap = {} :: { [string]: ModuleScriptInfo }

	return self
end

function PackageTracker.StartTracking(self: PackageTracker)
	local moduleScript: ModuleScript? = nil
	if self._packageRoot:IsA("ModuleScript") then
		moduleScript = self._packageRoot
	end

	if moduleScript ~= nil then
		-- Module script children don't get to be observed
		self:_trackModuleScript(moduleScript, ReplicationType.SHARED)
	else
		local root = self._packageRoot :: Instance
		self:_trackChildren(root, ReplicationType.SHARED)
	end
end

function PackageTracker.ResolveDependency(
	self: PackageTracker,
	request: string,
	replicationType: ReplicationType.ReplicationType
): ModuleScript?
	local packageModuleScript = self:FindPackageModuleScript(request, replicationType)
	if packageModuleScript then
		return packageModuleScript
	end

	local subpackageModuleScript = self:FindSubpackageModuleScript(request, replicationType)
	if subpackageModuleScript then
		return subpackageModuleScript
	end

	local parentModuleScript = self:FindImplicitParentModuleScript(request, replicationType)
	if parentModuleScript then
		return parentModuleScript
	end

	return nil
end

function PackageTracker.FindImplicitParentModuleScript(
	self: PackageTracker,
	request: string,
	replicationType: ReplicationType.ReplicationType
): ModuleScript?
	assert(type(request) == "string", "Bad request")
	assert(ReplicationTypeUtils.isReplicationType(replicationType), "Bad replicationType")

	-- Implicit dependencies
	local packageRootParent = self._packageRoot.Parent
	if not packageRootParent then
		return nil
	end

	local parentProvider = self._packageTrackerProvider:FindPackageTracker(packageRootParent)
	if not parentProvider then
		return nil
	end

	-- Check parent provider for implicit dependency
	local subpackageModuleScript = parentProvider:FindSubpackageModuleScript(request, replicationType)
	if subpackageModuleScript then
		return subpackageModuleScript
	end

	return parentProvider:FindImplicitParentModuleScript(request, replicationType) :: ModuleScript?
end

function PackageTracker.FindPackageModuleScript(
	self: PackageTracker,
	moduleScriptName: string,
	replicationType: ReplicationType.ReplicationType
): ModuleScript?
	assert(type(moduleScriptName) == "string", "Bad moduleScriptName")
	assert(ReplicationTypeUtils.isReplicationType(replicationType), "Bad replicationType")

	local found = self._packageModuleScriptMap[moduleScriptName]

	if found then
		if ReplicationTypeUtils.isAllowed(found.replicationType, replicationType) then
			return found.moduleScript
		else
			return nil
		end
	else
		return nil
	end
end

function PackageTracker.FindSubpackageModuleScript(
	self: PackageTracker,
	moduleScriptName: string,
	replicationType: ReplicationType.ReplicationType
): ModuleScript?
	assert(type(moduleScriptName) == "string", "Bad moduleScriptName")
	assert(ReplicationTypeUtils.isReplicationType(replicationType), "Bad replicationType")

	for _, packageTracker in self._subpackagesTrackerList do
		local found = packageTracker._packageModuleScriptMap[moduleScriptName]
		if found then
			if ReplicationTypeUtils.isAllowed(found.replicationType, replicationType) then
				return found.moduleScript
			else
				return nil
			end
		end
	end

	return nil
end

function PackageTracker._trackChildrenAndReplicationType(
	self: PackageTracker,
	parent: Instance,
	ancestorReplicationType: ReplicationType.ReplicationType
)
	assert(typeof(parent) == "Instance", "Bad parent")
	assert(ReplicationTypeUtils.isReplicationType(ancestorReplicationType), "Bad ancestorReplicationType")

	local lastReplicationType: ReplicationType.ReplicationType =
		ReplicationTypeUtils.getFolderReplicationType(parent.Name, ancestorReplicationType)

	self:_trackChildren(parent, lastReplicationType)
end

function PackageTracker._trackChildren(
	self: PackageTracker,
	parent: Instance,
	ancestorReplicationType: ReplicationType.ReplicationType
)
	assert(typeof(parent) == "Instance", "Bad parent")
	assert(ReplicationTypeUtils.isReplicationType(ancestorReplicationType), "Bad ancestorReplicationType")

	for _, child in parent:GetChildren() do
		self:_handleChildAdded(child, ancestorReplicationType)
	end
end

function PackageTracker._handleChildAdded(
	self: PackageTracker,
	child: Instance,
	ancestorReplicationType: ReplicationType.ReplicationType
)
	assert(typeof(child) == "Instance", "Bad child")
	assert(ReplicationTypeUtils.isReplicationType(ancestorReplicationType), "Bad ancestorReplicationType")

	if child:IsA("ModuleScript") then
		self:_trackModuleScript(child, ancestorReplicationType)
	elseif child:IsA("Folder") then
		self:_trackFolder(child, ancestorReplicationType)
	end
end

function PackageTracker._trackFolder(
	self: PackageTracker,
	child: Instance,
	ancestorReplicationType: ReplicationType.ReplicationType
)
	self:_trackChildrenAndReplicationType(child, ancestorReplicationType)
end

function PackageTracker._trackModuleScript(
	self: PackageTracker,
	child: ModuleScript,
	ancestorReplicationType: ReplicationType.ReplicationType
)
	self:_storeModuleScript(child.Name, child, ancestorReplicationType)
end

function PackageTracker._storeModuleScript(
	self: PackageTracker,
	moduleScriptName: string,
	child: ModuleScript,
	ancestorReplicationType: ReplicationType.ReplicationType
): () -> ()
	if self._packageModuleScriptMap[moduleScriptName] then
		local original = self._packageModuleScriptMap[moduleScriptName].moduleScript
		local isOriginalQuentyOrDaimywil = original:FindFirstAncestor("@quenty") ~= nil
			or original:FindFirstAncestor("@daimywil") ~= nil
		if isOriginalQuentyOrDaimywil then
			return function() end
		end
	end

	local data: ModuleScriptInfo = {
		moduleScript = child,
		replicationType = ancestorReplicationType,
	}
	self._packageModuleScriptMap[moduleScriptName] = data

	return function()
		if self._packageModuleScriptMap[moduleScriptName] == data then
			self._packageModuleScriptMap[moduleScriptName] = nil
		end
	end
end

function PackageTracker._handleNodeModulesChildAdded(self: PackageTracker, child: Instance)
	if child:IsA("ObjectValue") then
		-- Assume symlinked package
		self:_trackNodeModulesObjectValue(child)
	elseif child:IsA("Folder") then
		self:_trackNodeModulesChildFolder(child)
	elseif child:IsA("ModuleScript") then
		self:_trackAddPackage(child)
	end
end

function PackageTracker._trackNodeModulesChildFolder(self: PackageTracker, child: Instance)
	local childName = child.Name

	-- like @quenty
	if DependencyUtils.isPackageGroup(childName) then
		return self:_trackScopedChildFolder(childName, child)
	else
		return self:_tryStorePackage(childName, child)
	end
end

function PackageTracker._trackNodeModulesObjectValue(self: PackageTracker, objectValue: ObjectValue)
	self:_tryStorePackage(objectValue.Name, objectValue.Value)
end

function PackageTracker._trackScopedChildFolder(self: PackageTracker, scopeName: string, parent: Instance)
	for _, child in parent:GetChildren() do
		self:_handleScopedModulesChildAdded(scopeName, child)
	end
end

function PackageTracker._handleScopedModulesChildAdded(self: PackageTracker, scopeName: string, child: Instance)
	if child:IsA("ObjectValue") then
		self:_trackScopedNodeModulesObjectValue(scopeName, child)
	elseif child:IsA("Folder") or child:IsA("ModuleScript") then
		self:_trackAddScopedPackage(scopeName, child)
	end
end

function PackageTracker._trackScopedNodeModulesObjectValue(
	self: PackageTracker,
	scopeName: string,
	objectValue: ObjectValue
)
	self:_tryStorePackage(scopeName .. "/" .. objectValue.Name, objectValue.Value)
end

function PackageTracker._trackAddScopedPackage(self: PackageTracker, scopeName: string, child: Instance)
	assert(type(scopeName) == "string", "Bad scopeName")
	assert(typeof(child) == "Instance", "Bad child")

	self:_tryStorePackage(scopeName .. "/" .. child.Name, child)
end

function PackageTracker._trackAddPackage(self: PackageTracker, child: Instance)
	self:_tryStorePackage(child.Name, child)
end

function PackageTracker._tryStorePackage(
	self: PackageTracker,
	fullPackageName: string,
	packageInst: Instance?
): (() -> ())?
	assert(type(fullPackageName) == "string", "Bad fullPackageName")

	if not packageInst then
		return nil
	end

	self._subpackagesMap[fullPackageName] = packageInst

	local packageTracker = self._packageTrackerProvider:AddPackageRoot(packageInst)
	table.insert(self._subpackagesTrackerList, packageTracker)

	return function()
		local index = table.find(self._subpackagesTrackerList, packageTracker)
		if index then
			table.remove(self._subpackagesTrackerList, index)
		end

		if self._subpackagesMap[fullPackageName] == packageInst then
			self._subpackagesMap[fullPackageName] = nil
		end
	end
end

return PackageTracker
