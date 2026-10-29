--[[
	Fakes just enough of Roblox to load ModuleScripts from src/ under Lune:
	`script` / `script.Parent.X` / `:WaitForChild`, a `require` that accepts
	those fake instances, `Color3` and `Random`.

	local Shim = require("./shim")
	local folder = Shim.folder("src/ServerStorage/ShrimpillionAnswers")
	local Matcher = Shim.require(folder.AnswerMatcher)
]]

local fs = require("@lune/fs")
local luau = require("@lune/luau")
local roblox = require("@lune/roblox")

local Shim = {}

-------------------------------------------------------------------------------
-- Color3
-------------------------------------------------------------------------------

local Color3 = {}
Color3.__index = Color3

function Color3.new(r: number?, g: number?, b: number?)
	return setmetatable({ R = r or 0, G = g or 0, B = b or 0 }, Color3)
end

function Color3.fromRGB(r: number?, g: number?, b: number?)
	return Color3.new((r or 0) / 255, (g or 0) / 255, (b or 0) / 255)
end

function Color3.__tostring(c)
	return string.format("Color3(%d, %d, %d)", math.round(c.R * 255), math.round(c.G * 255), math.round(c.B * 255))
end

-------------------------------------------------------------------------------
-- Random (mulberry32: seedable, so tests can be repeated)
-------------------------------------------------------------------------------

local Random = {}
Random.__index = Random

local seedCounter = 0

function Random.new(seed: number?)
	if seed == nil then
		seedCounter += 1
		seed = os.clock() * 1e6 + seedCounter * 7919
	end
	return setmetatable({ _state = bit32.band(math.floor(seed :: number), 0xFFFFFFFF) }, Random)
end

local function mul32(a: number, b: number): number
	-- 32-bit multiply without losing precision in doubles
	local aHi, aLo = bit32.rshift(a, 16), bit32.band(a, 0xFFFF)
	return bit32.band(aLo * b + bit32.lshift(bit32.band(aHi * b, 0xFFFF), 16), 0xFFFFFFFF)
end

local function next32(self): number
	self._state = bit32.band(self._state + 0x6D2B79F5, 0xFFFFFFFF)
	local t = self._state
	t = mul32(bit32.bxor(t, bit32.rshift(t, 15)), bit32.bor(t, 1))
	t = bit32.bxor(t, bit32.band(t + mul32(bit32.bxor(t, bit32.rshift(t, 7)), bit32.bor(t, 61)), 0xFFFFFFFF))
	return bit32.bxor(t, bit32.rshift(t, 14))
end

function Random.NextNumber(self, min: number?, max: number?): number
	local u = next32(self) / 4294967296
	local lo, hi = min or 0, max or 1
	return lo + (hi - lo) * u
end

function Random.NextInteger(self, min: number, max: number): number
	return min + math.floor(next32(self) / 4294967296 * (max - min + 1))
end

-------------------------------------------------------------------------------
-- fake instances backed by the file system (Rojo naming)
-------------------------------------------------------------------------------

local Instance = {}

local function stripExt(name: string): string?
	return string.match(name, "^(.-)%.luau$") or string.match(name, "^(.-)%.lua$")
end

local function makeNode(path: string, name: string, parent: any, isModule: boolean)
	local node = { _path = path, _isModule = isModule, Name = name, Parent = parent }
	return setmetatable(node, Instance)
end

-- scanned up front: Lune's fs calls yield, which isn't allowed inside __index
local function scan(node)
	local kids = {}
	rawset(node, "_kids", kids)
	if node._isModule then
		return
	end
	for _, entry in fs.readDir(node._path) do
		local full = node._path .. "/" .. entry
		if fs.isDir(full) then
			kids[entry] = makeNode(full, entry, node, false)
			scan(kids[entry])
		else
			local base = stripExt(entry)
			if base and not string.find(base, "%.") then -- skip .server/.client scripts
				kids[base] = makeNode(full, base, node, true)
				scan(kids[base])
			end
		end
	end
end

local function children(node): { [string]: any }
	return rawget(node, "_kids")
end

Instance.__index = function(node, key)
	local method = Instance[key]
	if method then
		return method
	end
	local child = children(node)[key]
	if child == nil then
		error(string.format("%s is not a valid member of %s", tostring(key), node._path), 2)
	end
	return child
end

Instance.__tostring = function(node)
	return node.Name
end

function Instance.FindFirstChild(node, name: string)
	return children(node)[name]
end

function Instance.WaitForChild(node, name: string)
	local child = children(node)[name]
	if child == nil then
		error("WaitForChild would hang forever: no " .. name .. " in " .. node._path, 2)
	end
	return child
end

function Instance.GetChildren(node)
	local out = {}
	for _, c in children(node) do
		table.insert(out, c)
	end
	table.sort(out, function(a, b)
		return a.Name < b.Name
	end)
	return out
end

-------------------------------------------------------------------------------
-- require
-------------------------------------------------------------------------------

local loaded: { [any]: any } = {}
local loading: { [any]: boolean } = {}

local function fakeRequire(target: any)
	if type(target) ~= "table" or getmetatable(target) ~= Instance then
		return require(target) -- a real Lune require ("@lune/fs" etc.)
	end
	if loaded[target] ~= nil then
		return loaded[target]
	end
	assert(target._isModule, "require() of a non-module: " .. target._path)
	assert(not loading[target], "require cycle at " .. target._path)
	loading[target] = true
	local source = fs.readFile(target._path)
	local env = setmetatable({
		script = target,
		require = fakeRequire,
		Color3 = Color3,
		Random = Random,
		Vector3 = roblox.Vector3,
	}, { __index = getfenv(0) })
	local chunk = luau.load(source, { debugName = target._path, environment = env })
	local result = chunk()
	loading[target] = nil
	loaded[target] = result
	return result
end

function Shim.folder(path: string)
	assert(fs.isDir(path), "Not a folder: " .. path .. " (run from the repo root)")
	local name = string.match(path, "([^/]+)/*$") :: string
	local root = makeNode(path, name, nil, false)
	scan(root)
	return root
end

Shim.require = fakeRequire
Shim.Color3 = Color3
Shim.Random = Random

return Shim
