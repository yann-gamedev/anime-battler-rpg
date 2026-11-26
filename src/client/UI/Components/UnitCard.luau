--!strict
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Types = require(ReplicatedStorage.Shared.Types)
local Controls = require(script.Parent.Controls)
local Theme = require(script.Parent.Parent.Theme)

export type View = { button: TextButton, badge: TextLabel, title: TextLabel, detail: TextLabel, stroke: UIStroke }
local UnitCard = {}

function UnitCard.create(parent: Instance): View
	local button = Controls.button("", UDim2.new(1, 0, 0, Theme.cardHeight), parent)
	button.TextTransparency = 1
	local stroke = Instance.new("UIStroke")
	stroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
	stroke.Parent = button

	local badge = Controls.label("", UDim2.fromOffset(Theme.badgeSize, Theme.badgeSize), button)
	badge.AnchorPoint = Vector2.new(0, 0.5)
	badge.Position = UDim2.new(0, Theme.gap, 0.5, 0)
	badge.TextXAlignment = Enum.TextXAlignment.Center
	badge.Font = Theme.bold
	badge.BackgroundTransparency = 0
	badge.TextColor3 = Theme.background
	Controls.round(badge)

	local contentOffset = Theme.badgeSize + 2 * Theme.gap
	local title = Controls.label("", UDim2.new(1, -contentOffset - Theme.gap, 0, Theme.lineHeight), button)
	title.Position = UDim2.new(0, contentOffset, 0.5, -Theme.lineHeight)
	title.Font = Theme.bold
	title.TextWrapped = false
	title.TextTruncate = Enum.TextTruncate.AtEnd
	local detail = Controls.label("", title.Size, button)
	detail.Position = UDim2.new(0, contentOffset, 0.5, 0)
	detail.TextColor3 = Theme.muted
	detail.TextWrapped = false
	detail.TextTruncate = Enum.TextTruncate.AtEnd
	return { button = button, badge = badge, title = title, detail = detail, stroke = stroke }
end

function UnitCard.update(
	view: View,
	unit: Types.TeamBoardUnit,
	placed: number?,
	selected: boolean,
	enabled: boolean
): ()
	view.title.Text = if placed then string.format("%s  ·  Slot %d", unit.name, placed) else unit.name
	view.button.Text = view.title.Text
	view.detail.Text =
		string.format("%s  ·  %s  ·  Lv %d  ·  %d★", unit.element, unit.rarity, unit.level, unit.stars)
	view.badge.Text = Theme.elementIcon[unit.element]
	view.badge.BackgroundColor3 = Theme.element[unit.element]
	view.stroke.Color = Theme.rarity[unit.rarity] or Theme.border
	view.button.BackgroundColor3 = if selected then Theme.accent else Theme.button
	Controls.setEnabled(view.button, enabled)
end

return table.freeze(UnitCard)
