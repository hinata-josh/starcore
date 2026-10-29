--!strict
-- M0 風險驗證:球面重力(方案 A)。驗收看 docs/studio-checklist.md。
-- 作法:Humanoid 進 PlatformStand 不再自己站直 → 每幀自己做「重力朝球心 + 身體 Y 軸對齊法線 + 沿切平面移動」。
-- 操作(仿 Roblox 預設):WASD 依「相機方向」移動;按住右鍵拖曳 / Q E / ←→ 轉視角;滾輪縮放;空白鍵跳。
-- 相機有自己的朝向(camFwd),不會自動甩到角色背後 → 按 A/D 是側移+轉身,不會繞圈。
-- 若手感不佳或相機暈,改走方案 B(圓盤島),格位是邏輯座標,玩法不受影響。

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")

local SHOW_LOG = true
local function log(...)
	if SHOW_LOG then
		print("[SphereGravity]", ...)
	end
end

local player = Players.LocalPlayer
local GRAVITY = 90 -- studs/s²
local WALK_SPEED = 20
local JUMP_SPEED = 45
local ACCEL_GROUND = 12 -- 速度追上目標的快慢(越大越「緊」)
local ACCEL_AIR = 3
local TURN_RATE = 12 -- 身體轉向的快慢
local KEY_YAW_SPEED = 2.4 -- Q/E、←→ 每秒轉幾弧度
local MOUSE_YAW = 0.006 -- 右鍵拖曳每像素轉幾弧度
local MOUSE_PITCH = 0.004
local PITCH_MIN, PITCH_MAX = math.rad(5), math.rad(70)
local DIST_MIN, DIST_MAX = 10, 50

-- 相機狀態放在外層:重生後保留玩家習慣的距離/俯角
local camPitch = math.rad(25)
local camDist = 22
local rmbDown = false

-- 把向量 v 投影到法線為 up 的切平面;太小就用 fallback
local function flatten(v: Vector3, up: Vector3, fallback: Vector3): Vector3
	local f = v - up * v:Dot(up)
	return if f.Magnitude > 1e-3 then f.Unit else fallback
end

-- 繞 axis 旋轉 v(axis 需為單位向量)
local function rotateAround(v: Vector3, axis: Vector3, angle: number): Vector3
	return CFrame.fromAxisAngle(axis, angle):VectorToWorldSpace(v)
end

local yawInput = 0 -- 本幀累積的滑鼠水平轉角(弧度)

UserInputService.InputBegan:Connect(function(input)
	if input.UserInputType == Enum.UserInputType.MouseButton2 then
		rmbDown = true
		UserInputService.MouseBehavior = Enum.MouseBehavior.LockCurrentPosition
	end
end)
UserInputService.InputEnded:Connect(function(input)
	if input.UserInputType == Enum.UserInputType.MouseButton2 then
		rmbDown = false
		UserInputService.MouseBehavior = Enum.MouseBehavior.Default
	end
end)
UserInputService.InputChanged:Connect(function(input, processed)
	if input.UserInputType == Enum.UserInputType.MouseMovement and rmbDown then
		yawInput -= input.Delta.X * MOUSE_YAW
		camPitch = math.clamp(camPitch + input.Delta.Y * MOUSE_PITCH, PITCH_MIN, PITCH_MAX)
	elseif input.UserInputType == Enum.UserInputType.MouseWheel and not processed then
		camDist = math.clamp(camDist - input.Position.Z * 3, DIST_MIN, DIST_MAX)
	end
end)

-- Roblox 預設動畫(角色身上的 Animate 腳本讀不到時用)
local DEFAULT_ANIM = {
	R15 = { idle = "rbxassetid://507766666", walk = "rbxassetid://913402848", run = "rbxassetid://913376220", jump = "rbxassetid://507765000", fall = "rbxassetid://507767968" },
	R6 = { idle = "rbxassetid://180435571", walk = "rbxassetid://180426354", run = "rbxassetid://180426354", jump = "rbxassetid://125750702", fall = "rbxassetid://180436148" },
}
-- Animate 腳本裡各動作的 (資料夾, Animation 名稱)
local ANIM_PATH = { idle = { "idle", "Animation1" }, walk = { "walk", "WalkAnim" }, run = { "run", "RunAnim" }, jump = { "jump", "JumpAnim" }, fall = { "fall", "FallAnim" } }

