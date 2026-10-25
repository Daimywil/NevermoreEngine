--!strict
--[=[
	@class RxStateStackUtils
]=]

local require = require(script.Parent.loader).load(script)

local Brio = require("Brio")
local Maid = require("Maid")
local Observable = require("Observable")
local StateStack = require("StateStack")

local RxStateStackUtils = {}

--[=[
	Converts the observable of Brios into a statestack.

	@param defaultValue T?
	@return (source: Observable<Brio<T>>) -> Observable<T?>
]=]
function RxStateStackUtils.topOfStack<T>(defaultValue: T?): Observable.Transformer<(Brio.Brio<T>), (T)>
	return function(source)
		return Observable.new(function(sub)
			local stateStack = StateStack.new(defaultValue)

			local subscription = source:Subscribe(function(brio)
				if not brio:IsDead() then
					brio:ToMaid():GiveTask(stateStack:PushState(brio:GetValue()))
				end
			end)

			local function update()
				sub:Fire(stateStack:GetState())
			end

			local connection = stateStack.Changed:Connect(update)

			update()

			return function()
				connection:Disconnect()
				subscription:Destroy()
			end
		end) :: any
	end
end

--[=[
	Creates a state stack from the brio's value. The state stack holds the last
	value seen that is valid.

	@param observable Observable<Brio<T>>
	@return StateStack<T>
]=]
function RxStateStackUtils.createStateStack<T>(observable: Observable.Observable<Brio.Brio<T>>): StateStack.StateStack<T>
	local stateStack: StateStack.StateStack<T> = StateStack.new(nil) :: any

	stateStack._maid:GiveTask(observable:Subscribe(function(value)
		assert(Brio.isBrio(value), "Observable must emit brio")

		if value:IsDead() then
			return
		end

		local maid = value:ToMaid()
		maid:GiveTask(stateStack:PushState(value:GetValue()))
	end))

	return stateStack
end

return RxStateStackUtils
