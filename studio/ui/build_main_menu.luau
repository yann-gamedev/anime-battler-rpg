--!strict
-- Builds StarterGui.MainMenu (Play / Settings / Quit). Run in Studio edit mode
-- (execute_luau or Command Bar). Re-running replaces the previous MainMenu.
local StarterGui = game:GetService("StarterGui")
local StarterPlayer = game:GetService("StarterPlayer")
local client = assert(
	StarterPlayer.StarterPlayerScripts:FindFirstChild("Client"),
	"Connect Rojo in Studio edit mode before building the Main Menu."
)
local Theme = require(client.UI.Theme)

local function new(class: string, props: { [string]: any }, parent: Instance?): any
	local inst: any = Instance.new(class)
	for key, value in props do
		inst[key] = value
	end
	inst.Parent = parent
	return inst
end

local function button(name: string, text: string, order: number, parent: Instance): TextButton
	local b = new("TextButton", {
		Name = name,
		Text = text,
		LayoutOrder = order,
		Size = UDim2.new(1, 0, 0, Theme.menuButtonHeight),
		BackgroundColor3 = Theme.button,
		AutoButtonColor = false,
		TextColor3 = Theme.text,
		Font = Theme.font,
		TextSize = Theme.titleSize,
	}, parent)
	new("UICorner", { CornerRadius = UDim.new(0, Theme.radius) }, b)
	new("UIStroke", {
		ApplyStrokeMode = Enum.ApplyStrokeMode.Border,
		Color = Theme.border,
		Thickness = 1,
	}, b)
	return b
end

local function panel(name: string, title: string, parent: Instance): Frame
	local p = new("Frame", {
		Name = name,
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromScale(1, 1),
		BackgroundTransparency = 1,
	}, parent)
	local width = new("UISizeConstraint", {}, p)
	width.MaxSize = Vector2.new(Theme.menuWidth, width.MaxSize.Y)
	new("UIListLayout", {
		SortOrder = Enum.SortOrder.LayoutOrder,
		HorizontalAlignment = Enum.HorizontalAlignment.Center,
		VerticalAlignment = Enum.VerticalAlignment.Center,
		Padding = UDim.new(0, Theme.gap),
	}, p)
	local t = new("TextLabel", {
		Name = "Title",
		Text = title,
		LayoutOrder = 0,
		Size = UDim2.new(1, 0, 0, Theme.menuTitleHeight),
		BackgroundTransparency = 1,
		TextColor3 = Theme.text,
		Font = Theme.bold,
		TextScaled = true,
	}, p)
	new("UITextSizeConstraint", { MaxTextSize = Theme.menuTitleSize }, t)
	return p
end

local gui = new("ScreenGui", {
	Name = "MainMenu",
	ResetOnSpawn = false,
	ScreenInsets = Enum.ScreenInsets.CoreUISafeInsets,
	DisplayOrder = 10,
	ZIndexBehavior = Enum.ZIndexBehavior.Sibling,
}, nil)

local bg = new("Frame", {
	Name = "Background",
	Size = UDim2.fromScale(1, 1),
	BackgroundColor3 = Color3.new(1, 1, 1),
	BorderSizePixel = 0,
}, gui)
new("UIGradient", {
	Rotation = 90,
	Color = ColorSequence.new(Theme.panel, Theme.background),
}, bg)
new("UIPadding", {
	PaddingTop = UDim.new(0, Theme.padding),
	PaddingBottom = UDim.new(0, Theme.padding),
	PaddingLeft = UDim.new(0, Theme.padding),
	PaddingRight = UDim.new(0, Theme.padding),
}, bg)

local menu = panel("Menu", "Battler RPG", bg)
button("PlayButton", "Play", 1, menu)
button("SettingsButton", "Settings", 2, menu)
button("QuitButton", "Quit", 3, menu)

local settings = panel("SettingsPanel", "Settings", bg)
settings.Visible = false
button("MusicButton", "Music: On", 1, settings)
button("BackButton", "Back", 2, settings)

local old = StarterGui:FindFirstChild("MainMenu")
if old then
	old:Destroy()
end
gui.Parent = StarterGui

return "MainMenu created in StarterGui"
