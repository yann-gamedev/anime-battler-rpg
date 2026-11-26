--!strict
local GuiService = game:GetService("GuiService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage.Shared
local Types = require(Shared.Types)
local Arena = require(Shared.Config.BattleArena)
local Constants = require(Shared.Config.Constants)
local Remotes = require(Shared.Net.Remotes)
local BattleReplay = require(Shared.BattleReplay)
local Hud = require(script.Parent.Parent.UI.Battle.Hud)
local Renderer = require(script.Parent.Parent.UI.Battle.Renderer)
local UIController = require(script.Parent.UIController)

local PLAYER = Players.LocalPlayer
local CINEMATIC_SETTING = "BattleCinematicsEnabled"
local CINEMATIC_SECONDS = 0.95
local CAMERA_FOV = 52
local VIEW_DIRECTION = Vector3.new(0, 1, -0.6).Unit

type CameraState = {
	kind: Enum.CameraType,
	cframe: CFrame,
	focus: CFrame,
	fov: number,
	fovMode: Enum.FieldOfViewMode,
}
type Session = {
	camera: Camera,
	priorCamera: CameraState,
	scene: Renderer.Scene,
	view: Hud.View,
	result: Types.BattleResult,
	restoreUI: () -> (),
	connections: { RBXScriptConnection },
	frame: RBXScriptConnection?,
	clock: BattleReplay.Clock,
	speed: number,
	shownSeconds: number,
	cinematicRemaining: number,
	cinematicFocus: Vector3?,
	cinematicTween: Tween?,
	ended: boolean,
}

local BattleViewController = {}
local active: Session?

local function cinematicEnabled(): boolean
	return PLAYER:GetAttribute(CINEMATIC_SETTING) ~= false
end

local function framing(camera: Camera, center: Vector3, zoom: number): CFrame
	local viewport = camera.ViewportSize
	local aspect = math.max(0.1, viewport.X / math.max(viewport.Y, 1))
	-- Fit both the board and the two rows of touch controls in portrait and landscape.
	local tangent = math.tan(math.rad(CAMERA_FOV / 2))
	local distance = math.max((Arena.depth + Arena.cellSize) / 1.25, (Arena.width + Arena.cellSize) / (1.5 * aspect))
		/ tangent
	return CFrame.lookAt(center + VIEW_DIRECTION * distance * zoom, center)
end

local function stopCinematic(session: Session): ()
	local tween = session.cinematicTween
	if tween then
		tween:Cancel()
		tween:Destroy()
		session.cinematicTween = nil
	end
	session.cinematicRemaining = 0
	session.cinematicFocus = nil
	session.view.cinematicTitle.Visible = false
	Hud.enable(session.view.skip, false)
	if GuiService.SelectedObject == session.view.skip then
		UIController.focus(session.view.cinematic)
	end
end

local function close(session: Session): ()
	if active ~= session then
		return
	end
	active = nil
	local frame = session.frame
	if frame then
		frame:Disconnect()
		session.frame = nil
	end
	for _, connection in session.connections do
		connection:Disconnect()
	end
	stopCinematic(session)
	Renderer.destroy(session.scene)
	session.restoreUI()
	session.view.screen:Destroy()
	local camera = session.camera
	if camera.Parent then
		camera.FieldOfViewMode = session.priorCamera.fovMode
		camera.FieldOfView = session.priorCamera.fov
		camera.CFrame = session.priorCamera.cframe
		camera.Focus = session.priorCamera.focus
		camera.CameraType = session.priorCamera.kind
	end
end

local function startCinematic(session: Session, event: Types.BattleEvent): boolean
	if event.kind ~= "ultimate" or not event.cinematic or not cinematicEnabled() then
		return false
	end
	local focus = Renderer.unitPosition(session.scene, event.src)
	if not focus then
		return false
	end
	session.cinematicFocus = focus
	session.cinematicRemaining = CINEMATIC_SECONDS
	local tween =
		TweenService:Create(session.camera, TweenInfo.new(0.22), { CFrame = framing(session.camera, focus, 0.56) })
	session.cinematicTween = tween
	tween:Play()
	local title = session.view.cinematicTitle
	title.Text = string.gsub(event.skill, "_", " ")
	title.Visible = true
	Hud.enable(session.view.skip, true)
	return true
end

local function finish(session: Session): ()
	session.ended = true
	Renderer.clearEffects(session.scene)
	local view = session.view
	view.resultTitle.Text = if session.result.winner == "A"
		then "Victory"
		elseif session.result.winner == "B" then "Defeat"
		else "Draw"
	local yours = 0
	for _, survivor in session.result.survivors do
		if survivor.side == "A" then
			yours += 1
		end
	end
	view.resultDetail.Text = string.format("Your survivors: %d", yours)
	view.result.Visible = true
	Hud.enable(view.speed, false)
	Hud.enable(view.cinematic, false)
	Hud.enable(view.exit, false)
	UIController.focus(view.close)
end

local function tick(session: Session, delta: number): ()
	if Workspace.CurrentCamera ~= session.camera or not session.scene.origin:IsDescendantOf(Workspace) then
		close(session)
		return
	end

	local focus = session.cinematicFocus
	if focus then
		session.camera.Focus = CFrame.new(focus)
		session.cinematicRemaining -= delta
		Renderer.step(session.scene, delta)
		if session.cinematicRemaining > 0 then
			return
		end
		stopCinematic(session)
		-- Resume at the exact event tick instead of adding cinematic wall time.
		delta = 0
	end

	local center = session.scene.origin.Position
	session.camera.CFrame = framing(session.camera, center, 1)
	session.camera.Focus = CFrame.new(center)
	if session.ended then
		return
	end

	Renderer.step(session.scene, delta)
	local done = BattleReplay.advance(session.clock, session.result, delta, session.speed, function(event)
		Renderer.apply(session.scene, event, session.speed)
		return startCinematic(session, event)
	end)
	local seconds =
		math.floor(math.min(session.clock.seconds, session.result.ticks / Constants.BATTLE_TICKS_PER_SECOND))
	if seconds ~= session.shownSeconds then
		session.shownSeconds = seconds
		session.view.time.Text = string.format("Replay · %d:%02d", math.floor(seconds / 60), seconds % 60)
	end
	if done then
		finish(session)
	end
end

local function begin(result: Types.BattleResult): ()
	local model = Workspace:FindFirstChild(Arena.modelName)
	local origin = model and model:FindFirstChild(Arena.originName)
	local camera = Workspace.CurrentCamera
	local gui = PLAYER:FindFirstChildOfClass("PlayerGui")
	if not origin or not origin:IsA("BasePart") or not camera or not gui or not gui:IsA("PlayerGui") then
		warn("[BattleReplay] Arena, CurrentCamera or PlayerGui is missing.")
		return
	end

	if active then
		close(active)
	end
	local view = Hud.create(gui)
	local allowDoubleSpeed = RunService:IsStudio()
	Hud.enable(view.speed, allowDoubleSpeed)
	Hud.enable(view.skip, false)

	local session: Session = {
		camera = camera,
		scene = Renderer.new(origin),
		view = view,
		result = result,
		connections = {},
		priorCamera = {
			kind = camera.CameraType,
			cframe = camera.CFrame,
			focus = camera.Focus,
			fov = camera.FieldOfView,
			fovMode = camera.FieldOfViewMode,
		},
		restoreUI = UIController.overlay(view.screen, if allowDoubleSpeed then view.speed else view.cinematic),
		clock = BattleReplay.new(),
		speed = 1,
		shownSeconds = -1,
		cinematicRemaining = 0,
		ended = false,
	}
	active = session
	camera.CameraType = Enum.CameraType.Scriptable
	camera.FieldOfViewMode = Enum.FieldOfViewMode.Vertical
	camera.FieldOfView = CAMERA_FOV

	local function updateCinematicLabel(): ()
		view.cinematic.Text = if cinematicEnabled() then "Cinematics: On" else "Cinematics: Off"
	end
	updateCinematicLabel()
	local function listen(connection: RBXScriptConnection): ()
		table.insert(session.connections, connection)
	end

	listen(view.speed.Activated:Connect(function()
		if allowDoubleSpeed and not session.ended then
			session.speed = if session.speed == 1 then 2 else 1
			view.speed.Text = if session.speed == 2 then "Speed: 2×" else "Speed: 1×"
		end
	end))
	listen(view.skip.Activated:Connect(function()
		if session.cinematicFocus then
			stopCinematic(session)
		end
	end))
	listen(view.cinematic.Activated:Connect(function()
		if not session.ended then
			PLAYER:SetAttribute(CINEMATIC_SETTING, not cinematicEnabled())
			updateCinematicLabel()
			if not cinematicEnabled() then
				stopCinematic(session)
			end
		end
	end))
	listen(view.exit.Activated:Connect(function()
		close(session)
	end))
	listen(view.close.Activated:Connect(function()
		close(session)
	end))
	listen(PLAYER.CharacterRemoving:Connect(function()
		close(session)
	end))
	listen(UserInputService.InputBegan:Connect(function(input, processed)
		if not processed and input.KeyCode == Enum.KeyCode.ButtonB then
			close(session)
		end
	end))

	tick(session, 0)
	if active == session then
		session.frame = RunService.PreRender:Connect(function(delta)
			tick(session, delta)
		end)
	end
end

function BattleViewController.start(): ()
	task.spawn(function()
		local folder = ReplicatedStorage:WaitForChild(Remotes.FOLDER_NAME, 10)
		local event = folder and folder:WaitForChild("BattleResult", 10)
		if not event or not event:IsA("RemoteEvent") then
			warn("[BattleReplay] BattleResult remote is unavailable.")
			return
		end
		-- One listener persists for this LocalScript. All per-replay resources are closed separately.
		event.OnClientEvent:Connect(begin)
	end)
end

return table.freeze(BattleViewController)