-- 走路動畫:PlatformStand 會讓 Roblox 內建 Animate 不播走路,所以關掉它、自己依速度播
-- 回傳 update(水平速度, 是否著地, 垂直速度);載入失敗時回傳空函式(不影響移動)
local function setupAnimations(character: Model, humanoid: Humanoid): (number, boolean, number) -> ()
	local ok, update = pcall(function()
		local animator = humanoid:FindFirstChildOfClass("Animator")
		if not animator then
			animator = Instance.new("Animator")
			animator.Parent = humanoid
		end
		local rig = if humanoid.RigType == Enum.HumanoidRigType.R15 then "R15" else "R6"
		local animate = character:FindFirstChild("Animate")
		local tracks: { [string]: AnimationTrack } = {}
		for name, path in ANIM_PATH do
			local id = DEFAULT_ANIM[rig][name]
			local folder = animate and animate:FindFirstChild(path[1])
			local src = folder and folder:FindFirstChild(path[2])
			if src and src:IsA("Animation") and src.AnimationId ~= "" then
				id = src.AnimationId
			end
			local a = Instance.new("Animation")
			a.AnimationId = id
			local tr = (animator :: Animator):LoadAnimation(a)
			tr.Priority = if name == "idle" then Enum.AnimationPriority.Idle else Enum.AnimationPriority.Movement
			tr.Looped = name ~= "jump"
			tracks[name] = tr
		end
		if animate and animate:IsA("LocalScript") then
			animate.Enabled = false
		end
		for _, tr in (animator :: Animator):GetPlayingAnimationTracks() do
			tr:Stop(0)
		end
		log("走路動畫就緒:", rig, if animate then "(取自 Animate)" else "(用預設)")
		local current: string? = nil
		local function play(name: string, speed: number)
			if current ~= name then
				if current then
					tracks[current]:Stop(0.15)
				end
				tracks[name]:Play(0.15)
				current = name
				character:SetAttribute("MoveAnim", name) -- 除錯用:Studio 屬性面板看得到目前動作
			end
			tracks[name]:AdjustSpeed(speed)
		end
		return function(hSpeed: number, grounded: boolean, vUp: number)
			if not grounded then
				play(if vUp > 0 then "jump" else "fall", 1)
			elseif hSpeed > 13 then
				play("run", hSpeed / 16)
			elseif hSpeed > 1 then
				play("walk", hSpeed / 10)
			else
				play("idle", 1)
			end
		end
	end)
	if not ok then
		log("走路動畫載入失敗(不影響移動):", update)
		return function() end
	end
	return update :: any
end

