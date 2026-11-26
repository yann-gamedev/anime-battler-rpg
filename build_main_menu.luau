-- Builds StarterGui.MainMenu (Play / Settings / Quit). Run in Studio edit mode
-- (execute_luau or Command Bar). Re-running replaces the previous MainMenu.
local StarterGui = game:GetService("StarterGui")

local old = StarterGui:FindFirstChild("MainMenu")
if old then
	old:Destroy()
end

local IDLE = Color3.fromRGB(38, 42, 58)
local TEXT = Color3.fromRGB(235, 238, 245)

local function new(class, props, parent)
	local inst = Instance.new(class)
	for key, value in props do
		inst[key] = value
	end
	inst.Parent = parent
	return inst
end

local function button(name, text, order, parent)
	local b = new("TextButton", {
		Name = name,
		Text = text,
		LayoutOrder = order,
		Size = UDim2.new(1, 0, 0, 56),
		BackgroundColor3 = IDLE,
		AutoButtonColor = false,
		TextColor3 = TEXT,
		FontFace = Font.fromEnum(Enum.Font.GothamMedium),
		TextSize = 22,
	}, parent)
	new("UICorner", { CornerRadius = UDim.new(0, 8) }, b)
	new("UIStroke", {
		ApplyStrokeMode = Enum.ApplyStrokeMode.Border,
		Color = Color3.fromRGB(70, 76, 100),
		Thickness = 1,
	}, b)
	return b
end

local function panel(name, title, parent)
	local p = new("Frame", {
		Name = name,
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromScale(0.3, 0.6),
		BackgroundTransparency = 1,
	}, parent)
	new("UISizeConstraint", { MinSize = Vector2.new(260, 320), MaxSize = Vector2.new(420, 520) }, p)
	new("UIListLayout", {
		SortOrder = Enum.SortOrder.LayoutOrder,
		HorizontalAlignment = Enum.HorizontalAlignment.Center,
		VerticalAlignment = Enum.VerticalAlignment.Center,
		Padding = UDim.new(0, 12),
	}, p)
	local t = new("TextLabel", {
		Name = "Title",
		Text = title,
		LayoutOrder = 0,
		Size = UDim2.new(1, 0, 0, 80),
		BackgroundTransparency = 1,
		TextColor3 = TEXT,
		FontFace = Font.fromEnum(Enum.Font.GothamBold),
		TextScaled = true,
	}, p)
	new("UITextSizeConstraint", { MaxTextSize = 56 }, t)
	return p
end

local gui = new("ScreenGui", {
	Name = "MainMenu",
	ResetOnSpawn = false,
	IgnoreGuiInset = true,
	DisplayOrder = 10,
	ZIndexBehavior = Enum.ZIndexBehavior.Sibling,
}, StarterGui)

local bg = new("Frame", {
	Name = "Background",
	Size = UDim2.fromScale(1, 1),
	BackgroundColor3 = Color3.new(1, 1, 1),
	BorderSizePixel = 0,
}, gui)
new("UIGradient", {
	Rotation = 90,
	Color = ColorSequence.new(Color3.fromRGB(28, 32, 46), Color3.fromRGB(12, 13, 18)),
}, bg)
new("UIPadding", {
	PaddingTop = UDim.new(0, 24),
	PaddingBottom = UDim.new(0, 24),
	PaddingLeft = UDim.new(0, 24),
	PaddingRight = UDim.new(0, 24),
}, bg)

local menu = panel("Menu", "Battler RPG", bg)
button("PlayButton", "Play", 1, menu)
button("SettingsButton", "Settings", 2, menu)
button("QuitButton", "Quit", 3, menu)

local settings = panel("SettingsPanel", "Settings", bg)
settings.Visible = false
button("MusicButton", "Music: On", 1, settings)
button("BackButton", "Back", 2, settings)

local controller = new("LocalScript", { Name = "MenuController" }, gui)
controller.Source = [==[
local Players = game:GetService("Players")
local GuiService = game:GetService("GuiService")
local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")

local player = Players.LocalPlayer
local gui = script.Parent
local menu = gui.Background.Menu
local settings = gui.Background.SettingsPanel

local IDLE = Color3.fromRGB(38, 42, 58)
local HOVER = Color3.fromRGB(62, 68, 94)
local fade = TweenInfo.new(0.12)

local function hover(b)
	local function to(c)
		TweenService:Create(b, fade, { BackgroundColor3 = c }):Play()
	end
	b.MouseEnter:Connect(function() to(HOVER) end)
	b.MouseLeave:Connect(function() to(IDLE) end)
	b.SelectionGained:Connect(function() to(HOVER) end)
	b.SelectionLost:Connect(function() to(IDLE) end)
end

for _, p in { menu, settings } do
	for _, b in p:GetChildren() do
		if b:IsA("TextButton") then hover(b) end
	end
end

local function show(p, first)
	menu.Visible = p == menu
	settings.Visible = p == settings
	if UserInputService.GamepadEnabled then
		GuiService.SelectedObject = first
	end
end

-- Other systems read this attribute to play or mute music.
player:SetAttribute("MusicEnabled", true)
local function musicText()
	settings.MusicButton.Text = player:GetAttribute("MusicEnabled") and "Music: On" or "Music: Off"
end

menu.PlayButton.Activated:Connect(function()
	GuiService.SelectedObject = nil
	gui.Enabled = false
end)
menu.SettingsButton.Activated:Connect(function() show(settings, settings.MusicButton) end)
-- Roblox cannot close the client from a script; Kick is the standard "quit".
menu.QuitButton.Activated:Connect(function() player:Kick("Thanks for playing!") end)
settings.MusicButton.Activated:Connect(function()
	player:SetAttribute("MusicEnabled", not player:GetAttribute("MusicEnabled"))
	musicText()
end)
settings.BackButton.Activated:Connect(function() show(menu, menu.PlayButton) end)

musicText()
show(menu, menu.PlayButton)
]==]

return "MainMenu created in StarterGui"
