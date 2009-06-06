local _VERSION = GetAddOnMetadata('oGlow', 'version')

local function argcheck(value, num, ...)
	assert(type(num) == 'number', "Bad argument #2 to 'argcheck' (number expected, got "..type(num)..")")

	for i=1,select("#", ...) do
		if type(value) == select(i, ...) then return end
	end

	local types = strjoin(", ", ...)
	local name = string.match(debugstack(2,2,0), ": in function [`<](.-)['>]")
	error(("Bad argument #%d to '%s' (%s expected, got %s"):format(num, name, types, type(value)), 3)
end

local print = function(...) print("|cff33ff99oGlow:|r ", ...) end
local error = function(...) print("|cffff0000Error:|r "..string.format(...)) end

local pipesTable = {}
local filtersTable = {}
local displaysTable = {}

local activeFilters = {}

local event_metatable = {
	__call = function(funcs, self, ...)
		for _, func in pairs(funcs) do
			func(self, ...)
		end
	end,
}

local oGlow = CreateFrame('Frame', 'oGlow')

-- This is a temporary solution. Right now we just want to enable all pipes and
-- filters.
function oGlow:PLAYER_LOGIN(event)
	for pipe in next, pipesTable do
		self:EnablePipe(pipe)

		for filter in next, filtersTable do
			self:RegisterFilterOnPipe(pipe, filter)
		end
	end

	self:UnregisterEvent(event)
end

--[[ Event API ]]

local RegisterEvent = oGlow.RegisterEvent
function oGlow:RegisterEvent(event, func)
	argcheck(event, 2, 'string')

	if(type(func) == 'string' and type(self[func]) == 'function') then
		func = self[func]
	end

	local curev = self[event]
	if(curev and func) then
		if(type(curev) == 'function') then
			self[event] = setmetatable({curev, func}, event_metatable)
		else
			for _, infunc in next, curev do
				if(infunc == func) then return end
			end

			table.insert(curev, func)
		end
	elseif(self:IsEventRegistered(event)) then
		return
	else
		if(func) then
			self[event] = func
		elseif(not self[event]) then
			error("Handler for event [%s] does not exist.", event)
		end

		RegisterEvent(self, event)
	end
end

local UnregisterEvent = oGlow.UnregisterEvent
function oGlow:UnregisterEvent(event, func)
	argcheck(event, 2, 'string')

	local curev = self[event]
	if(type(curev) == 'table' and func) then
		for k, infunc in pairs(curev) do
			if(infunc == func) then
				curev[k] = nil

				if(#curev == 0) then
					table.remove(curev, k)
					UnregisterEvent(self, event)
				end
			end
		end
	else
		self[event] = nil
		UnregisterEvent(self, event)
	end
end

oGlow:SetScript('OnEvent', function(self, event, ...)
	self[event](self, event, ...)
end)

--[[ Pipe API ]]

function oGlow:RegisterPipe(pipe, enable, disable, update, desc)
	argcheck(pipe, 2, 'string')
	argcheck(enable, 3, 'function')
	argcheck(disable, 4, 'function', 'nil')
	argcheck(update, 5, 'function')
	argcheck(desc, 6, 'string', 'nil')

	-- Silently fail.
	if(pipesTable[pipe]) then
		return nil, string.format('Pipe [%s] is already registered.')
	else
		pipesTable[pipe] = {
			enable = enable;
			disable = disable;
			update = update;
			desc = desc;
		}
	end

	return true
end

function oGlow:IteratePipes(k)
	local n = next(pipesTable, k)
	if(n) then
		return n, pipesTable[n].isActive, pipesTable[n].desc
	end
end

function oGlow:EnablePipe(pipe)
	argcheck(pipe, 2, 'string')

	local ref = pipesTable[pipe]
	if(ref and not ref.isActive) then
		ref.enable(self)
		ref.isActive = true

		return true
	end
end

function oGlow:DisablePipe(pipe)
	argcheck(pipe, 2, 'string')

	local ref = pipesTable[pipe]
	if(ref and ref.isActive) then
		if(ref.disable) then ref.disable(self) end
		ref.isActive = nil

		return true
	end
end

function oGlow:IsPipeEnabled(pipe)
	argcheck(pipe, 2, 'string')

	return pipesTable[pipe].isActive
end

function oGlow:UpdatePipe(pipe)
	argcheck(pipe, 2, 'string')

	local ref = pipesTable[pipe]
	if(ref and ref.isActive) then
		ref.update(self)

		return true
	end
end

--[[ Filter API ]]

function oGlow:RegisterFilter(name, type, filter, desc)
	argcheck(name, 2, 'string')
	argcheck(type, 3, 'string')
	argcheck(filter, 4, 'function')
	argcheck(desc, 5, 'string', 'nil')

	if(filtersTable[name]) then return nil, 'Filter function is already registered.' end
	filtersTable[name] = {type, filter, desc}

	return true
end

function oGlow:IterateFilters(k)
	local n = next(filtersTable, k)
	if(n) then
		return n, filtersTable[n][1], filtersTable[n][3]
	end
end

function oGlow:RegisterFilterOnPipe(pipe, filter)
	argcheck(pipe, 2, 'string')
	argcheck(filter, 3, 'string')

	if(not pipesTable[pipe]) then return nil, 'Pipe does not exist.' end
	if(not filtersTable[filter]) then return nil, 'Filter does not exist.' end
	if(not activeFilters[pipe]) then
		activeFilters[pipe] = {}
		table.insert(activeFilters[pipe], filtersTable[filter])
	else
		filter = filtersTable[filter]
		local ref = activeFilters[pipe]

		for _, func in next, ref do
			if(func == filter) then
				return nil, 'Filter function is already registered.'
			end
		end

		table.insert(ref, filter)
		return true
	end
end

function oGlow:UnregisterFilterOnPipe(pipe, filter)
	argcheck(pipe, 2, 'string')
	argcheck(filter, 3, 'string')

	if(not pipesTable[pipe]) then return nil, 'Pipe does not exist.' end
	if(not filtersTable[filter]) then return nil, 'Filter does not exist.' end

	local ref = activeFilters[pipe]
	if(ref) then
		filter = filtersTable[filter]

		for k, func in next, ref do
			if(func == filter) then
				table.remove(ref, k)
				return true
			end
		end
	end
end

--[[ Display API ]]

function oGlow:RegisterDisplay(name, display)
	argcheck(name, 2, 'string')
	argcheck(display, 3, 'function')

	displaysTable[name] = display
end

--[[ General API ]]

function oGlow:CallFilters(pipe, frame, ...)
	argcheck(pipe, 2, 'string')

	if(not pipesTable[pipe]) then return nil, 'Pipe does not exist.' end

	local ref = activeFilters[pipe]
	if(ref) then
		for _, filter in next, ref do
			local display, func = filter[1], filter[2]

			if(not displaysTable[display]) then return nil, 'Display does not exist.' end
			displaysTable[display](frame, func(...))
		end
	end
end

oGlow:RegisterEvent('PLAYER_LOGIN')

oGlow.argcheck = argcheck

oGlow.version = _VERSION
