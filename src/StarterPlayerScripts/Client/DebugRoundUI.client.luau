--[[
	DebugRoundUI — a bare-bones round screen for playtesting the server.

	Temporary: the real round UI and HUD (prompt 4) replaces this file.
	Shows the ring state, the feed, an answer box, Dive Deeper, and pick
	buttons on Midnight/Abyss. Also prints every RingUpdate to the output.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local player = Players.LocalPlayer
local remotes = ReplicatedStorage:WaitForChild("RemoteEvents")
local SubmitAnswer = remotes:WaitForChild("SubmitAnswer") :: RemoteEvent
local PickTarget = remotes:WaitForChild("PickTarget") :: RemoteEvent
local DiveDeeper = remotes:WaitForChild("DiveDeeper") :: RemoteEvent
local RingUpdate = remotes:WaitForChild("RingUpdate") :: RemoteEvent

local OUTLINE = Color3.fromHex("14162E")
local FONT = Enum.Font.FredokaOne

local gui = Instance.new("ScreenGui")
gui.Name = "DebugRoundUI"
gui.ResetOnSpawn = false
gui.IgnoreGuiInset = true
gui.Parent = player:WaitForChild("PlayerGui")

local function stroke(parent: Instance, thickness: number)
	local s = Instance.new("UIStroke")
	s.Color = OUTLINE
	s.Thickness = thickness
	s.Parent = parent
end

local function label(props): TextLabel
	local l = Instance.new("TextLabel")
	l.BackgroundTransparency = 1
	l.Font = FONT
	l.TextColor3 = Color3.new(1, 1, 1)
	l.TextScaled = true
	for k, v in props do
		(l :: any)[k] = v
	end
	stroke(l, 2)
	l.Parent = gui
	return l
end

local function button(text: string, color: Color3, pos: UDim2, size: UDim2): TextButton
	local b = Instance.new("TextButton")
	b.Text = text
	b.Font = FONT
	b.TextScaled = true
	b.TextColor3 = Color3.new(1, 1, 1)
	b.BackgroundColor3 = color
	b.Position = pos
	b.Size = size
	b.AutoButtonColor = true
	Instance.new("UICorner", b).CornerRadius = UDim.new(0, 10)
	local s = Instance.new("UIStroke")
	s.Color = OUTLINE
	s.Thickness = 3
	s.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
	s.Parent = b
	b.Parent = gui
	return b
end

local status = label({
	Size = UDim2.new(0.5, 0, 0, 34),
	Position = UDim2.new(0.25, 0, 0, 44),
	Text = "Sit on a seat in a ring to play",
})
local detail = label({
	Size = UDim2.new(0.5, 0, 0, 24),
	Position = UDim2.new(0.25, 0, 0, 80),
	Text = "",
})
local feedLabel = label({
	Size = UDim2.new(0.3, 0, 0, 120),
	Position = UDim2.new(0, 12, 0, 44),
	TextScaled = false,
	TextSize = 15,
	TextWrapped = true,
	TextXAlignment = Enum.TextXAlignment.Left,
	TextYAlignment = Enum.TextYAlignment.Top,
	Text = "",
})
local banner = label({
	Size = UDim2.new(0.6, 0, 0, 40),
	Position = UDim2.new(0.2, 0, 0.3, 0),
	TextColor3 = Color3.fromRGB(255, 190, 60),
	Visible = false,
})

local box = Instance.new("TextBox")
box.PlaceholderText = "Type an answer"
box.Text = ""
box.ClearTextOnFocus = false
box.Font = FONT
box.TextScaled = true
box.TextColor3 = OUTLINE
box.BackgroundColor3 = Color3.new(1, 1, 1)
box.Size = UDim2.new(0.4, 0, 0, 52)
box.Position = UDim2.new(0.15, 0, 1, -70)
Instance.new("UICorner", box).CornerRadius = UDim.new(0, 10)
stroke(box, 3)
box.Parent = gui

local send = button("Send", Color3.fromRGB(70, 200, 90), UDim2.new(0.56, 0, 1, -70), UDim2.new(0.12, 0, 0, 52))
local dive = button("Dive Deeper", Color3.fromRGB(70, 110, 230), UDim2.new(0.69, 0, 1, -70), UDim2.new(0.16, 0, 0, 52))

local pickFrame = Instance.new("Frame")
pickFrame.BackgroundTransparency = 1
pickFrame.Size = UDim2.new(0.7, 0, 0, 56)
pickFrame.Position = UDim2.new(0.15, 0, 1, -140)
pickFrame.Visible = false
local layout = Instance.new("UIListLayout")
layout.FillDirection = Enum.FillDirection.Horizontal
layout.Padding = UDim.new(0, 8)
layout.Parent = pickFrame
pickFrame.Parent = gui

local state = nil
local feed = {}

local function myTurn(): boolean
	return state ~= nil and state.holder == player.UserId and (state.phase == "playing" or state.phase == "picking")
end

local function nameOf(userId: number?): string
	if state and userId then
		for _, s in state.seats do
			if s.userId == userId then
				return s.name
			end
		end
	end
	return "?"
end

local function rebuildPicks()
	for _, c in pickFrame:GetChildren() do
		if c:IsA("TextButton") then
			c:Destroy()
		end
	end
	local picking = state and state.phase == "picking" and state.holder == player.UserId
	pickFrame.Visible = picking
	if not picking then
		return
	end
	for _, s in state.seats do
		if s.status == "alive" and s.userId ~= player.UserId then
			local b = button(s.name, Color3.fromRGB(160, 80, 230), UDim2.new(), UDim2.new(0, 150, 1, 0))
			b.Parent = pickFrame
			b.Activated:Connect(function()
				PickTarget:FireServer(s.userId)
			end)
		end
	end
end

local function submit()
	if box.Text ~= "" then
		SubmitAnswer:FireServer(box.Text)
		box.Text = ""
	end
	if myTurn() then
		box:CaptureFocus()
	end
end

send.Activated:Connect(submit)
box.FocusLost:Connect(function(enter)
	if enter then
		submit()
	end
end)
dive.Activated:Connect(function()
	DiveDeeper:FireServer()
end)

RingUpdate.OnClientEvent:Connect(function(msg)
	if msg.kind == "state" then
		local wasMine = myTurn()
		state = msg.ring
		rebuildPicks()
		if myTurn() and not wasMine then
			box:CaptureFocus()
		end
	elseif msg.kind == "feed" then
		print("[Feed]", msg.line)
		table.insert(feed, msg.line)
		if #feed > 6 then
			table.remove(feed, 1)
		end
		feedLabel.Text = table.concat(feed, "\n")
	elseif msg.kind == "reply" then
		print("[Reply]", msg.ok, msg.reason, msg.display)
		if not msg.ok then
			-- shake
			local base = box.Position
			task.spawn(function()
				for i = 1, 6 do
					box.Position = base + UDim2.fromOffset(if i % 2 == 0 then 8 else -8, 0)
					task.wait(0.03)
				end
				box.Position = base
			end)
		end
	elseif msg.kind == "banner" then
		print("[Banner]", msg.name, msg.display)
		banner.Text = string.format("ABYSS! %s said %s", msg.name, msg.display)
		banner.Visible = true
		task.delay(3, function()
			banner.Visible = false
		end)
	elseif msg.kind == "left" then
		state = nil
		rebuildPicks()
	end
end)

local PUFF = { "", "·", "··", "···", "!!! RED !!!" }

RunService.RenderStepped:Connect(function()
	local mine = myTurn()
	box.Visible = mine and state.phase == "playing"
	send.Visible = box.Visible
	dive.Visible = box.Visible and not state.diveUsed
	if not state then
		status.Text = "Sit on a seat in a ring to play"
		detail.Text = ""
		return
	end
	local left = if state.endsAt then math.max(0, state.endsAt - workspace:GetServerTimeNow()) else nil
	local phase = state.phase
	if phase == "waiting" then
		status.Text = string.format("%s ring · %d/%d · need %d", if state.ranked then "Ranked" else "Casual", #state.seats, state.seatCount, state.minPlayers)
		detail.Text = ""
	elseif phase == "countdown" then
		status.Text = string.format("Starting in %d", math.ceil(left or 0))
		detail.Text = string.format("%d/%d seated", #state.seats, state.seatCount)
	elseif phase == "playing" or phase == "picking" or phase == "between" then
		status.Text = state.prompt or ""
		if phase == "between" then
			detail.Text = "Next round soon…"
		elseif phase == "picking" then
			detail.Text = string.format("%s is picking · %d", nameOf(state.holder), math.ceil(left or 0))
		else
			local dived = if state.diveEndsAt then string.format(" · DIVING %d", math.ceil(state.diveEndsAt - workspace:GetServerTimeNow())) else ""
			detail.Text = string.format("%s %s%s", if mine then "Your turn!" else nameOf(state.holder) .. " is thinking…", PUFF[state.puff + 1] or "", dived)
		end
	elseif phase == "results" then
		local r = state.results
		status.Text = if r and r.winnerName then r.winnerName .. " wins!" else "No winner"
		detail.Text = string.format("Next game in %d", math.ceil(left or 0))
	end
end)
