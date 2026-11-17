--!nonstrict
--[[
	@class Rx.spec.lua
]]

local require = (require :: any)(
		game:GetService("ServerScriptService"):FindFirstChild("LoaderUtils", true).Parent
	).bootstrapStory(script) :: typeof(require(script.Parent.loader).load(script))

local Jest = require("Jest")
local Rx = require("Rx")

local describe = Jest.Globals.describe
local expect = Jest.Globals.expect
local it = Jest.Globals.it

describe("Rx.combineLatest({})", function()
	local observe = Rx.combineLatest({})
	local externalResult

	it("should execute immediately", function()
		local sub = observe:Subscribe(function(result)
			externalResult = result
		end)

		expect(externalResult).toEqual(expect.any("table"))
		sub:Destroy()
	end)
end)

describe("Rx.combineLatest({ value = 5 })", function()
	local observe = Rx.combineLatest({ value = 5 })
	local externalResult

	it("should execute immediately", function()
		local sub = observe:Subscribe(function(result)
			externalResult = result
		end)

		expect(externalResult).toEqual(expect.any("table"))
		expect(externalResult.value).toEqual(5)
		sub:Destroy()
	end)
end)

describe("Rx.combineLatest({ value = Rx.of(5) })", function()
	local observe = Rx.combineLatest({ value = Rx.of(5) })
	local externalResult

	it("should execute immediately", function()
		local sub = observe:Subscribe(function(result)
			externalResult = result
		end)

		expect(externalResult).toEqual(expect.any("table"))
		expect(externalResult.value).toEqual(5)
		sub:Destroy()
	end)
end)

describe("Rx.skipWhile", function()
	it("should emit the value that ends the skipping and every value after it", function()
		local results = {}
		local sub = Rx.of(0, 0, 1, 0, 2)
			:Pipe({
				Rx.skipWhile(function(_, value)
					return value == 0
				end),
			})
			:Subscribe(function(value)
				table.insert(results, value)
			end)

		expect(results).toEqual({ 1, 0, 2 })
		sub:Destroy()
	end)

	it("should pass a 1-based index to the predicate", function()
		local indexes = {}
		local sub = Rx.of("a", "b", "c")
			:Pipe({
				Rx.skipWhile(function(index)
					table.insert(indexes, index)
					return index < 2
				end),
			})
			:Subscribe(function() end)

		expect(indexes).toEqual({ 1, 2 })
		sub:Destroy()
	end)
end)
