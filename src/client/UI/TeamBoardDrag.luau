--!strict
local UserInputService = game:GetService("UserInputService")
local Theme = require(script.Parent.Theme)
local Controls = require(script.Parent.Components.Controls)

local TeamBoardDrag = {}
type Pending = { source: TextButton, uid: string, name: string, origin: Vector2, dragging: boolean }

function TeamBoardDrag.mount(
	playerGui: PlayerGui,
	screen: ScreenGui,
	boardScroll: ScrollingFrame,
	cells: { TextButton },
	canInteract: () -> boolean,
	selectUnit: (string) -> (),
	placeUnit: (string, number) -> ()
): (TextButton, () -> (string?, string?)) -> ()
	local ghost = Controls.label("", UDim2.fromOffset(3 * Theme.touch, Theme.touch), screen)
	ghost.AnchorPoint = Vector2.new(0.5, 1)
	ghost.BackgroundTransparency = 0
	ghost.BackgroundColor3 = Theme.focus
	ghost.TextXAlignment = Enum.TextXAlignment.Center
	ghost.ZIndex = 5
	ghost.Visible = false
	Controls.round(ghost)

	local pending: Pending? = nil
	local function cancel(): ()
		pending = nil
		ghost.Visible = false
	end
	local function hits(position: Vector3): { GuiObject }
		return playerGui:GetGuiObjectsAtPosition(position.X, position.Y) :: { GuiObject }
	end
	local function contains(target: GuiObject, underPointer: { GuiObject }): boolean
		for _, gui in underPointer do
			if gui == target or gui:IsDescendantOf(target) then
				return true
			end
		end
		return false
	end

	UserInputService.InputChanged:Connect(function(input: InputObject)
		local drag = pending
		if not drag or input.UserInputType ~= Enum.UserInputType.MouseMovement then
			return
		end
		if not canInteract() then
			cancel()
			return
		end
		local point = Vector2.new(input.Position.X, input.Position.Y)
		if not drag.dragging and (point - drag.origin).Magnitude >= Theme.dragThreshold then
			drag.dragging = true
			boardScroll.CanvasPosition = Vector2.zero
			ghost.Text = drag.name
			ghost.Visible = true
		end
		ghost.Position = UDim2.fromOffset(point.X, point.Y - Theme.gap)
	end)

	UserInputService.InputEnded:Connect(function(input: InputObject)
		local drag = pending
		if not drag or input.UserInputType ~= Enum.UserInputType.MouseButton1 then
			return
		end
		cancel()
		if not canInteract() then
			return
		end
		local underPointer = hits(input.Position)
		if drag.dragging then
			for index, cell in cells do
				if contains(cell, underPointer) then
					placeUnit(drag.uid, index)
					break
				end
			end
		elseif drag.source.Parent and contains(drag.source, underPointer) then
			selectUnit(drag.uid)
		end
	end)
	UserInputService.WindowFocusReleased:Connect(cancel)
	screen:GetPropertyChangedSignal("Enabled"):Connect(cancel)

	return function(button: TextButton, unit: () -> (string?, string?)): ()
		button.InputBegan:Connect(function(input: InputObject)
			if input.UserInputType ~= Enum.UserInputType.MouseButton1 or not canInteract() then
				return
			end
			local uid, name = unit()
			if uid and name then
				pending = {
					source = button,
					uid = uid,
					name = name,
					origin = Vector2.new(input.Position.X, input.Position.Y),
					dragging = false,
				}
			end
		end)
		button.Activated:Connect(function(input: InputObject)
			if input.UserInputType ~= Enum.UserInputType.MouseButton1 and canInteract() then
				local uid = unit()
				if uid then
					selectUnit(uid)
				end
			end
		end)
	end
end

return table.freeze(TeamBoardDrag)