local function setup(character: Model)
	local humanoid = character:WaitForChild("Humanoid") :: Humanoid
	local root = character:WaitForChild("HumanoidRootPart") :: BasePart
	humanoid.PlatformStand = true
	humanoid.AutoRotate = false
	-- 位置完全由本腳本控制:關掉本機世界重力(否則每個物理步都被往 -Y 拉,會抖/飄)
	workspace.Gravity = 0
	-- 根部到腳底的距離(依實際角色算,避免腳插進地面被物理推出去)
	local FOOT = humanoid.HipHeight + root.Size.Y / 2
	if humanoid.RigType == Enum.HumanoidRigType.R6 then
		FOOT = root.Size.Y / 2 + 2 -- R6 的 HipHeight 是 0,腿長 2
	end
	log(("啟用:腳底距離 %.2f,RigType %s"):format(FOOT, humanoid.RigType.Name))
	local animate = setupAnimations(character, humanoid)

	local vUp = 0
	local hVel = Vector3.zero -- 切平面內的水平速度(平滑加減速)
	local grounded = false
	local look = Vector3.zAxis -- 身體面向(切平面內)
	local camFwd: Vector3? = nil -- 相機水平朝向(切平面內);第一幀用身體面向初始化
	local focus: Vector3? = nil -- 相機注視點(平滑跟隨,避免跳動)

	-- 伺服器要傳送玩家(穿梭/返航)時,設 TeleportTo + TeleportSeq;由 client 自己搬,避免和 client 端位置控制打架
	local tpConn = player:GetAttributeChangedSignal("TeleportSeq"):Connect(function()
		local to = player:GetAttribute("TeleportTo") :: Vector3?
		local c = player:GetAttribute("GravCenter") :: Vector3?
		if to and c then
			vUp, hVel, grounded = 0, Vector3.zero, false
			local up = (to - c).Unit
			-- 伺服器可指定傳送後面向哪裡(觀戰:面向怪獸降落區)
			local want = player:GetAttribute("TeleportLook") :: Vector3?
			look = flatten(want or Vector3.zAxis, up, up:Cross(Vector3.xAxis).Unit)
			camFwd, focus = look, nil
			camPitch = math.rad(if want then 30 else 25)
			root.CFrame = CFrame.lookAt(to, to + look, up)
			log("傳送到", to)
		end
	end)

	local conn
	conn = RunService.RenderStepped:Connect(function(dt)
		if not character.Parent then
			conn:Disconnect()
			tpConn:Disconnect()
			return
		end
		-- 重力中心由伺服器依「人在哪顆星球」設在玩家屬性上(穿梭會切換)
		local center = player:GetAttribute("GravCenter") :: Vector3?
		local radius = player:GetAttribute("GravRadius") :: number?
		if not center or not radius then
			return
		end
		local pos = root.Position
		local up = (pos - center).Unit
		local height = (pos - center).Magnitude - radius - FOOT

		-- 朝向向量隨球面「平行移動」:每幀重新投影到當下的切平面,過極點也不會翻轉
		look = flatten(look, up, flatten(Vector3.zAxis, up, up:Cross(Vector3.xAxis).Unit))
		local fwd = flatten(camFwd or look, up, look)

		-- 轉視角:右鍵拖曳 + Q/E/←→(打字時不吃鍵盤)
		local typing = UserInputService:GetFocusedTextBox() ~= nil
		local keyYaw = 0
		if not typing then
			if UserInputService:IsKeyDown(Enum.KeyCode.Q) or UserInputService:IsKeyDown(Enum.KeyCode.Left) then
				keyYaw += KEY_YAW_SPEED * dt
			end
			if UserInputService:IsKeyDown(Enum.KeyCode.E) or UserInputService:IsKeyDown(Enum.KeyCode.Right) then
				keyYaw -= KEY_YAW_SPEED * dt
			end
		end
		local yaw = yawInput + keyYaw
		yawInput = 0
		if yaw ~= 0 then
			fwd = rotateAround(fwd, up, yaw)
		end
		camFwd = fwd
		local right = fwd:Cross(up).Unit

		-- 移動輸入:相對相機方向
		local move = Vector3.zero
		if not typing then
			if UserInputService:IsKeyDown(Enum.KeyCode.W) or UserInputService:IsKeyDown(Enum.KeyCode.Up) then move += fwd end
			if UserInputService:IsKeyDown(Enum.KeyCode.S) or UserInputService:IsKeyDown(Enum.KeyCode.Down) then move -= fwd end
			if UserInputService:IsKeyDown(Enum.KeyCode.D) then move += right end
			if UserInputService:IsKeyDown(Enum.KeyCode.A) then move -= right end
		end
		if move.Magnitude > 0 then
			move = move.Unit
		end

		-- 水平速度平滑追目標(地面緊、空中鬆);身體平滑轉向行進方向
		hVel = flatten(hVel, up, Vector3.zero) * hVel.Magnitude
		local accel = if grounded then ACCEL_GROUND else ACCEL_AIR
		hVel = hVel:Lerp(move * WALK_SPEED, 1 - math.exp(-accel * dt))
		if move.Magnitude > 0 then
			local target = look:Lerp(move, 1 - math.exp(-TURN_RATE * dt))
			-- look 與 move 幾乎反向時 Lerp 會接近零向量 → 先往右偏一點再轉
			look = if target.Magnitude > 0.05 then target.Unit else (look + right * 0.2).Unit
		end

		-- 垂直:重力 / 跳躍
		if grounded and not typing and UserInputService:IsKeyDown(Enum.KeyCode.Space) then
			vUp = JUMP_SPEED
			grounded = false
		end
		vUp -= GRAVITY * dt
		local newHeight = height + vUp * dt
		if newHeight <= 0 then
			newHeight = 0
			vUp = math.max(vUp, 0)
			grounded = true
		else
			grounded = false
		end

		-- 水平位移後重新貼回球面高度
		local dir = (pos + hVel * dt - center).Unit
		local newPos = center + dir * (radius + FOOT + newHeight)

		-- 身體:Y 對齊法線、面向 look
		local lookFlat = flatten(look, dir, fwd)
		root.AssemblyLinearVelocity = Vector3.zero
		root.AssemblyAngularVelocity = Vector3.zero
		root.CFrame = CFrame.lookAt(newPos, newPos + lookFlat, dir)
		animate(hVel.Magnitude, grounded, vUp)

		-- 相機:由 camFwd/俯角/距離決定,注視點平滑跟隨(不再 Lerp 整個 CFrame,轉向不會拖泥帶水)
		local camF = flatten(fwd, dir, lookFlat)
		local targetFocus = newPos + dir * 2
		focus = if focus then (focus :: Vector3):Lerp(targetFocus, 1 - math.exp(-20 * dt)) else targetFocus
		local f = focus :: Vector3
		local camPos = f - camF * math.cos(camPitch) * camDist + dir * math.sin(camPitch) * camDist
		local cam = workspace.CurrentCamera
		cam.CameraType = Enum.CameraType.Scriptable
		cam.CFrame = CFrame.lookAt(camPos, f, dir)
	end)
end

if player.Character then
	task.spawn(setup, player.Character)
end
player.CharacterAdded:Connect(setup)
