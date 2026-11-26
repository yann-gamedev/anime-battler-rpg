--!strict
local Controls = require(script.Parent.Controls)
local Theme = require(script.Parent.Parent.Theme)

local Toast = {}

function Toast.create(size: UDim2, parent: Instance): TextLabel
	return Controls.label("", size, parent)
end

function Toast.show(label: TextLabel, message: string, isError: boolean?): ()
	label.Text = message
	label.TextColor3 = if isError then Theme.error else Theme.muted
end

return table.freeze(Toast)
