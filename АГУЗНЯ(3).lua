--// Jailbreak Bounty Tracker
--// LocalScript
--// Помести в StarterPlayerScripts или StarterGui

local Players = game:GetService("Players")
local UserInputService = game:GetService("UserInputService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")
local RunService = game:GetService("RunService")
-- НОВОЕ: нужен, чтобы получить список тим сервера для выпадающего меню
local Teams = game:GetService("Teams")
-- НОВОЕ: анимации появления, сворачивания и подсветки кнопок
local TweenService = game:GetService("TweenService")
-- НОВОЕ: отсюда читается пинг до сервера
local Stats = game:GetService("Stats")
-- НОВОЕ: задержка запуска. Скрипт ничего не делает первые секунды —
-- после захода на сервер карта, игроки и модули подгружаются не сразу,
-- и слишком ранний старт ловил бы пустоту. Само ожидание теперь идёт
-- на экране загрузки ниже, чтобы эти секунды не выглядели зависанием
local START_DELAY = 5

local LocalPlayer = Players.LocalPlayer
local PlayerGui = LocalPlayer:WaitForChild("PlayerGui")

--==================================================
-- НАСТРОЙКИ
--==================================================
local UPDATE_INTERVAL = 1
local MAX_DISTANCE = 10000

-- Минимальная награда в игре. Значение ниже считается «нашли не тот объект»,
-- и поиск продолжается дальше. Из-за этого награда больше не залипает на 0.
local MIN_BOUNTY = 400

-- Включи, чтобы в Output увидеть, какое именно значение нашёл скрипт
-- для каждого игрока (или что не нашёл вообще)
local DEBUG_STATS = false

-- НОВОЕ: включи, чтобы при запуске выгрузить в Output содержимое модулей игры
-- (CriminalUtil, JobsUtil, JobsConstants, CriminalConstants) и то, что
-- скрипт из них вычитал по каждому игроку. Нужно, если число не сходится
-- с тем, что показывает сама игра
local DEBUG_MODULES = false

--==================================================
-- РЕЖИМЫ (НОВОЕ)
--==================================================
-- Панель работает под две игры, режим спрашивается при запуске:
--   Drive Empire — всё как было: таймер розыска, выплата за арест
--                  из констант игры (ArrestReward/CaptureReward), кнопка ШЕР
--   Jail break   — без таймера (его в игре нет), без констант криминала
--                  и без кнопки ШЕР
local MODE_DRIVE_EMPIRE = "drive"
local MODE_JAILBREAK = "jail"

local MODE_FEATURES = {
	[MODE_DRIVE_EMPIRE] = {
		label = "Drive Empire",
		-- таймер розыска в карточке
		wantedTimer = true,
		-- поиск выплаты за арест в CriminalConstants
		captureConfig = true,
		-- нижняя кнопка запроса работы Security
		securityButton = true,
	},
	[MODE_JAILBREAK] = {
		label = "Jail break",
		wantedTimer = false,
		captureConfig = false,
		securityButton = false,
	},
}

-- Скрипт сам ищет нужные значения в данных игрока по этим кускам имён
-- (сравнение по подстроке).
-- ВНИМАНИЕ: string.lower в Luau приводит к нижнему регистру только латиницу,
-- поэтому кириллица перечислена и с заглавной, и со строчной буквы.
local BOUNTY_PATTERNS = {
	"bounty",
	"wanted",
	"награда",
	"Награда",
	"розыск",
	"Розыск",
}

local ROBBERY_PATTERNS = {
	"robbery",
	"robberies",
	"robbed",
	"heist",
	"ограбл",
	"Ограбл",
	"налёт",
	"Налёт",
	"налет",
	"Налет",
	"кражи",
	"Кражи",
}

local CAPTURE_PATTERNS = {
	"capturereward",
	"captureprice",
	"arrestreward",
	"поимк",
	"Поимк",
}

-- Если цену за поимку в данных не нашли — считаем как процент от награды.
-- Поставь 0, чтобы вместо расчётного числа был прочерк.
local CAPTURE_PERCENT = 0.5

-- НОВОЕ: цена за поимку от этой суммы — ник в таблице получает жёлтый фон,
-- такой же, как у строки дропа: жирную цель видно сразу
local BIG_CAPTURE_VALUE = 1000000

-- НОВОЕ: столько секунд до конца розыска таймер горит красным
local WANTED_SOON = 15

-- НОВОЕ: автозапуск после телепорта. Впиши сюда прямую ссылку на этот же
-- скрипт (raw), и после смены сервера исполнитель запустит его сам.
-- Пустая строка = автозапуск выключен. Своего исходника у запущенного кода
-- нет, поэтому в очередь уходит именно загрузчик по ссылке
local AUTORUN_URL = ""

-- Имена, которые никогда не считаются нужным значением
-- (Robux ловится по "rob", деньги — не награда за розыск)
local NAME_EXCLUDE = {
	"robux",
	"cash",
	"money",
}

-- Насколько глубоко залезать в папки с данными
local SEARCH_DEPTH = 4

-- Контейнеры игрока, куда лезть бессмысленно и дорого
local SKIP_NAMES = {
	PlayerGui = true,
	Backpack = true,
	StarterGear = true,
	PlayerScripts = true,
}

--==================================================
-- НАСТРОЙКИ ВЫБОРА ТИМЫ
--==================================================
-- Режимы фильтра:
--   "auto" — как раньше: тима похожа на криминальную ИЛИ есть награда
--   "all"  — все игроки сервера, кроме себя
--   "team" — только выбранная тима (её имя лежит в teamFilter.teamName)
-- Здесь задаётся только стартовое значение, дальше меняется кнопкой в панели
local teamFilter = {
	mode = "auto",
	teamName = nil,
}

-- По этим подстрокам режим "auto" узнаёт тиму преступников
local CRIMINAL_TEAM_PATTERNS = {
	"criminal",
	"crim",
	"преступ",
	"Преступ",
}

local AUTO_LABEL = "Авто: преступники"
local ALL_LABEL = "Все игроки"

--==================================================
-- НАСТРОЙКИ A-LOOP TOP-1
--==================================================
local AUTO_LOOP_ENABLED = true
local AUTO_LOOP_MIN_CAPTURE = 100000
local AUTO_LOOP_INTERVAL = 0.20
local AUTO_LOOP_BUTTON_TEXT = "A-LOOP"
local AUTO_LOOP_ACTIVE_TEXT = "UNLOOP"

-- Размеры выпадающего списка тим
local DROPDOWN_ROW_HEIGHT = 20
local DROPDOWN_ROW_GAP = 1
local DROPDOWN_MAX_HEIGHT = 110

--==================================================
-- НАСТРОЙКИ DROP
--==================================================
-- По этим кускам имён дроп ищется в Workspace.
-- Исключения NAME_EXCLUDE здесь НЕ применяются, иначе «MoneyBag» отсеялся бы.
local DROP_PATTERNS = {
	"drop",
	"Drop",
	"дроп",
	"Дроп",
	"loot",
	"Loot",
	"лут",
	"Лут",
}

-- Глубина поиска в Workspace. Больше 3 ставить не стоит: карта большая
local DROP_SEARCH_DEPTH = 3

-- Имена, которые дропом НЕ считаются, хотя и содержат «drop».
-- Это точки сдачи мешков, а не сам лут. Совпадение по подстроке,
-- поэтому "dropoff" ловит и SackDropOffs, и DropOff, и любой DropOffPart.
-- Такой контейнер ещё и не просматривается внутри: то, что лежит
-- в зоне сдачи, дропом тоже не является
local DROP_EXCLUDE = {
	"sackdropoff",
	"dropoff",
	"Mountain",
	"oil",
	"cargo",
	"rain",
}

-- Ярко-жёлтый для подсветки и линии
local DROP_COLOR = Color3.fromRGB(255, 255, 0)
-- Фон строки дропа в таблице и цвет текста на нём
local DROP_ROW_COLOR = Color3.fromRGB(255, 215, 0)
local DROP_TEXT_COLOR = Color3.fromRGB(25, 25, 25)

local espEnabled = true
local linesEnabled = true

--==================================================
-- НАСТРОЙКИ ЛИНИИ
--==================================================
-- Цвет линии для игрока без тимы: с тимой линия берёт её цвет
local LINE_COLOR = Color3.fromRGB(255, 0, 0)
local LINE_WIDTH = 0.12

-- Линия выбранного игрока (клик по нику в таблице)
local SELECT_COLOR = Color3.fromRGB(0, 255, 0)
local SELECT_WIDTH = 0.35

--==================================================
-- ТЕМА (НОВОЕ)
--==================================================
-- Красно-чёрная палитра. Вся панель берёт цвета отсюда — поменяв
-- значения здесь, меняешь оформление целиком
local COLOR_BG = Color3.fromRGB(13, 11, 12)
local COLOR_HEADER = Color3.fromRGB(24, 16, 18)
local COLOR_FIELD = Color3.fromRGB(32, 23, 25)
local COLOR_ROW = Color3.fromRGB(26, 19, 21)
local COLOR_EDGE = Color3.fromRGB(125, 26, 34)
local COLOR_ACCENT = Color3.fromRGB(220, 45, 55)
local COLOR_TEXT = Color3.fromRGB(240, 232, 233)
local COLOR_TEXT_DIM = Color3.fromRGB(145, 132, 134)
local COLOR_MONEY = Color3.fromRGB(235, 180, 90)

-- Переключатели остаются красно-зелёными: состояние видно с одного взгляда
local COLOR_ON = Color3.fromRGB(40, 165, 65)
local COLOR_OFF = Color3.fromRGB(180, 35, 40)

-- Цвет игрока, у которого тимы нет вовсе
local NO_TEAM_COLOR = LINE_COLOR
-- Ниже этой яркости цвет тимы на чёрном фоне не читается и осветляется
local MIN_TEAM_LUMA = 0.45

-- НОВОЕ: тёмные тимы (чёрная, тёмно-синяя) на чёрном фоне сливаются с ним,
-- поэтому слишком тёмный оттенок подтягивается по яркости, сохраняя тон
local function readableColor(color)
	local luma = 0.299 * color.R + 0.587 * color.G + 0.114 * color.B
	if luma >= MIN_TEAM_LUMA then
		return color
	end
	if luma <= 0.08 then
		-- почти чёрная тима: оттенка нет вообще, отдаём светло-серый
		return Color3.fromRGB(200, 200, 200)
	end

	-- Осветляем подмешиванием белого, а не умножением: чистый синий
	-- умножением не поднять (канал упирается в 1), а примесь белого
	-- поднимает яркость всегда и оттенок при этом узнаётся
	local mix = (MIN_TEAM_LUMA - luma) / (1 - luma)
	return Color3.new(
		color.R + (1 - color.R) * mix,
		color.G + (1 - color.G) * mix,
		color.B + (1 - color.B) * mix
	)
end

-- НОВОЕ: цвет игрока — цвет его тимы. Через pcall: у игрока, вылетевшего
-- прямо во время обхода, обращение к Team бросает ошибку
local function getPlayerColor(player)
	local ok, team = pcall(function()
		return player.Team
	end)
	if ok and team then
		local gotColor, brick = pcall(function()
			return player.TeamColor.Color
		end)
		if gotColor and brick then
			return readableColor(brick)
		end
	end
	return NO_TEAM_COLOR
end

-- UserId выбранного игрока. nil — не выбран никто.
-- Объявлено здесь намеренно: createLine ниже читает эту переменную,
-- а в Lua обращение к локали, объявленной позже, молча вернёт nil
local selectedUserId = nil

-- НОВОЕ: предварительное объявление. Обработчики выпадающего списка тим
-- создаются выше по файлу, чем сама updateList, а замыкание в Lua не увидит
-- локаль, объявленную после него. Ниже updateList определяется уже без local
local updateList
local matchesFilter
local getCaptureValue
local getBountyValue

local GUI_NAME = "JailbreakBountyTracker"

-- ФИКС: префикс якоря вынесен в константу, чтобы не хардкодить sub(1, 13)
local ANCHOR_PREFIX = "BountyAnchor_"

--==================================================
-- ЭКРАН ЗАГРУЗКИ (НОВОЕ)
--==================================================
-- Раньше скрипт просто молчал START_DELAY секунд, и было не понять,
-- запустился он вообще или нет. Теперь эти секунды идут с прогрессом
local LOAD_GUI_NAME = GUI_NAME .. "_Loading"

-- Подписи меняются по ходу полосы. Это честный порядок того, чего мы ждём:
-- сначала карта, потом игроки, потом модули игры становятся доступны
local LOAD_STEPS = {
	"Ждём карту",
	"Собираем игроков",
	"Читаем модули игры",
	"Почти готово",
}

local function playLoadingScreen()
	local oldLoad = PlayerGui:FindFirstChild(LOAD_GUI_NAME)
	if oldLoad then
		oldLoad:Destroy()
	end

	local LoadGui = Instance.new("ScreenGui")
	LoadGui.Name = LOAD_GUI_NAME
	LoadGui.ResetOnSpawn = false
	LoadGui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
	LoadGui.Parent = PlayerGui

	local frame = Instance.new("Frame")
	frame.Name = "LoadFrame"
	frame.Size = UDim2.new(0, 300, 0, 96)
	frame.AnchorPoint = Vector2.new(0.5, 0.5)
	-- стартовая позиция ниже конечной: окно всплывает снизу вверх
	frame.Position = UDim2.new(0.5, 0, 0.42, 20)
	frame.BackgroundColor3 = COLOR_BG
	frame.BackgroundTransparency = 1
	frame.BorderSizePixel = 0
	frame.Parent = LoadGui

	local frameCorner = Instance.new("UICorner")
	frameCorner.CornerRadius = UDim.new(0, 8)
	frameCorner.Parent = frame

	local frameStroke = Instance.new("UIStroke")
	frameStroke.Color = COLOR_EDGE
	frameStroke.Thickness = 1
	frameStroke.Transparency = 1
	frameStroke.Parent = frame

	-- вращающийся квадратик слева от заголовка вместо статичной иконки
	local spinner = Instance.new("Frame")
	spinner.Name = "Spinner"
	spinner.Size = UDim2.new(0, 12, 0, 12)
	spinner.AnchorPoint = Vector2.new(0.5, 0.5)
	spinner.Position = UDim2.new(0, 22, 0, 24)
	spinner.BackgroundColor3 = COLOR_ACCENT
	spinner.BackgroundTransparency = 1
	spinner.BorderSizePixel = 0
	spinner.Parent = frame

	local spinnerCorner = Instance.new("UICorner")
	spinnerCorner.CornerRadius = UDim.new(0, 2)
	spinnerCorner.Parent = spinner

	local title = Instance.new("TextLabel")
	title.Name = "LoadTitle"
	title.Size = UDim2.new(1, -50, 0, 22)
	title.Position = UDim2.new(0, 38, 0, 13)
	title.BackgroundTransparency = 1
	title.Text = "ТРЕКЕР ИГРОКОВ"
	title.TextColor3 = COLOR_TEXT
	title.TextTransparency = 1
	title.TextXAlignment = Enum.TextXAlignment.Left
	title.Font = Enum.Font.SourceSansBold
	title.TextSize = 17
	title.Parent = frame

	local step = Instance.new("TextLabel")
	step.Name = "LoadStep"
	step.Size = UDim2.new(1, -100, 0, 18)
	step.Position = UDim2.new(0, 14, 0, 38)
	step.BackgroundTransparency = 1
	step.Text = LOAD_STEPS[1]
	step.TextColor3 = COLOR_TEXT_DIM
	step.TextTransparency = 1
	step.TextXAlignment = Enum.TextXAlignment.Left
	step.Font = Enum.Font.SourceSans
	step.TextSize = 14
	step.TextTruncate = Enum.TextTruncate.AtEnd
	step.Parent = frame

	local percent = Instance.new("TextLabel")
	percent.Name = "LoadPercent"
	percent.Size = UDim2.new(0, 60, 0, 18)
	percent.Position = UDim2.new(1, -74, 0, 38)
	percent.BackgroundTransparency = 1
	percent.Text = "0%"
	percent.TextColor3 = COLOR_ACCENT
	percent.TextTransparency = 1
	percent.TextXAlignment = Enum.TextXAlignment.Right
	percent.Font = Enum.Font.SourceSansBold
	percent.TextSize = 14
	percent.Parent = frame

	-- дорожка полосы и сама полоса
	local track = Instance.new("Frame")
	track.Name = "Track"
	track.Size = UDim2.new(1, -28, 0, 6)
	track.Position = UDim2.new(0, 14, 0, 64)
	track.BackgroundColor3 = COLOR_FIELD
	track.BackgroundTransparency = 1
	track.BorderSizePixel = 0
	track.Parent = frame

	local trackCorner = Instance.new("UICorner")
	trackCorner.CornerRadius = UDim.new(1, 0)
	trackCorner.Parent = track

	local fill = Instance.new("Frame")
	fill.Name = "Fill"
	fill.Size = UDim2.new(0, 0, 1, 0)
	fill.BackgroundColor3 = COLOR_ACCENT
	fill.BackgroundTransparency = 1
	fill.BorderSizePixel = 0
	fill.Parent = track

	local fillCorner = Instance.new("UICorner")
	fillCorner.CornerRadius = UDim.new(1, 0)
	fillCorner.Parent = fill

	-- появление: окно всплывает и проявляется
	local appear = TweenInfo.new(
		0.35,
		Enum.EasingStyle.Quad,
		Enum.EasingDirection.Out
	)
	TweenService:Create(frame, appear, {
		Position = UDim2.new(0.5, 0, 0.42, 0),
		BackgroundTransparency = 0.05,
	}):Play()
	TweenService:Create(frameStroke, appear, { Transparency = 0 }):Play()
	TweenService:Create(title, appear, { TextTransparency = 0 }):Play()
	TweenService:Create(step, appear, { TextTransparency = 0.1 }):Play()
	TweenService:Create(percent, appear, { TextTransparency = 0 }):Play()
	TweenService:Create(track, appear, { BackgroundTransparency = 0 }):Play()
	TweenService:Create(spinner, appear, { BackgroundTransparency = 0 }):Play()
	TweenService:Create(fill, appear, { BackgroundTransparency = 0 }):Play()

	-- прогресс считается от реального времени, а не от числа кадров:
	-- при просадке FPS полоса всё равно дойдёт до конца ровно за START_DELAY
	local started = os.clock()
	local dots = 0

	while true do
		local passed = os.clock() - started
		local ratio = math.clamp(passed / START_DELAY, 0, 1)

		fill.Size = UDim2.new(ratio, 0, 1, 0)
		percent.Text = tostring(math.floor(ratio * 100)) .. "%"

		local stepIndex = math.min(
			#LOAD_STEPS,
			math.floor(ratio * #LOAD_STEPS) + 1
		)
		dots = (dots + 1) % 4
		step.Text = LOAD_STEPS[stepIndex] .. string.rep(".", dots)

		spinner.Rotation = spinner.Rotation + 9

		if ratio >= 1 then
			break
		end
		task.wait(0.06)
	end

	-- исчезновение: то же движение в обратную сторону
	local vanish = TweenInfo.new(
		0.25,
		Enum.EasingStyle.Quad,
		Enum.EasingDirection.In
	)
	TweenService:Create(frame, vanish, {
		Position = UDim2.new(0.5, 0, 0.42, -14),
		BackgroundTransparency = 1,
	}):Play()
	TweenService:Create(frameStroke, vanish, { Transparency = 1 }):Play()
	TweenService:Create(title, vanish, { TextTransparency = 1 }):Play()
	TweenService:Create(step, vanish, { TextTransparency = 1 }):Play()
	TweenService:Create(percent, vanish, { TextTransparency = 1 }):Play()
	TweenService:Create(track, vanish, { BackgroundTransparency = 1 }):Play()
	TweenService:Create(fill, vanish, { BackgroundTransparency = 1 }):Play()
	TweenService:Create(spinner, vanish, { BackgroundTransparency = 1 }):Play()

	-- ждём конец анимации, иначе окно исчезло бы рывком
	task.wait(0.3)
	LoadGui:Destroy()
end

playLoadingScreen()

--==================================================
-- ПОДСВЕТКА КНОПОК (НОВОЕ)
--==================================================
-- Кнопка светлеет под курсором и возвращается к своему цвету. Базовый цвет
-- запоминается один раз при подключении: считать его в момент наведения
-- нельзя — можно поймать середину незакончившейся анимации.
-- Переключателям ESP/LINE подсветку не вешаем: у них цвет несёт состояние
local HOVER_TWEEN = TweenInfo.new(0.12, Enum.EasingStyle.Quad)
-- переключение вкл/выкл заметнее наведения, поэтому идёт медленнее
local TOGGLE_TWEEN = TweenInfo.new(0.2, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)

local function addHover(button, lighten)
	local function lighter(color)
		return Color3.new(
			math.min(1, color.R + lighten),
			math.min(1, color.G + lighten),
			math.min(1, color.B + lighten)
		)
	end

	local base = button.BackgroundColor3
	local hover = lighter(base)
	local inside = false

	-- встроенная подсветка Roblox мешала бы анимации
	button.AutoButtonColor = false

	button.MouseEnter:Connect(function()
		inside = true
		TweenService:Create(button, HOVER_TWEEN, {
			BackgroundColor3 = hover,
		}):Play()
	end)

	button.MouseLeave:Connect(function()
		inside = false
		TweenService:Create(button, HOVER_TWEEN, {
			BackgroundColor3 = base,
		}):Play()
	end)

	-- НОВОЕ: возвращаем функцию смены базового цвета. Кнопки ESP и LINE
	-- красятся по состоянию вкл/выкл, и без этого подсветка считалась бы
	-- от цвета, который был при запуске: выключенная кнопка после
	-- наведения снова становилась бы зелёной
	return function(newBase)
		base = newBase
		hover = lighter(newBase)
		TweenService:Create(button, TOGGLE_TWEEN, {
			BackgroundColor3 = inside and hover or base,
		}):Play()
	end
end

--==================================================
-- ВЫБОР РЕЖИМА ПРИ ЗАПУСКЕ (НОВОЕ)
--==================================================
-- Окно с двумя кнопками. Пока режим не выбран, скрипт дальше не идёт:
-- от режима зависит и набор данных, и сама панель
local MODE_GUI_NAME = GUI_NAME .. "_ModePick"

local oldModeGui = PlayerGui:FindFirstChild(MODE_GUI_NAME)
if oldModeGui then
	oldModeGui:Destroy()
end

local ModeGui = Instance.new("ScreenGui")
ModeGui.Name = MODE_GUI_NAME
ModeGui.ResetOnSpawn = false
ModeGui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
ModeGui.Parent = PlayerGui

local ModeFrame = Instance.new("Frame")
ModeFrame.Name = "ModeFrame"
ModeFrame.Size = UDim2.new(0, 260, 0, 122)
-- НОВОЕ: стартует ниже и прозрачным, дальше всплывает на место
ModeFrame.Position = UDim2.new(0.5, -130, 0.4, -43)
ModeFrame.BackgroundColor3 = COLOR_BG
ModeFrame.BackgroundTransparency = 1
ModeFrame.BorderSizePixel = 0
ModeFrame.Parent = ModeGui

local ModeCorner = Instance.new("UICorner")
ModeCorner.CornerRadius = UDim.new(0, 8)
ModeCorner.Parent = ModeFrame

-- НОВОЕ: тонкая красная рамка вместо плоского прямоугольника
local ModeStroke = Instance.new("UIStroke")
ModeStroke.Color = COLOR_EDGE
ModeStroke.Thickness = 1
ModeStroke.Transparency = 1
ModeStroke.Parent = ModeFrame

local ModeTitle = Instance.new("TextLabel")
ModeTitle.Size = UDim2.new(1, -10, 0, 30)
ModeTitle.Position = UDim2.new(0, 5, 0, 4)
ModeTitle.BackgroundTransparency = 1
ModeTitle.Text = "Выбери режим"
ModeTitle.TextColor3 = COLOR_TEXT
ModeTitle.TextTransparency = 1
ModeTitle.Font = Enum.Font.SourceSansBold
ModeTitle.TextSize = 16
ModeTitle.Parent = ModeFrame

local DriveModeButton = Instance.new("TextButton")
DriveModeButton.Name = "DriveModeButton"
DriveModeButton.Size = UDim2.new(1, -20, 0, 32)
DriveModeButton.Position = UDim2.new(0, 10, 0, 38)
DriveModeButton.BackgroundColor3 = Color3.fromRGB(150, 30, 38)
DriveModeButton.BackgroundTransparency = 1
DriveModeButton.Text = MODE_FEATURES[MODE_DRIVE_EMPIRE].label
DriveModeButton.TextColor3 = COLOR_TEXT
DriveModeButton.TextTransparency = 1
DriveModeButton.Font = Enum.Font.SourceSansBold
DriveModeButton.TextSize = 14
DriveModeButton.BorderSizePixel = 0
DriveModeButton.Parent = ModeFrame

local DriveModeCorner = Instance.new("UICorner")
DriveModeCorner.CornerRadius = UDim.new(0, 4)
DriveModeCorner.Parent = DriveModeButton

local JailModeButton = Instance.new("TextButton")
JailModeButton.Name = "JailModeButton"
JailModeButton.Size = UDim2.new(1, -20, 0, 32)
JailModeButton.Position = UDim2.new(0, 10, 0, 76)
JailModeButton.BackgroundColor3 = Color3.fromRGB(60, 24, 28)
JailModeButton.BackgroundTransparency = 1
JailModeButton.Text = MODE_FEATURES[MODE_JAILBREAK].label
JailModeButton.TextColor3 = COLOR_TEXT
JailModeButton.TextTransparency = 1
JailModeButton.Font = Enum.Font.SourceSansBold
JailModeButton.TextSize = 14
JailModeButton.BorderSizePixel = 0
JailModeButton.Parent = ModeFrame

local JailModeCorner = Instance.new("UICorner")
JailModeCorner.CornerRadius = UDim.new(0, 4)
JailModeCorner.Parent = JailModeButton

-- НОВОЕ: подсветка под курсором
addHover(DriveModeButton, 0.09)
addHover(JailModeButton, 0.09)

-- НОВОЕ: появление окна выбора
local MODE_APPEAR = TweenInfo.new(
	0.3,
	Enum.EasingStyle.Quad,
	Enum.EasingDirection.Out
)

TweenService:Create(ModeFrame, MODE_APPEAR, {
	Position = UDim2.new(0.5, -130, 0.4, -61),
	BackgroundTransparency = 0,
}):Play()
TweenService:Create(ModeStroke, MODE_APPEAR, { Transparency = 0 }):Play()
-- ФИКС: раньше рамка проявлялась плавно, а надписи и кнопки возникали
-- сразу, и первый кадр выглядел рваным
TweenService:Create(ModeTitle, MODE_APPEAR, { TextTransparency = 0 }):Play()
TweenService:Create(DriveModeButton, MODE_APPEAR, {
	BackgroundTransparency = 0,
	TextTransparency = 0,
}):Play()
TweenService:Create(JailModeButton, MODE_APPEAR, {
	BackgroundTransparency = 0,
	TextTransparency = 0,
}):Play()

-- Клик пишет выбор, ожидание ниже его подхватывает
local pickedMode = nil

DriveModeButton.MouseButton1Click:Connect(function()
	pickedMode = MODE_DRIVE_EMPIRE
end)

JailModeButton.MouseButton1Click:Connect(function()
	pickedMode = MODE_JAILBREAK
end)

-- Ждём выбора. Панель собирается уже под конкретный режим,
-- поэтому строить её до ответа нельзя
repeat
	task.wait()
until pickedMode ~= nil

-- НОВОЕ: окно уезжает вверх и растворяется, а не пропадает мгновенно
local MODE_VANISH = TweenInfo.new(
	0.22,
	Enum.EasingStyle.Quad,
	Enum.EasingDirection.In
)

TweenService:Create(ModeFrame, MODE_VANISH, {
	Position = UDim2.new(0.5, -130, 0.4, -80),
	BackgroundTransparency = 1,
}):Play()
TweenService:Create(ModeStroke, MODE_VANISH, { Transparency = 1 }):Play()
TweenService:Create(ModeTitle, MODE_VANISH, { TextTransparency = 1 }):Play()
TweenService:Create(DriveModeButton, MODE_VANISH, {
	BackgroundTransparency = 1,
	TextTransparency = 1,
}):Play()
TweenService:Create(JailModeButton, MODE_VANISH, {
	BackgroundTransparency = 1,
	TextTransparency = 1,
}):Play()

task.wait(0.26)
ModeGui:Destroy()

-- Набор возможностей выбранного режима. Дальше по файлу проверяется
-- только он, а не сам режим: так проще будет добавить третий
local features = MODE_FEATURES[pickedMode]
print("[BountyTracker] режим:", features.label)

--==================================================
-- УДАЛЕНИЕ СТАРОЙ GUI
--==================================================
local oldGui = PlayerGui:FindFirstChild(GUI_NAME)
if oldGui then
	oldGui:Destroy()
end

--==================================================
-- GUI
--==================================================
local ScreenGui = Instance.new("ScreenGui")
ScreenGui.Name = GUI_NAME
ScreenGui.ResetOnSpawn = false
ScreenGui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
ScreenGui.Parent = PlayerGui

local MainFrame = Instance.new("Frame")
MainFrame.Name = "MainFrame"
-- НОВОЕ: +30 по высоте под строку выбора тимы, ещё +18 под нижнюю
-- строку с пингом
MainFrame.Size = UDim2.new(0, 260, 0, 318)
-- НОВОЕ: окно ждёт за левым краем экрана и выезжает в секции START.
-- Двигается весь фрейм целиком, поэтому подписи внутри отдельно
-- прятать не нужно
MainFrame.Position = UDim2.new(0.05, -320, 0.3, 0)
MainFrame.Visible = false
MainFrame.BackgroundColor3 = COLOR_BG
MainFrame.BorderSizePixel = 0
MainFrame.Active = true
MainFrame.Parent = ScreenGui

--==================================================
-- JAIL BREAK: AIM + WALK SPEED
--==================================================
-- Отдельное окно в том же стиле, что и основная панель.
-- Окно создаётся только для Jail break.
local AimSpeedFrame = nil

if pickedMode == MODE_JAILBREAK then
	AimSpeedFrame = Instance.new("Frame")
	AimSpeedFrame.Name = "AimSpeedFrame"
	AimSpeedFrame.Size = UDim2.new(0, 240, 0, 292)
	AimSpeedFrame.Position = UDim2.new(0.05, 15, 0.62, 0)
	AimSpeedFrame.BackgroundColor3 = COLOR_BG
	AimSpeedFrame.BorderSizePixel = 0
	AimSpeedFrame.Active = true
	AimSpeedFrame.Parent = ScreenGui

	local AimSpeedStroke = Instance.new("UIStroke")
	AimSpeedStroke.Color = COLOR_EDGE
	AimSpeedStroke.Thickness = 1
	AimSpeedStroke.Parent = AimSpeedFrame

	local AimSpeedCorner = Instance.new("UICorner")
	AimSpeedCorner.CornerRadius = UDim.new(0, 8)
	AimSpeedCorner.Parent = AimSpeedFrame

	local AimSpeedTitle = Instance.new("TextLabel")
	AimSpeedTitle.Size = UDim2.new(1, -10, 0, 30)
	AimSpeedTitle.Position = UDim2.new(0, 5, 0, 0)
	AimSpeedTitle.BackgroundColor3 = COLOR_HEADER
	AimSpeedTitle.Text = " AIM / SPEED"
	AimSpeedTitle.TextColor3 = COLOR_TEXT
	AimSpeedTitle.TextXAlignment = Enum.TextXAlignment.Left
	AimSpeedTitle.Font = Enum.Font.SourceSansBold
	AimSpeedTitle.TextSize = 16
	AimSpeedTitle.BorderSizePixel = 0
	AimSpeedTitle.Parent = AimSpeedFrame

	local AimSpeedTitleCorner = Instance.new("UICorner")
	AimSpeedTitleCorner.CornerRadius = UDim.new(0, 8)
	AimSpeedTitleCorner.Parent = AimSpeedTitle

	local AimSpeedUnderline = Instance.new("Frame")
	AimSpeedUnderline.Size = UDim2.new(1, -10, 0, 1)
	AimSpeedUnderline.Position = UDim2.new(0, 5, 0, 31)
	AimSpeedUnderline.BackgroundColor3 = COLOR_ACCENT
	AimSpeedUnderline.BackgroundTransparency = 0.35
	AimSpeedUnderline.BorderSizePixel = 0
	AimSpeedUnderline.Parent = AimSpeedFrame

	local aimEnabled = true
	local aimHolding = false
	local aimRadius = 120
	local aimStrength = 70
	local aimPart = "Head"
	local teamCheck = true
	local wallCheck = true
	local currentWalkSpeed = 20

	local function makeControlLabel(text, y)
		local label = Instance.new("TextLabel")
		label.Size = UDim2.new(1, -10, 0, 20)
		label.Position = UDim2.new(0, 5, 0, y)
		label.BackgroundTransparency = 1
		label.Text = text
		label.TextColor3 = COLOR_TEXT
		label.Font = Enum.Font.SourceSansBold
		label.TextSize = 13
		label.TextXAlignment = Enum.TextXAlignment.Left
		label.Parent = AimSpeedFrame
		return label
	end

	local AimButton = Instance.new("TextButton")
	AimButton.Size = UDim2.new(0, 76, 0, 24)
	AimButton.Position = UDim2.new(0, 5, 0, 40)
	AimButton.BackgroundColor3 = COLOR_ON
	AimButton.Text = "AIM: ON"
	AimButton.TextColor3 = COLOR_TEXT
	AimButton.Font = Enum.Font.SourceSansBold
	AimButton.TextSize = 12
	AimButton.BorderSizePixel = 0
	AimButton.Parent = AimSpeedFrame
	local AimButtonCorner = Instance.new("UICorner")
	AimButtonCorner.CornerRadius = UDim.new(0, 4)
	AimButtonCorner.Parent = AimButton
	addHover(AimButton, 0.08)

	local RmbLabel = Instance.new("TextLabel")
	RmbLabel.Size = UDim2.new(0, 145, 0, 24)
	RmbLabel.Position = UDim2.new(0, 88, 0, 40)
	RmbLabel.BackgroundTransparency = 1
	RmbLabel.Text = "ПКМ — захват"
	RmbLabel.TextColor3 = COLOR_TEXT_DIM
	RmbLabel.Font = Enum.Font.SourceSans
	RmbLabel.TextSize = 12
	RmbLabel.TextXAlignment = Enum.TextXAlignment.Left
	RmbLabel.Parent = AimSpeedFrame

	local TargetLabel = makeControlLabel("Цель: голова", 72)
	local HeadButton = Instance.new("TextButton")
	HeadButton.Size = UDim2.new(0, 110, 0, 23)
	HeadButton.Position = UDim2.new(0, 5, 0, 94)
	HeadButton.BackgroundColor3 = COLOR_ACCENT
	HeadButton.Text = "ГОЛОВА"
	HeadButton.TextColor3 = COLOR_TEXT
	HeadButton.Font = Enum.Font.SourceSansBold
	HeadButton.TextSize = 12
	HeadButton.BorderSizePixel = 0
	HeadButton.Parent = AimSpeedFrame
	local HeadCorner = Instance.new("UICorner")
	HeadCorner.CornerRadius = UDim.new(0, 4)
	HeadCorner.Parent = HeadButton

	local TorsoButton = HeadButton:Clone()
	TorsoButton.Position = UDim2.new(0, 120, 0, 94)
	TorsoButton.BackgroundColor3 = COLOR_FIELD
	TorsoButton.Text = "ТОРС"
	TorsoButton.Parent = AimSpeedFrame

	local function updatePartButtons()
		HeadButton.BackgroundColor3 = aimPart == "Head" and COLOR_ACCENT or COLOR_FIELD
		TorsoButton.BackgroundColor3 = aimPart == "Torso" and COLOR_ACCENT or COLOR_FIELD
		TargetLabel.Text = aimPart == "Head" and "Цель: голова" or "Цель: торс"
	end
	HeadButton.MouseButton1Click:Connect(function() aimPart = "Head"; updatePartButtons() end)
	TorsoButton.MouseButton1Click:Connect(function() aimPart = "Torso"; updatePartButtons() end)

	local TeamButtonAim = Instance.new("TextButton")
	TeamButtonAim.Size = UDim2.new(0, 110, 0, 23)
	TeamButtonAim.Position = UDim2.new(0, 5, 0, 122)
	TeamButtonAim.BackgroundColor3 = COLOR_ON
	TeamButtonAim.Text = "TEAM: ON"
	TeamButtonAim.TextColor3 = COLOR_TEXT
	TeamButtonAim.Font = Enum.Font.SourceSansBold
	TeamButtonAim.TextSize = 12
	TeamButtonAim.BorderSizePixel = 0
	TeamButtonAim.Parent = AimSpeedFrame
	local TeamAimCorner = Instance.new("UICorner")
	TeamAimCorner.CornerRadius = UDim.new(0, 4)
	TeamAimCorner.Parent = TeamButtonAim

	local WallButtonAim = TeamButtonAim:Clone()
	WallButtonAim.Position = UDim2.new(0, 120, 0, 122)
	WallButtonAim.Text = "WALL: ON"
	WallButtonAim.Parent = AimSpeedFrame

	local function updateChecks()
		TeamButtonAim.BackgroundColor3 = teamCheck and COLOR_ON or COLOR_OFF
		TeamButtonAim.Text = teamCheck and "TEAM: ON" or "TEAM: OFF"
		WallButtonAim.BackgroundColor3 = wallCheck and COLOR_ON or COLOR_OFF
		WallButtonAim.Text = wallCheck and "WALL: ON" or "WALL: OFF"
	end
	TeamButtonAim.MouseButton1Click:Connect(function() teamCheck = not teamCheck; updateChecks() end)
	WallButtonAim.MouseButton1Click:Connect(function() wallCheck = not wallCheck; updateChecks() end)

	local RadiusLabel = makeControlLabel("Радиус: 120", 150)
	local RadiusTrack = Instance.new("Frame")
	RadiusTrack.Size = UDim2.new(1, -20, 0, 7)
	RadiusTrack.Position = UDim2.new(0, 10, 0, 174)
	RadiusTrack.BackgroundColor3 = COLOR_FIELD
	RadiusTrack.BorderSizePixel = 0
	RadiusTrack.Parent = AimSpeedFrame
	local RadiusTrackCorner = Instance.new("UICorner")
	RadiusTrackCorner.CornerRadius = UDim.new(1, 0)
	RadiusTrackCorner.Parent = RadiusTrack
	local RadiusFill = Instance.new("Frame")
	RadiusFill.Size = UDim2.new((aimRadius - 50) / 250, 0, 1, 0)
	RadiusFill.BackgroundColor3 = COLOR_ACCENT
	RadiusFill.BorderSizePixel = 0
	RadiusFill.Parent = RadiusTrack
	local RadiusFillCorner = Instance.new("UICorner")
	RadiusFillCorner.CornerRadius = UDim.new(1, 0)
	RadiusFillCorner.Parent = RadiusFill
	local RadiusKnob = Instance.new("TextButton")
	RadiusKnob.Size = UDim2.new(0, 16, 0, 16)
	RadiusKnob.AnchorPoint = Vector2.new(0.5, 0.5)
	RadiusKnob.Position = UDim2.new((aimRadius - 50) / 250, 0, 0.5, 0)
	RadiusKnob.BackgroundColor3 = COLOR_TEXT
	RadiusKnob.Text = ""
	RadiusKnob.BorderSizePixel = 0
	RadiusKnob.Parent = RadiusTrack
	local RadiusKnobCorner = Instance.new("UICorner")
	RadiusKnobCorner.CornerRadius = UDim.new(1, 0)
	RadiusKnobCorner.Parent = RadiusKnob

	local StrengthLabel = makeControlLabel("Сила: 70%", 180)
	local StrengthTrack = RadiusTrack:Clone()
	StrengthTrack.Position = UDim2.new(0, 10, 0, 204)
	StrengthTrack:ClearAllChildren()
	StrengthTrack.Parent = AimSpeedFrame
	local StrengthFill = Instance.new("Frame")
	StrengthFill.Size = UDim2.new(aimStrength / 100, 0, 1, 0)
	StrengthFill.BackgroundColor3 = COLOR_ACCENT
	StrengthFill.BorderSizePixel = 0
	StrengthFill.Parent = StrengthTrack
	local StrengthFillCorner = Instance.new("UICorner")
	StrengthFillCorner.CornerRadius = UDim.new(1, 0)
	StrengthFillCorner.Parent = StrengthFill
	local StrengthKnob = Instance.new("TextButton")
	StrengthKnob.Size = UDim2.new(0, 16, 0, 16)
	StrengthKnob.AnchorPoint = Vector2.new(0.5, 0.5)
	StrengthKnob.Position = UDim2.new(aimStrength / 100, 0, 0.5, 0)
	StrengthKnob.BackgroundColor3 = COLOR_TEXT
	StrengthKnob.Text = ""
	StrengthKnob.BorderSizePixel = 0
	StrengthKnob.Parent = StrengthTrack
	local StrengthKnobCorner = Instance.new("UICorner")
	StrengthKnobCorner.CornerRadius = UDim.new(1, 0)
	StrengthKnobCorner.Parent = StrengthKnob

	local SpeedLabel = makeControlLabel("Скорость: 20", 216)
	local SpeedTrack = RadiusTrack:Clone()
	SpeedTrack.Position = UDim2.new(0, 10, 0, 240)
	SpeedTrack:ClearAllChildren()
	SpeedTrack.Parent = AimSpeedFrame
	local SpeedFill = Instance.new("Frame")
	SpeedFill.Size = UDim2.new(0, 0, 1, 0)
	SpeedFill.BackgroundColor3 = COLOR_ACCENT
	SpeedFill.BorderSizePixel = 0
	SpeedFill.Parent = SpeedTrack
	local SpeedFillCorner = Instance.new("UICorner")
	SpeedFillCorner.CornerRadius = UDim.new(1, 0)
	SpeedFillCorner.Parent = SpeedFill
	local SpeedKnob = Instance.new("TextButton")
	SpeedKnob.Size = UDim2.new(0, 16, 0, 16)
	SpeedKnob.AnchorPoint = Vector2.new(0.5, 0.5)
	SpeedKnob.Position = UDim2.new(0, 0, 0.5, 0)
	SpeedKnob.BackgroundColor3 = COLOR_TEXT
	SpeedKnob.Text = ""
	SpeedKnob.BorderSizePixel = 0
	SpeedKnob.Parent = SpeedTrack
	local SpeedKnobCorner = Instance.new("UICorner")
	SpeedKnobCorner.CornerRadius = UDim.new(1, 0)
	SpeedKnobCorner.Parent = SpeedKnob
	local AimCircle = Instance.new("Frame")
	AimCircle.Name = "AimCaptureCircle"
	AimCircle.AnchorPoint = Vector2.new(0.5, 0.5)
	AimCircle.Position = UDim2.new(0.5, 0, 0.5, 0)
	AimCircle.Size = UDim2.new(0, aimRadius * 2, 0, aimRadius * 2)
	AimCircle.BackgroundTransparency = 1
	AimCircle.BorderSizePixel = 0
	AimCircle.Visible = false
	AimCircle.ZIndex = 100
	AimCircle.Parent = ScreenGui
	local AimCircleCorner = Instance.new("UICorner")
	AimCircleCorner.CornerRadius = UDim.new(1, 0)
	AimCircleCorner.Parent = AimCircle
	local AimCircleStroke = Instance.new("UIStroke")
	AimCircleStroke.Color = COLOR_ACCENT
	AimCircleStroke.Thickness = 2
	AimCircleStroke.Transparency = 0.15
	AimCircleStroke.Parent = AimCircle

	local function setAimCircle()
		AimCircle.Size = UDim2.new(0, aimRadius * 2, 0, aimRadius * 2)
		AimCircle.Visible = aimEnabled and aimHolding
		RadiusLabel.Text = "Радиус: " .. aimRadius
		RadiusFill.Size = UDim2.new((aimRadius - 50) / 250, 0, 1, 0)
		RadiusKnob.Position = UDim2.new((aimRadius - 50) / 250, 0, 0.5, 0)
		StrengthLabel.Text = "Сила: " .. aimStrength .. "%"
		StrengthFill.Size = UDim2.new(aimStrength / 100, 0, 1, 0)
		StrengthKnob.Position = UDim2.new(aimStrength / 100, 0, 0.5, 0)
		SpeedLabel.Text = "Скорость: " .. currentWalkSpeed
		SpeedFill.Size = UDim2.new((currentWalkSpeed - 20) / 30, 0, 1, 0)
		SpeedKnob.Position = UDim2.new((currentWalkSpeed - 20) / 30, 0, 0.5, 0)
	end

	local function sliderPercent(input, track)
		local width = track.AbsoluteSize.X
		if width <= 0 then return 0 end
		return math.clamp((input.Position.X - track.AbsolutePosition.X) / width, 0, 1)
	end

	local dragRadius, dragStrength, dragSpeed = false, false, false
	local function applySlider(input)
		if dragRadius then
			aimRadius = math.floor(50 + sliderPercent(input, RadiusTrack) * 250 + 0.5)
		elseif dragStrength then
			aimStrength = math.floor(1 + sliderPercent(input, StrengthTrack) * 99 + 0.5)
		elseif dragSpeed then
			currentWalkSpeed = math.floor(20 + sliderPercent(input, SpeedTrack) * 30 + 0.5)
		end
		setAimCircle()
	end

	RadiusKnob.MouseButton1Down:Connect(function() dragRadius = true end)
	RadiusTrack.InputBegan:Connect(function(input)
		if input.UserInputType == Enum.UserInputType.MouseButton1 then dragRadius = true; applySlider(input) end
	end)
	StrengthKnob.MouseButton1Down:Connect(function() dragStrength = true end)
	StrengthTrack.InputBegan:Connect(function(input)
		if input.UserInputType == Enum.UserInputType.MouseButton1 then dragStrength = true; applySlider(input) end
	end)
	SpeedKnob.MouseButton1Down:Connect(function() dragSpeed = true end)
	SpeedTrack.InputBegan:Connect(function(input)
		if input.UserInputType == Enum.UserInputType.MouseButton1 then dragSpeed = true; applySlider(input) end
	end)
	UserInputService.InputChanged:Connect(function(input)
		if input.UserInputType == Enum.UserInputType.MouseMovement then applySlider(input) end
	end)
	UserInputService.InputEnded:Connect(function(input)
		if input.UserInputType == Enum.UserInputType.MouseButton1 then dragRadius = false; dragStrength = false; dragSpeed = false end
	end)

	AimButton.MouseButton1Click:Connect(function()
		aimEnabled = not aimEnabled
		AimButton.Text = aimEnabled and "AIM: ON" or "AIM: OFF"
		AimButton.BackgroundColor3 = aimEnabled and COLOR_ON or COLOR_OFF
		if not aimEnabled then aimHolding = false end
		setAimCircle()
	end)

	UserInputService.InputBegan:Connect(function(input, processed)
		if processed then return end
		if input.UserInputType == Enum.UserInputType.MouseButton2 then
			aimHolding = true
			setAimCircle()
		end
	end)
	UserInputService.InputEnded:Connect(function(input)
		if input.UserInputType == Enum.UserInputType.MouseButton2 then
			aimHolding = false
			setAimCircle()
		end
	end)

	local function getAimPart(character)
		if aimPart == "Head" then return character:FindFirstChild("Head") end
		return character:FindFirstChild("UpperTorso") or character:FindFirstChild("Torso") or character:FindFirstChild("HumanoidRootPart")
	end

	local function validTarget(player)
		if player == LocalPlayer then return false end
		local character = player.Character
		local humanoid = character and character:FindFirstChildOfClass("Humanoid")
		if not humanoid or humanoid.Health <= 0 then return false end
		if teamCheck and LocalPlayer.Team and player.Team and LocalPlayer.Team == player.Team then return false end
		local part = getAimPart(character)
		if not part then return false end
		if wallCheck then
			local camera = Workspace.CurrentCamera
			if not camera then return false end
			local origin = camera.CFrame.Position
			local direction = part.Position - origin
			local params = RaycastParams.new()
			params.FilterType = Enum.RaycastFilterType.Exclude
			params.FilterDescendantsInstances = {LocalPlayer.Character, AimSpeedFrame, AimCircle}
			local result = Workspace:Raycast(origin, direction, params)
			if result and not result.Instance:IsDescendantOf(character) then return false end
		end
		return true
	end

	local function getBestTarget()
		local camera = Workspace.CurrentCamera
		if not camera then return nil end
		local center = Vector2.new(camera.ViewportSize.X / 2, camera.ViewportSize.Y / 2)
		local best, bestDistance = nil, aimRadius
		for _, player in ipairs(Players:GetPlayers()) do
			if validTarget(player) then
				local part = getAimPart(player.Character)
				local point, visible = camera:WorldToViewportPoint(part.Position)
				if visible and point.Z > 0 then
					local distance = (Vector2.new(point.X, point.Y) - center).Magnitude
					if distance <= bestDistance then bestDistance = distance; best = part end
				end
			end
		end
		return best
	end

	RunService.RenderStepped:Connect(function()
		if not aimEnabled or not aimHolding then return end
		local camera = Workspace.CurrentCamera
		local target = getBestTarget()
		if camera and target then
			local desired = CFrame.lookAt(camera.CFrame.Position, target.Position)
			local alpha = math.clamp(aimStrength / 100, 0.01, 1)
			camera.CFrame = camera.CFrame:Lerp(desired, alpha)
		end
	end)

	task.spawn(function()
		while AimSpeedFrame and AimSpeedFrame.Parent do
			task.wait(1)
			local character = LocalPlayer.Character
			local humanoid = character and character:FindFirstChildOfClass("Humanoid")
			if humanoid and humanoid.WalkSpeed ~= currentWalkSpeed then humanoid.WalkSpeed = currentWalkSpeed end
		end
	end)

	LocalPlayer.CharacterAdded:Connect(function(character)
		local humanoid = character:WaitForChild("Humanoid", 5)
		if humanoid then humanoid.WalkSpeed = currentWalkSpeed end
	end)

	-- Перетаскивание второго окна за его шапку
	local aimDragging = false
	local aimDragStart
	local aimStartPosition
	AimSpeedTitle.InputBegan:Connect(function(input)
		if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
			aimDragging = true
			aimDragStart = input.Position
			aimStartPosition = AimSpeedFrame.Position
			input.Changed:Connect(function()
				if input.UserInputState == Enum.UserInputState.End then aimDragging = false end
			end)
		end
	end)
	UserInputService.InputChanged:Connect(function(input)
		if not aimDragging then return end
		if input.UserInputType == Enum.UserInputType.MouseMovement or input.UserInputType == Enum.UserInputType.Touch then
			local delta = input.Position - aimDragStart
			AimSpeedFrame.Position = UDim2.new(aimStartPosition.X.Scale, aimStartPosition.X.Offset + delta.X, aimStartPosition.Y.Scale, aimStartPosition.Y.Offset + delta.Y)
		end
	end)

	updatePartButtons()
	updateChecks()
	setAimCircle()
end

-- НОВОЕ: красный контур по краю окна — основа всего оформления
local MainStroke = Instance.new("UIStroke")
MainStroke.Color = COLOR_EDGE
MainStroke.Thickness = 1
MainStroke.Parent = MainFrame

local MainCorner = Instance.new("UICorner")
MainCorner.CornerRadius = UDim.new(0, 8)
MainCorner.Parent = MainFrame

--==================================================
-- TITLE
--==================================================
local Title = Instance.new("TextLabel")
Title.Name = "Title"
Title.Size = UDim2.new(1, -100, 0, 30)
Title.BackgroundColor3 = COLOR_HEADER
-- НОВОЕ: в заголовке видно выбранный режим
Title.Text = " Трекер: " .. features.label
Title.TextColor3 = COLOR_TEXT
Title.TextXAlignment = Enum.TextXAlignment.Left
Title.Font = Enum.Font.SourceSansBold
Title.TextSize = 16
Title.BorderSizePixel = 0
Title.Parent = MainFrame

local TitleCorner = Instance.new("UICorner")
TitleCorner.CornerRadius = UDim.new(0, 8)
TitleCorner.Parent = Title

-- НОВОЕ: красная линия под шапкой, отделяет заголовок от содержимого
local TitleUnderline = Instance.new("Frame")
TitleUnderline.Name = "TitleUnderline"
TitleUnderline.Size = UDim2.new(1, -10, 0, 1)
TitleUnderline.Position = UDim2.new(0, 5, 0, 31)
TitleUnderline.BackgroundColor3 = COLOR_ACCENT
TitleUnderline.BackgroundTransparency = 0.35
TitleUnderline.BorderSizePixel = 0
TitleUnderline.Parent = MainFrame

--==================================================
-- ESP BUTTON
--==================================================
local EspButton = Instance.new("TextButton")
EspButton.Name = "EspButton"
EspButton.Size = UDim2.new(0, 45, 0, 22)
EspButton.Position = UDim2.new(1, -95, 0, 4)
EspButton.BackgroundColor3 = COLOR_ON
EspButton.Text = "ESP"
EspButton.TextColor3 = COLOR_TEXT
EspButton.Font = Enum.Font.SourceSansBold
EspButton.TextSize = 12
EspButton.BorderSizePixel = 0
EspButton.Parent = MainFrame

local EspCorner = Instance.new("UICorner")
EspCorner.CornerRadius = UDim.new(0, 4)
EspCorner.Parent = EspButton

-- НОВОЕ: подсветка при наведении, а setEspColor красит кнопку по состоянию
local setEspColor = addHover(EspButton, 0.08)

--==================================================
-- LINE BUTTON
--==================================================
local LineButton = Instance.new("TextButton")
LineButton.Name = "LineButton"
LineButton.Size = UDim2.new(0, 45, 0, 22)
LineButton.Position = UDim2.new(1, -45, 0, 4)
LineButton.BackgroundColor3 = COLOR_ON
LineButton.Text = "LINE"
LineButton.TextColor3 = COLOR_TEXT
LineButton.Font = Enum.Font.SourceSansBold
LineButton.TextSize = 12
LineButton.BorderSizePixel = 0
LineButton.Parent = MainFrame

local LineCorner = Instance.new("UICorner")
LineCorner.CornerRadius = UDim.new(0, 4)
LineCorner.Parent = LineButton

local setLineColor = addHover(LineButton, 0.08)

--==================================================
-- TEAM BUTTON (НОВОЕ)
--==================================================
-- Кнопка показывает текущий фильтр, по клику разворачивается список тим
local TeamButton = Instance.new("TextButton")
TeamButton.Name = "TeamButton"
-- НОВОЕ: справа кнопка ШЕР, поэтому строка укорочена. В Jail break
-- кнопки нет и строка занимает всю ширину
local teamButtonInset = -10
if features.securityButton then
	teamButtonInset = -125
end
TeamButton.Size = UDim2.new(1, teamButtonInset, 0, 20)
TeamButton.Position = UDim2.new(0, 5, 0, 34)
TeamButton.BackgroundColor3 = COLOR_FIELD
TeamButton.AutoButtonColor = true
TeamButton.Text = ""
TeamButton.TextColor3 = COLOR_TEXT
TeamButton.TextXAlignment = Enum.TextXAlignment.Left
TeamButton.Font = Enum.Font.SourceSansBold
TeamButton.TextSize = 11
TeamButton.TextTruncate = Enum.TextTruncate.AtEnd
TeamButton.BorderSizePixel = 0
TeamButton.ZIndex = 2
TeamButton.Parent = MainFrame

local TeamButtonCorner = Instance.new("UICorner")
TeamButtonCorner.CornerRadius = UDim.new(0, 4)
TeamButtonCorner.Parent = TeamButton

-- НОВОЕ: рамка того же красного, что и у окна
local TeamButtonStroke = Instance.new("UIStroke")
TeamButtonStroke.Color = COLOR_EDGE
TeamButtonStroke.Thickness = 1
TeamButtonStroke.Transparency = 0.35
TeamButtonStroke.Parent = TeamButton

local TeamButtonPadding = Instance.new("UIPadding")
TeamButtonPadding.PaddingLeft = UDim.new(0, 8)
-- отступ справа с запасом под стрелку, иначе длинное имя тимы налезает на неё
TeamButtonPadding.PaddingRight = UDim.new(0, 22)
TeamButtonPadding.Parent = TeamButton

local TeamArrow = Instance.new("TextLabel")
TeamArrow.Name = "Arrow"
TeamArrow.Size = UDim2.new(0, 12, 1, 0)
-- позиция считается внутри отступов UIPadding, поэтому смещение положительное
TeamArrow.Position = UDim2.new(1, 4, 0, 0)
TeamArrow.BackgroundTransparency = 1
TeamArrow.Text = "\226\150\188"
TeamArrow.TextColor3 = COLOR_ACCENT
TeamArrow.Font = Enum.Font.SourceSansBold
TeamArrow.TextSize = 10
TeamArrow.ZIndex = 3
TeamArrow.Parent = TeamButton

--==================================================
-- КНОПКА ШЕР (НОВОЕ)
--==================================================
-- Просит у сервера ту же смену работы, что и подход к job-паду.
-- Решает всё равно сервер: если он не согласен, ничего не произойдёт
local SHER_TEXT = "ШЕР"

-- НОВОЕ: работа Security есть только в Drive Empire, поэтому в Jail break
-- кнопка вообще не создаётся, а переменная остаётся nil
local JobButton = nil

if features.securityButton then
	JobButton = Instance.new("TextButton")
	JobButton.Name = "JobButton"
	JobButton.Size = UDim2.new(0, 48, 0, 20)
	JobButton.Position = UDim2.new(1, -53, 0, 34)
	JobButton.BackgroundColor3 = Color3.fromRGB(150, 30, 38)
	JobButton.Text = SHER_TEXT
	JobButton.TextColor3 = COLOR_TEXT
	JobButton.Font = Enum.Font.SourceSansBold
	JobButton.TextSize = 11
	JobButton.BorderSizePixel = 0
	JobButton.ZIndex = 2
	JobButton.Parent = MainFrame

	local JobButtonCorner = Instance.new("UICorner")
	JobButtonCorner.CornerRadius = UDim.new(0, 4)
	JobButtonCorner.Parent = JobButton

	addHover(JobButton, 0.08)
end

--==================================================
-- A-LOOP TOP-1
--==================================================
local AutoLoopButton = nil
local autoLoopRunning = false
local autoLoopTargetUserId = nil

local function stopAutoLoop()
	autoLoopRunning = false
	autoLoopTargetUserId = nil
	if AutoLoopButton and AutoLoopButton.Parent then
		AutoLoopButton.Text = AUTO_LOOP_BUTTON_TEXT
		AutoLoopButton.BackgroundColor3 = COLOR_FIELD
	end
end

local function getAutoLoopTarget()
	local bestPlayer = nil
	local bestCapture = -1
	local bestBounty = -1

	for _, player in ipairs(Players:GetPlayers()) do
		if player ~= LocalPlayer and matchesFilter(player) then
			local capture = getCaptureValue(player, getBountyValue(player))
			local bounty = getBountyValue(player)
			if capture > AUTO_LOOP_MIN_CAPTURE then
				if capture > bestCapture
					or (capture == bestCapture and bounty > bestBounty) then
					bestPlayer = player
					bestCapture = capture
					bestBounty = bounty
				end
			end
		end
	end

	return bestPlayer
end

local function startAutoLoop()
	if autoLoopRunning then
		return
	end

	autoLoopRunning = true
	AutoLoopButton.Text = AUTO_LOOP_ACTIVE_TEXT
	AutoLoopButton.BackgroundColor3 = COLOR_ON

	task.spawn(function()
		while autoLoopRunning do
			local target = nil
			if autoLoopTargetUserId then
				target = Players:GetPlayerByUserId(autoLoopTargetUserId)
			end

			-- Если старой цели больше нет или она больше не подходит
			-- выбранной тиме/порогу — ищем новый TOP-1.
			if not target
				or not target.Parent
				or not matchesFilter(target)
				or getCaptureValue(target, getBountyValue(target)) <= AUTO_LOOP_MIN_CAPTURE then
				target = getAutoLoopTarget()
				autoLoopTargetUserId = target and target.UserId or nil
			end

			if target then
				local myCharacter = LocalPlayer.Character
				local targetCharacter = target.Character
				local myRoot = myCharacter and myCharacter:FindFirstChild("HumanoidRootPart")
				local targetRoot = targetCharacter and targetCharacter:FindFirstChild("HumanoidRootPart")

				if myRoot and targetRoot then
					myRoot.CFrame = targetRoot.CFrame
				end
			end

			task.wait(AUTO_LOOP_INTERVAL)
		end
	end)
end

if AUTO_LOOP_ENABLED then
	AutoLoopButton = Instance.new("TextButton")
	AutoLoopButton.Name = "AutoLoopButton"
	AutoLoopButton.Size = UDim2.new(0, 62, 0, 20)
	AutoLoopButton.Position = UDim2.new(1, -120, 0, 34)
	AutoLoopButton.BackgroundColor3 = COLOR_FIELD
	AutoLoopButton.BorderSizePixel = 0
	AutoLoopButton.Text = AUTO_LOOP_BUTTON_TEXT
	AutoLoopButton.TextColor3 = COLOR_TEXT
	AutoLoopButton.Font = Enum.Font.SourceSansBold
	AutoLoopButton.TextSize = 10
	AutoLoopButton.ZIndex = 2
	AutoLoopButton.Parent = MainFrame

	local AutoLoopCorner = Instance.new("UICorner")
	AutoLoopCorner.CornerRadius = UDim.new(0, 4)
	AutoLoopCorner.Parent = AutoLoopButton

	addHover(AutoLoopButton, 0.08)

	AutoLoopButton.MouseButton1Click:Connect(function()
		if autoLoopRunning then
			stopAutoLoop()
		else
			startAutoLoop()
		end
	end)
end

--==================================================
-- TEAM DROPDOWN (НОВОЕ)
--==================================================
-- Высокий ZIndex, чтобы список ложился поверх таблицы,
-- а не прятался под карточками игроков
local TeamDropdown = Instance.new("ScrollingFrame")
TeamDropdown.Name = "TeamDropdown"
-- НОВОЕ: высота нулевая, список раскрывается анимацией при нажатии
TeamDropdown.Size = UDim2.new(1, -10, 0, 0)
TeamDropdown.Position = UDim2.new(0, 5, 0, 55)
TeamDropdown.BackgroundColor3 = COLOR_FIELD
TeamDropdown.BorderSizePixel = 0
TeamDropdown.CanvasSize = UDim2.new(0, 0, 0, 0)
TeamDropdown.ScrollBarThickness = 4
TeamDropdown.ScrollBarImageColor3 = COLOR_ACCENT
TeamDropdown.ScrollBarImageTransparency = 0.3
TeamDropdown.ClipsDescendants = true
TeamDropdown.Visible = false
TeamDropdown.ZIndex = 10
TeamDropdown.Parent = MainFrame

local TeamDropdownCorner = Instance.new("UICorner")
TeamDropdownCorner.CornerRadius = UDim.new(0, 4)
TeamDropdownCorner.Parent = TeamDropdown

-- НОВОЕ: список тоже в рамке, иначе на тёмном фоне не видно его границ
local TeamDropdownStroke = Instance.new("UIStroke")
TeamDropdownStroke.Color = COLOR_EDGE
TeamDropdownStroke.Thickness = 1
TeamDropdownStroke.Parent = TeamDropdown

local TeamDropdownLayout = Instance.new("UIListLayout")
TeamDropdownLayout.SortOrder = Enum.SortOrder.LayoutOrder
TeamDropdownLayout.Padding = UDim.new(0, DROPDOWN_ROW_GAP)
TeamDropdownLayout.Parent = TeamDropdown

--==================================================
-- SCROLLING FRAME
--==================================================
local ScrollingFrame = Instance.new("ScrollingFrame")
ScrollingFrame.Name = "PlayerList"
-- НОВОЕ: список сдвинут вниз, чтобы не залезать на кнопку выбора тимы,
-- и укорочен снизу под строку с пингом
ScrollingFrame.Size = UDim2.new(1, -10, 1, -83)
ScrollingFrame.Position = UDim2.new(0, 5, 0, 58)
ScrollingFrame.BackgroundTransparency = 1
ScrollingFrame.BorderSizePixel = 0
ScrollingFrame.CanvasSize = UDim2.new(0, 0, 0, 0)
ScrollingFrame.ScrollBarThickness = 4
-- НОВОЕ: полоса прокрутки в цвет темы, а не серая по умолчанию
ScrollingFrame.ScrollBarImageColor3 = COLOR_ACCENT
ScrollingFrame.ScrollBarImageTransparency = 0.3
ScrollingFrame.Parent = MainFrame

local UIListLayout = Instance.new("UIListLayout")
UIListLayout.SortOrder = Enum.SortOrder.LayoutOrder
UIListLayout.Padding = UDim.new(0, 4)
UIListLayout.Parent = ScrollingFrame

--==================================================
-- НИЖНЯЯ СТРОКА: ПИНГ И СЧЁТЧИК (НОВОЕ)
--==================================================
-- Тонкая черта отделяет строку от списка
local FooterLine = Instance.new("Frame")
FooterLine.Name = "FooterLine"
FooterLine.Size = UDim2.new(1, -10, 0, 1)
FooterLine.Position = UDim2.new(0, 5, 1, -24)
FooterLine.BackgroundColor3 = COLOR_ACCENT
FooterLine.BackgroundTransparency = 0.6
FooterLine.BorderSizePixel = 0
FooterLine.Parent = MainFrame

local PingLabel = Instance.new("TextLabel")
PingLabel.Name = "PingLabel"
PingLabel.Size = UDim2.new(0.5, -6, 0, 16)
PingLabel.Position = UDim2.new(0, 7, 1, -20)
PingLabel.BackgroundTransparency = 1
PingLabel.Text = "Пинг: —"
PingLabel.TextColor3 = COLOR_TEXT_DIM
PingLabel.Font = Enum.Font.SourceSansBold
PingLabel.TextSize = 12
PingLabel.TextXAlignment = Enum.TextXAlignment.Left
PingLabel.Parent = MainFrame

local CountLabel = Instance.new("TextLabel")
CountLabel.Name = "CountLabel"
CountLabel.Size = UDim2.new(0.5, -6, 0, 16)
CountLabel.Position = UDim2.new(0.5, 0, 1, -20)
CountLabel.BackgroundTransparency = 1
CountLabel.Text = "в списке: 0"
CountLabel.TextColor3 = COLOR_TEXT_DIM
CountLabel.Font = Enum.Font.SourceSans
CountLabel.TextSize = 12
CountLabel.TextXAlignment = Enum.TextXAlignment.Right
CountLabel.Parent = MainFrame

-- Пинг живёт в Stats, но путь к нему у исполнителей иногда закрыт,
-- поэтому чтение обёрнуто в pcall и при отказе показывается прочерк
local function readPing()
	local ok, value = pcall(function()
		return Stats.Network.ServerStatsItem["Data Ping"]:GetValue()
	end)
	if not ok or type(value) ~= "number" then
		return nil
	end
	return math.floor(value + 0.5)
end

local PING_GOOD = 80
local PING_OKAY = 150

local function refreshPing()
	local ping = readPing()
	if not ping then
		PingLabel.Text = "Пинг: —"
		PingLabel.TextColor3 = COLOR_TEXT_DIM
		return
	end
	PingLabel.Text = "Пинг: " .. ping .. " мс"
	if ping <= PING_GOOD then
		PingLabel.TextColor3 = COLOR_ON
	elseif ping <= PING_OKAY then
		PingLabel.TextColor3 = COLOR_MONEY
	else
		PingLabel.TextColor3 = COLOR_OFF
	end
end

-- Раз в секунду: чаще нет смысла, цифра всё равно усреднённая
task.spawn(function()
	while true do
		refreshPing()
		task.wait(1)
	end
end)

--==================================================
-- ЛОГИКА ВЫБОРА ТИМЫ (НОВОЕ)
--==================================================
local function getFilterLabel()
	if teamFilter.mode == "all" then
		return ALL_LABEL
	end
	if teamFilter.mode == "team" then
		return teamFilter.teamName or ALL_LABEL
	end
	return AUTO_LABEL
end

local function updateTeamButtonText()
	TeamButton.Text = "Тима: " .. getFilterLabel()
end

-- Первые два пункта всегда на месте, дальше — тимы, какие есть на сервере
local function buildDropdownEntries()
	local entries = {
		{ mode = "auto", label = AUTO_LABEL },
		{ mode = "all", label = ALL_LABEL },
	}
	local teamList = Teams:GetTeams()
	for _, team in ipairs(teamList) do
		table.insert(entries, {
			mode = "team",
			label = team.Name,
			teamName = team.Name,
			-- НОВОЕ: тот же осветлённый цвет, что и у ников в таблице
			color = readableColor(team.TeamColor.Color),
		})
	end
	return entries
end

local function isEntrySelected(entry)
	if entry.mode ~= teamFilter.mode then
		return false
	end
	if entry.mode == "team" then
		return entry.teamName == teamFilter.teamName
	end
	return true
end

-- Объявлено заранее: setTeamFilter вызывает пересборку списка,
-- а сама пересборка вешает обработчики, вызывающие setTeamFilter
local rebuildDropdown

-- НОВОЕ: список раскрывается и сворачивается анимацией высоты.
-- Состояние держим отдельным флагом, а не полем Visible: пока идёт
-- закрывающая анимация, окно ещё видно, и по Visible нельзя понять,
-- открыт список или уже закрывается
local DROPDOWN_TWEEN = TweenInfo.new(0.18, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
local dropdownHeight = 0
local dropdownOpen = false
local dropdownTween = nil

local function setDropdownOpen(open)
	if open == dropdownOpen then
		return
	end
	dropdownOpen = open
	if dropdownTween then
		-- предыдущую анимацию гасим, иначе она домотает до старой высоты
		dropdownTween:Cancel()
		dropdownTween = nil
	end
	if open then
		-- тимы могли появиться уже после запуска скрипта
		rebuildDropdown()
		TeamDropdown.Size = UDim2.new(1, -10, 0, 0)
		TeamDropdown.Visible = true
		dropdownTween = TweenService:Create(TeamDropdown, DROPDOWN_TWEEN, {
			Size = UDim2.new(1, -10, 0, dropdownHeight),
		})
		dropdownTween:Play()
		TweenService:Create(TeamArrow, DROPDOWN_TWEEN, { Rotation = 180 }):Play()
	else
		dropdownTween = TweenService:Create(TeamDropdown, DROPDOWN_TWEEN, {
			Size = UDim2.new(1, -10, 0, 0),
		})
		dropdownTween:Play()
		TweenService:Create(TeamArrow, DROPDOWN_TWEEN, { Rotation = 0 }):Play()
		local closing = dropdownTween
		task.spawn(function()
			closing.Completed:Wait()
			-- за время анимации список могли открыть заново
			if not dropdownOpen then
				TeamDropdown.Visible = false
			end
		end)
	end
end

local function setTeamFilter(entry)
	teamFilter.mode = entry.mode
	teamFilter.teamName = entry.teamName
	-- Фильтр сменился — выделенный игрок мог из списка выпасть,
	-- и зелёная линия указывала бы в никуда
	selectedUserId = nil
	updateTeamButtonText()
	-- список закрывается сразу после выбора
	setDropdownOpen(false)
	rebuildDropdown()
	updateList()
end

function rebuildDropdown()
	for _, child in ipairs(TeamDropdown:GetChildren()) do
		if child:IsA("TextButton") then
			child:Destroy()
		end
	end

	local entries = buildDropdownEntries()

	for index, entry in ipairs(entries) do
		local option = Instance.new("TextButton")
		option.Name = "Option_" .. index
		option.Size = UDim2.new(1, -8, 0, DROPDOWN_ROW_HEIGHT)
		option.LayoutOrder = index
		option.BorderSizePixel = 0
		option.Text = entry.label
		option.TextXAlignment = Enum.TextXAlignment.Left
		option.Font = Enum.Font.SourceSansBold
		option.TextSize = 13
		option.TextTruncate = Enum.TextTruncate.AtEnd
		option.ZIndex = 11
		if isEntrySelected(entry) then
			option.BackgroundColor3 = Color3.fromRGB(120, 25, 32)
			option.TextColor3 = COLOR_TEXT
		else
			option.BackgroundColor3 = COLOR_ROW
			option.TextColor3 = Color3.fromRGB(215, 205, 207)
		end
		option.Parent = TeamDropdown

		local optionCorner = Instance.new("UICorner")
		optionCorner.CornerRadius = UDim.new(0, 3)
		optionCorner.Parent = option

		local optionPadding = Instance.new("UIPadding")
		-- у тим слева цветной кружок, поэтому текст отодвигается сильнее
		if entry.color then
			optionPadding.PaddingLeft = UDim.new(0, 24)
		else
			optionPadding.PaddingLeft = UDim.new(0, 8)
		end
		optionPadding.PaddingRight = UDim.new(0, 6)
		optionPadding.Parent = option

		if entry.color then
			local dot = Instance.new("Frame")
			dot.Name = "Color"
			dot.Size = UDim2.new(0, 10, 0, 10)
			-- позиция считается уже внутри отступов UIPadding,
			-- поэтому смещение отрицательное
			dot.Position = UDim2.new(0, -16, 0.5, -5)
			dot.BackgroundColor3 = entry.color
			dot.BorderSizePixel = 0
			dot.ZIndex = 12
			dot.Parent = option

			local dotCorner = Instance.new("UICorner")
			dotCorner.CornerRadius = UDim.new(1, 0)
			dotCorner.Parent = dot
		end

		-- НОВОЕ: подсветка пункта под курсором
		addHover(option, 0.05)

		option.MouseButton1Click:Connect(function()
			setTeamFilter(entry)
		end)
	end

	local fullHeight =
		#entries * (DROPDOWN_ROW_HEIGHT + DROPDOWN_ROW_GAP)
		- DROPDOWN_ROW_GAP
	-- НОВОЕ: высота запоминается для анимации раскрытия. Закрытому списку
	-- её присваивать нельзя — он бы дёрнулся и раскрылся сам
	dropdownHeight = math.min(fullHeight, DROPDOWN_MAX_HEIGHT)
	if dropdownOpen then
		TeamDropdown.Size = UDim2.new(1, -10, 0, dropdownHeight)
	end
	TeamDropdown.CanvasSize = UDim2.new(0, 0, 0, fullHeight)
end

TeamButton.MouseButton1Click:Connect(function()
	setDropdownOpen(not dropdownOpen)
end)

Teams.ChildAdded:Connect(function()
	if dropdownOpen then
		rebuildDropdown()
	end
end)

Teams.ChildRemoved:Connect(function(child)
	-- выбранную тиму удалили — возвращаемся в автоматический режим,
	-- иначе таблица молча опустела бы навсегда
	if teamFilter.mode == "team" and teamFilter.teamName == child.Name then
		teamFilter.mode = "auto"
		teamFilter.teamName = nil
		updateTeamButtonText()
	end
	if dropdownOpen then
		rebuildDropdown()
	end
end)

-- НОВОЕ: подсветка кнопки под курсором
addHover(TeamButton, 0.06)

updateTeamButtonText()
rebuildDropdown()

--==================================================
-- VISUALS
--==================================================
local function removeVisuals(character)
	if not character then
		return
	end

	local esp = character:FindFirstChild("BountyESP")
	if esp then
		esp:Destroy()
	end

	local tag = character:FindFirstChild("BountyNameTag")
	if tag then
		tag:Destroy()
	end

	local line = character:FindFirstChild("BountyLine")
	if line then
		line:Destroy()
	end

	-- ФИКС: BountyTarget лежит внутри HumanoidRootPart, а не в самой модели,
	-- поэтому нерекурсивный FindFirstChild его никогда не находил
	local targetAttachment = character:FindFirstChild("BountyTarget", true)
	if targetAttachment then
		targetAttachment:Destroy()
	end
end

-- Найденный дроп запоминается тут. Объявлено до removeAllVisuals намеренно:
-- в Lua обращение к локали, объявленной ниже по файлу, вернёт nil
local dropCache = {
	instance = nil,
	nextScan = 0,
}

local function removeDropVisuals(instance)
	if not instance then
		return
	end

	local box = instance:FindFirstChild("DropESP")
	if box then
		box:Destroy()
	end

	local tag = instance:FindFirstChild("DropTag")
	if tag then
		tag:Destroy()
	end

	local beam = instance:FindFirstChild("DropLine")
	if beam then
		beam:Destroy()
	end

	local targetAttachment = instance:FindFirstChild("DropTarget", true)
	if targetAttachment then
		targetAttachment:Destroy()
	end
end

-- ФИКС: якоря на нашем персонаже тоже нужно уметь снимать поштучно,
-- иначе они копятся при каждом ушедшем игроке
local function removeAnchor(userId)
	local myCharacter = LocalPlayer.Character
	if not myCharacter then
		return
	end

	local myRoot = myCharacter:FindFirstChild("HumanoidRootPart")
	if not myRoot then
		return
	end

	local anchor = myRoot:FindFirstChild(ANCHOR_PREFIX .. userId)
	if anchor then
		anchor:Destroy()
	end
end

local function removeAllVisuals()
	for _, player in ipairs(Players:GetPlayers()) do
		if player.Character then
			removeVisuals(player.Character)
		end
	end

	removeDropVisuals(dropCache.instance)

	local myCharacter = LocalPlayer.Character
	if myCharacter then
		-- ФИКС: якоря создаются в HumanoidRootPart, а обход шёл по GetChildren()
		-- самой модели, поэтому ни один якорь не удалялся
		for _, object in ipairs(myCharacter:GetDescendants()) do
			if object:IsA("Attachment")
				and object.Name:sub(1, #ANCHOR_PREFIX) == ANCHOR_PREFIX then
				object:Destroy()
			end
		end
	end
end

--==================================================
-- ESP
--==================================================
local function createESP(player, distance)
	if not player.Character then
		return
	end

	local character = player.Character
	local root = character:FindFirstChild("HumanoidRootPart")
	if not root then
		return
	end

	-- НОВОЕ: бокс, тег и линия красятся в цвет тимы игрока
	local teamColor = getPlayerColor(player)

	-- BOX
	if espEnabled then
		local box = character:FindFirstChild("BountyESP")
		if not box then
			box = Instance.new("BoxHandleAdornment")
			box.Name = "BountyESP"
			box.Adornee = root
			box.AlwaysOnTop = true
			box.ZIndex = 5
			box.Color3 = teamColor
			box.Transparency = 0.6
			box.Size = Vector3.new(4, 6, 2)
			box.Parent = character
		else
			box.Adornee = root
		end

		-- НОВОЕ: цвет ставится на каждом обновлении, а не только при создании:
		-- игрок мог сменить тиму, пока бокс уже висел на нём
		box.Color3 = teamColor

		-- NAME TAG
		local tag = character:FindFirstChild("BountyNameTag")
		if not tag then
			tag = Instance.new("BillboardGui")
			tag.Name = "BountyNameTag"
			tag.Size = UDim2.new(0, 200, 0, 50)
			tag.StudsOffset = Vector3.new(0, 4, 0)
			tag.AlwaysOnTop = true
			tag.Adornee = root
			tag.Parent = character

			local newLabel = Instance.new("TextLabel")
			newLabel.Name = "Text"
			newLabel.Size = UDim2.new(1, 0, 1, 0)
			newLabel.BackgroundTransparency = 1
			newLabel.TextColor3 = teamColor
			newLabel.Font = Enum.Font.SourceSansBold
			newLabel.TextSize = 16
			newLabel.TextStrokeTransparency = 0
			newLabel.TextStrokeColor3 = Color3.fromRGB(0, 0, 0)
			newLabel.Parent = tag
		else
			-- ФИКС: Adornee терялся, если тег пережил смену HumanoidRootPart
			tag.Adornee = root
		end

		local label = tag:FindFirstChild("Text")
		if label then
			-- НОВОЕ: тег перекрашивается и при смене тимы
			label.TextColor3 = teamColor
			-- ФИКС: при отсутствии персонажа дистанция была MAX_DISTANCE + 1
			-- и в теге показывалось «10001m»
			if distance < MAX_DISTANCE then
				label.Text = player.DisplayName
					.. " ["
					.. tostring(math.floor(distance))
					.. "m]"
			else
				label.Text = player.DisplayName .. " [?m]"
			end
		end
	else
		local box = character:FindFirstChild("BountyESP")
		if box then
			box:Destroy()
		end

		local tag = character:FindFirstChild("BountyNameTag")
		if tag then
			tag:Destroy()
		end
	end
end

--==================================================
-- LINES
--==================================================
local function createLine(player)
	if not linesEnabled then
		return
	end

	if not player.Character then
		return
	end

	local myCharacter = LocalPlayer.Character
	if not myCharacter then
		return
	end

	local myRoot = myCharacter:FindFirstChild("HumanoidRootPart")
	local targetRoot = player.Character:FindFirstChild("HumanoidRootPart")
	if not myRoot or not targetRoot then
		return
	end

	-- Наш Attachment
	local myAttachment = myRoot:FindFirstChild(
		ANCHOR_PREFIX .. player.UserId
	)
	if not myAttachment then
		myAttachment = Instance.new("Attachment")
		myAttachment.Name = ANCHOR_PREFIX .. player.UserId
		myAttachment.Parent = myRoot
	end

	-- Attachment цели
	-- ФИКС: искали в модели, а создавали в HumanoidRootPart, из-за чего
	-- на каждом апдейте плодился новый Attachment
	local targetAttachment = targetRoot:FindFirstChild("BountyTarget")
	if not targetAttachment then
		targetAttachment = Instance.new("Attachment")
		targetAttachment.Name = "BountyTarget"
		targetAttachment.Parent = targetRoot
	end

	-- Beam
	local beam = player.Character:FindFirstChild("BountyLine")
	if not beam then
		beam = Instance.new("Beam")
		beam.Name = "BountyLine"
		beam.Attachment0 = myAttachment
		beam.Attachment1 = targetAttachment
		beam.FaceCamera = true
		beam.ZOffset = 1
		beam.Parent = player.Character
	else
		beam.Attachment0 = myAttachment
		beam.Attachment1 = targetAttachment
	end

	-- Цвет и толщина задаются на каждом вызове, а не только при создании:
	-- иначе выбранная линия не перекрасилась бы обратно после снятия выделения
	if selectedUserId == player.UserId then
		beam.Width0 = SELECT_WIDTH
		beam.Width1 = SELECT_WIDTH
		beam.Color = ColorSequence.new(SELECT_COLOR)
	else
		beam.Width0 = LINE_WIDTH
		beam.Width1 = LINE_WIDTH
		-- НОВОЕ: цвет тимы вместо общего красного. Выделенная кликом линия
		-- остаётся зелёной — иначе выбор не отличить от остальных
		beam.Color = ColorSequence.new(getPlayerColor(player))
	end
end

--==================================================
-- TEAM / BOUNTY
--==================================================
-- Достаём число из любого Value-объекта
local function readNumber(instance)
	if instance:IsA("IntValue") or instance:IsA("NumberValue") then
		return tonumber(instance.Value)
	end
	if instance:IsA("StringValue") then
		-- "$4,200" -> 4200
		return tonumber((instance.Value:gsub("[^%d%.%-]", "")))
	end
	return nil
end

-- Ищем подстроку и в исходном имени, и в приведённом к нижнему регистру:
-- для латиницы работает lower(), для кириллицы — исходное написание
local function containsPattern(name, pattern)
	if name:find(pattern, 1, true) then
		return true
	end
	return name:lower():find(pattern, 1, true) ~= nil
end

-- Голое совпадение по списку, без исключений (нужно для поиска дропа)
local function nameMatchesAny(name, patterns)
	for _, pattern in ipairs(patterns) do
		if containsPattern(name, pattern) then
			return true
		end
	end
	return false
end

local function nameMatches(name, patterns, avoid)
	if nameMatchesAny(name, NAME_EXCLUDE) then
		return false
	end
	-- «Награда за поимку» содержит слово «награда», поэтому поиску самой
	-- награды такие имена нужно отдавать в исключения
	if avoid and nameMatchesAny(name, avoid) then
		return false
	end
	return nameMatchesAny(name, patterns)
end

local function isSkipped(instance)
	if SKIP_NAMES[instance.Name] then
		return true
	end
	return instance:IsA("PlayerGui")
		or instance:IsA("Backpack")
		or instance:IsA("StarterGear")
		or instance:IsA("PlayerScripts")
		or instance:IsA("LuaSourceContainer")
end

-- Где вообще могут лежать данные игрока
local function getSearchRoots(player)
	local roots = { player }

	local shared =
		ReplicatedStorage:FindFirstChild("PlayerData")
		or ReplicatedStorage:FindFirstChild("PlayerStats")
		or ReplicatedStorage:FindFirstChild("Data")

	if shared then
		local mine =
			shared:FindFirstChild(player.Name)
			or shared:FindFirstChild(tostring(player.UserId))
		if mine then
			table.insert(roots, mine)
		end
	end

	return roots
end

-- Обход в ширину с ограничением глубины.
-- minValue отсеивает объекты с подходящим именем, но заведомо неверным
-- значением — иначе поиск залипает на первом попавшемся нуле
local function findValueObject(player, patterns, avoid, minValue)
	for _, root in ipairs(getSearchRoots(player)) do
		local queue = { { root, 0 } }
		local index = 1
		while index <= #queue do
			local container = queue[index][1]
			local depth = queue[index][2]
			index = index + 1
			for _, child in ipairs(container:GetChildren()) do
				if not isSkipped(child) then
					if nameMatches(child.Name, patterns, avoid) then
						local number = readNumber(child)
						if number
							and (not minValue or number >= minValue) then
							return child
						end
					end
					if depth < SEARCH_DEPTH then
						table.insert(queue, { child, depth + 1 })
					end
				end
			end
		end
	end
	return nil
end

local function findAttributeName(player, patterns, avoid, minValue)
	for attributeName, value in pairs(player:GetAttributes()) do
		if type(value) == "number"
			and nameMatches(attributeName, patterns, avoid)
			and (not minValue or value >= minValue) then
			return attributeName
		end
	end
	return nil
end

-- Найденный источник запоминается, чтобы не обходить дерево каждую секунду
local statCache = {}

-- Если значение не нашлось, следующий обход не раньше чем через столько секунд
-- (сервер может создать счётчик позже, поэтому не навсегда)
local RESCAN_INTERVAL = 10

local function getStat(player, key, patterns, avoid, minValue)
	local cache = statCache[player.UserId]
	if not cache then
		cache = {}
		statCache[player.UserId] = cache
	end

	local entry = cache[key]
	if entry then
		-- кэш живой, пока найденный объект не удалили
		if entry.instance and entry.instance.Parent then
			return readNumber(entry.instance) or 0
		end
		if entry.attribute then
			local value = player:GetAttribute(entry.attribute)
			if type(value) == "number" then
				return value
			end
		end
		if entry.missing and os.clock() < entry.missing then
			return 0
		end
		cache[key] = nil
	end

	local found = findValueObject(player, patterns, avoid, minValue)
	if found then
		cache[key] = { instance = found }
		if DEBUG_STATS then
			print(
				"[BountyTracker]",
				player.Name,
				key,
				"->",
				found:GetFullName(),
				"=",
				readNumber(found)
			)
		end
		return readNumber(found) or 0
	end

	local attributeName = findAttributeName(player, patterns, avoid, minValue)
	if attributeName then
		cache[key] = { attribute = attributeName }
		if DEBUG_STATS then
			print(
				"[BountyTracker]",
				player.Name,
				key,
				"-> атрибут",
				attributeName,
				"=",
				player:GetAttribute(attributeName)
			)
		end
		return player:GetAttribute(attributeName) or 0
	end

	if DEBUG_STATS then
		print(
			"[BountyTracker]",
			player.Name,
			key,
			"-> не найдено (проверь имя значения и что оно реплицируется клиенту)"
		)
	end

	cache[key] = { missing = os.clock() + RESCAN_INTERVAL }
	return 0
end

--==================================================
-- ДАННЫЕ ИЗ МОДУЛЕЙ ИГРЫ (НОВОЕ)
--==================================================
-- Источник: ReplicatedStorage.Modules.Shared.Jobs.Criminal.CriminalUtil,
-- рядом с ним JobsUtil, JobsConstants, CriminalConstants. Это те же модули,
-- которыми пользуется сама игра, поэтому числа оттуда точные. Поиск
-- Value-объектов по именам остался запасным вариантом на случай,
-- если модули не подключатся.
--
-- Что в CriminalUtil есть про деньги преступника:
--   GetCurrencyEarned(player)          — сколько наворовано за текущий розыск
--   GetMoneyBagValue(player, tool, id) — стоимость мешка в руках
--   GetCrimesCommitted(player)         — счётчик преступлений
--   GetStarValue(player)               — звёзды розыска, 0..5
--   IsPlayerWanted(player)             — в розыске ли игрок
--
-- Чего в CriminalUtil НЕТ: отдельной функции «сколько дадут за поимку» —
-- выплата считается не в этом модуле. Поэтому цена за поимку берётся
-- из констант криминала (выплата за арест, если она там прописана),
-- а если и там нет — как раньше, процентом от награды (CAPTURE_PERCENT).

local function findByPath(root, path)
	local current = root
	for _, name in ipairs(path) do
		if not current then
			return nil
		end
		current = current:FindFirstChild(name)
	end
	return current
end

-- require чужого модуля может кинуть ошибку (или модуля может не быть),
-- поэтому только через pcall
local function tryRequire(instance)
	if not instance or not instance:IsA("ModuleScript") then
		return nil
	end
	local ok, result = pcall(require, instance)
	if not ok then
		if DEBUG_MODULES then
			warn(
				"[BountyTracker] require не удался:",
				instance:GetFullName(),
				result
			)
		end
		return nil
	end
	return result
end

local sharedModules = findByPath(ReplicatedStorage, { "Modules", "Shared" })

local CriminalUtil =
	tryRequire(findByPath(sharedModules, { "Jobs", "Criminal", "CriminalUtil" }))
local JobsUtil =
	tryRequire(findByPath(sharedModules, { "Jobs", "JobsUtil" }))
local JobsConstants =
	tryRequire(findByPath(sharedModules, { "Jobs", "JobsConstants" }))
local CriminalConstants = tryRequire(
	findByPath(sharedModules, { "Jobs", "Criminal", "CriminalConstants" })
)
local TransactionConstants = tryRequire(
	findByPath(sharedModules, { "Transactions", "TransactionConstants" })
)

-- Если файл констант переименуют — ищем в папке Criminal по подстроке
if CriminalConstants == nil then
	local criminalFolder = findByPath(sharedModules, { "Jobs", "Criminal" })
	if criminalFolder then
		for _, child in ipairs(criminalFolder:GetChildren()) do
			if child:IsA("ModuleScript")
				and child.Name:lower():find("constant", 1, true) then
				CriminalConstants = tryRequire(child)
				break
			end
		end
	end
end

-- Идентификатор наличных для GetMoneyBagValue. Берём из констант транзакций,
-- строка ниже — то, во что он разворачивается, если модуль не подключился
local CASH_CURRENCY_ID = "Cash"
if type(TransactionConstants) == "table"
	and type(TransactionConstants.CurrencyId) == "table"
	and TransactionConstants.CurrencyId.Cash ~= nil then
	CASH_CURRENCY_ID = TransactionConstants.CurrencyId.Cash
end

-- Имя инструмента-мешка проверяет сам CriminalUtil, здесь оно же
local MONEY_BAG_TOOL_NAME = "CriminalMoneyBag"

-- Атрибуты персонажа, из которых модуль читает данные. Нужны как запасной
-- путь: атрибуты реплицируются клиенту и читаются даже без require
local ATTR_CURRENCY_EARNED = "CurrencyEarned"
local ATTR_CRIMES_COMMITTED = "CrimesCommitted"
local ATTR_EXPIRE_EPOCH = "CriminalExpireEpoch"
if type(CriminalConstants) == "table"
	and type(CriminalConstants.PlayerAttributes) == "table" then
	local attributes = CriminalConstants.PlayerAttributes
	ATTR_CURRENCY_EARNED = attributes.CurrencyEarned or ATTR_CURRENCY_EARNED
	ATTR_CRIMES_COMMITTED = attributes.CrimesCommitted or ATTR_CRIMES_COMMITTED
	ATTR_EXPIRE_EPOCH = attributes.CriminalExpireEpoch or ATTR_EXPIRE_EPOCH
end

-- Часть геттеров внутри модуля не проверяет персонажа на nil
-- (GetCurrencyEarned лезет в player.Character напрямую), поэтому вызов
-- обязательно через pcall — иначе один мёртвый игрок уронит весь апдейт
local function callGetter(module, name, ...)
	if type(module) ~= "table" then
		return nil
	end
	local fn = module[name]
	if type(fn) ~= "function" then
		return nil
	end
	local ok, result = pcall(fn, ...)
	if not ok then
		return nil
	end
	return result
end

local function numberFromGetter(module, name, ...)
	local result = callGetter(module, name, ...)
	-- result == result отсекает nan
	if type(result) == "number" and result == result then
		return result
	end
	return nil
end

local function characterAttributeNumber(player, name)
	local character = player.Character
	if not character or name == nil then
		return nil
	end
	local ok, value = pcall(character.GetAttribute, character, name)
	if ok and type(value) == "number" then
		return value
	end
	return nil
end

-- true/false — ответ модуля, nil — спросить не удалось
local function hasCriminalJob(player)
	if type(JobsConstants) ~= "table"
		or type(JobsConstants.JobIds) ~= "table"
		or JobsConstants.JobIds.Criminal == nil then
		return nil
	end
	local result = callGetter(
		JobsUtil,
		"DoesPlayerHaveJob",
		player,
		JobsConstants.JobIds.Criminal
	)
	if result == nil then
		return nil
	end
	return result == true
end

-- true/false — ответ игры, nil — узнать не удалось
local function isPlayerWanted(player)
	local result = callGetter(CriminalUtil, "IsPlayerWanted", player)
	if type(result) == "boolean" then
		return result
	end
	-- запасной путь: тот же атрибут, который читает сам модуль
	local expire = characterAttributeNumber(player, ATTR_EXPIRE_EPOCH)
	if expire and expire > 0 then
		return os.time() < expire
	end
	return nil
end

-- Состояние розыска как объект — то же, чем CriminalHighlight решает,
-- рисовать обводку. Нужно только для дампа: суммы в нём нет
local function getWantedState(player)
	local available = type(CriminalUtil) == "table"
		and type(CriminalUtil.GetWantedState) == "function"
	if not available then
		return nil, false
	end
	return callGetter(CriminalUtil, "GetWantedState", player), true
end

-- Мешок с деньгами в руках игрока. Backpack чужих игроков клиенту
-- не реплицируется, поэтому CriminalUtil.GetAllMoneyBagsValue на других
-- не сработает — смотрим только надетый Tool, он виден всем
local function getCarriedMoneyBagValue(player)
	local character = player.Character
	if not character then
		return 0
	end
	local tool = character:FindFirstChildOfClass("Tool")
	if not tool or tool.Name ~= MONEY_BAG_TOOL_NAME then
		return 0
	end

	local value = numberFromGetter(
		CriminalUtil,
		"GetMoneyBagValue",
		player,
		tool,
		CASH_CURRENCY_ID
	)
	if value and value > 0 then
		return math.floor(value)
	end

	-- запасной путь: базовая сумма по редкости, без множителей
	local rarity = tool:GetAttribute("Rarity")
	if rarity ~= nil then
		local amount = numberFromGetter(
			CriminalUtil,
			"GetMoneyBagAmount",
			player,
			CASH_CURRENCY_ID,
			rarity
		)
		if amount and amount > 0 then
			return math.floor(amount)
		end
	end

	return 0
end

-- Награда — то, что игрок теряет, если его возьмут: наворованное за текущий
-- розыск или мешок в руках. Берём максимум, а не сумму: мешок, скорее всего,
-- уже учтён в CurrencyEarned, и складывать значило бы задвоить
local function getModuleBounty(player)
	local earned = numberFromGetter(CriminalUtil, "GetCurrencyEarned", player)
		or numberFromGetter(
			CriminalUtil,
			"GetTotalCurrencyEarnedDuringWantedState",
			player
		)
		or characterAttributeNumber(player, ATTR_CURRENCY_EARNED)

	local best = math.max(earned or 0, getCarriedMoneyBagValue(player))
	if best > 0 then
		return math.floor(best)
	end
	return nil
end

local function getModuleCrimes(player)
	local value = numberFromGetter(CriminalUtil, "GetCrimesCommitted", player)
	if value == nil then
		value = characterAttributeNumber(player, ATTR_CRIMES_COMMITTED)
	end
	if value and value > 0 then
		return math.floor(value)
	end
	return nil
end

local function getModuleStars(player)
	local value = numberFromGetter(CriminalUtil, "GetStarValue", player)
	if value and value > 0 then
		return math.floor(value)
	end
	return nil
end

-- НОВОЕ: сколько секунд ещё висит розыск. nil — данных нет вообще
local function getWantedRemaining(player)
	-- НОВОЕ: в Jail break таймера розыска нет, данные даже не собираем
	if not features.wantedTimer then
		return nil
	end

	local remaining =
		numberFromGetter(CriminalUtil, "GetWantedTimeRemaining", player)
	if remaining then
		-- отрицательное значит розыск уже истёк
		return math.max(0, math.floor(remaining))
	end

	-- запасной путь: момент окончания розыска лежит атрибутом на персонаже
	local expire = characterAttributeNumber(player, ATTR_EXPIRE_EPOCH)
	if expire and expire > 0 then
		return math.max(0, math.floor(expire - os.time()))
	end

	return nil
end

-- В константах криминала выплата за арест может лежать одним числом или
-- списком по звёздам розыска. Имя ключа заранее неизвестно, поэтому ищем
-- по подстроке — но только в данных, ничего не вызывая
local CAPTURE_KEY_PATTERNS = {
	"arrestreward",
	"arrestpayout",
	"arrestbounty",
	"arrestcash",
	"capturereward",
	"capturepayout",
	"bountyreward",
	"bountypayout",
}
local CAPTURE_SCAN_DEPTH = 3

local function looksLikeCaptureKey(key)
	if type(key) ~= "string" then
		return false
	end
	local lowered = key:lower()
	for _, pattern in ipairs(CAPTURE_KEY_PATTERNS) do
		if lowered:find(pattern, 1, true) then
			return true
		end
	end
	return false
end

-- Таблица вида { [1] = 500, [2] = 1000, ... } — выплата по звёздам
local function numbersByIndex(source)
	local list = nil
	for key, value in pairs(source) do
		if type(key) == "number" and type(value) == "number" then
			list = list or {}
			list[key] = value
		end
	end
	return list
end

local function scanForCaptureConfig(source, depth)
	if type(source) ~= "table" or depth > CAPTURE_SCAN_DEPTH then
		return nil
	end

	for key, value in pairs(source) do
		if looksLikeCaptureKey(key) then
			if type(value) == "number" then
				return { flat = value, from = tostring(key) }
			end
			if type(value) == "table" then
				local list = numbersByIndex(value)
				if list then
					return { byStar = list, from = tostring(key) }
				end
			end
		end
	end

	for key, value in pairs(source) do
		if type(value) == "table" then
			local found = scanForCaptureConfig(value, depth + 1)
			if found then
				found.from = tostring(key) .. "." .. found.from
				return found
			end
		end
	end

	return nil
end

-- Ищем один раз: константы за игру не меняются
local captureConfig = nil
local captureConfigSearched = false

local function getCaptureConfig()
	-- НОВОЕ: в Jail break констант с ArrestReward/CaptureReward нет,
	-- цена за поимку считается от награды
	if not features.captureConfig then
		return nil
	end

	if not captureConfigSearched then
		captureConfigSearched = true
		captureConfig = scanForCaptureConfig(CriminalConstants, 0)
		if DEBUG_MODULES then
			if captureConfig then
				print(
					"[BountyTracker] выплата за арест найдена:",
					captureConfig.from
				)
			else
				print(
					"[BountyTracker] выплаты за арест в константах нет,",
					"цена считается от награды"
				)
			end
		end
	end
	return captureConfig
end

local function getModuleCapture(player)
	local config = getCaptureConfig()
	if not config then
		return nil
	end
	if config.flat and config.flat > 0 then
		return math.floor(config.flat)
	end
	if config.byStar then
		local stars = getModuleStars(player)
		if stars then
			local value = config.byStar[stars]
			if type(value) == "number" and value > 0 then
				return math.floor(value)
			end
		end
	end
	return nil
end

-- Печатает, что удалось подключить и что читается по каждому игроку
-- (включается флагом DEBUG_MODULES)
local function dumpTable(label, value)
	if type(value) ~= "table" then
		print("[BountyTracker]", label, "->", type(value))
		return
	end
	print("[BountyTracker] " .. label .. ":")
	for key, item in pairs(value) do
		local shown
		if type(item) == "table" then
			shown = "<table>"
		else
			shown = tostring(item)
		end
		print("   ", tostring(key), "=", shown)
	end
end

local function dumpGameModules()
	print("[BountyTracker] --- дамп модулей игры ---")
	dumpTable("CriminalUtil", CriminalUtil)
	dumpTable("CriminalConstants", CriminalConstants)
	if type(CriminalConstants) == "table" then
		dumpTable(
			"CriminalConstants.PlayerAttributes",
			CriminalConstants.PlayerAttributes
		)
	end
	dumpTable("JobsUtil", JobsUtil)
	if type(JobsConstants) == "table" then
		dumpTable("JobsConstants.JobIds", JobsConstants.JobIds)
	end
	print("[BountyTracker] наличные:", tostring(CASH_CURRENCY_ID))
	getCaptureConfig()

	for _, player in ipairs(Players:GetPlayers()) do
		print(
			"[BountyTracker]",
			player.Name,
			"| розыск:",
			tostring(isPlayerWanted(player)),
			"| звёзды:",
			tostring(getModuleStars(player)),
			"| преступления:",
			tostring(getModuleCrimes(player)),
			"| награда:",
			tostring(getModuleBounty(player)),
			"| поимка:",
			tostring(getModuleCapture(player))
		)
		local state = getWantedState(player)
		if type(state) == "table" then
			dumpTable("WantedState." .. player.Name, state)
		end
	end
	print("[BountyTracker] --- конец дампа ---")
end

getBountyValue = function(player)
	-- НОВОЕ: точное значение из модулей игры
	local fromModule = getModuleBounty(player)
	if fromModule then
		return fromModule
	end

	-- Запасной вариант: поиск Value-объекта по имени.
	-- avoid: иначе поиск награды может схватить «Награду за поимку»
	-- MIN_BOUNTY: значение меньше минимального в игре — значит объект не тот
	return getStat(
		player,
		"Bounty",
		BOUNTY_PATTERNS,
		CAPTURE_PATTERNS,
		MIN_BOUNTY
	)
end

local function getRobberyCount(player)
	-- НОВОЕ: счётчик преступлений из модуля вместо поиска по именам
	local fromModule = getModuleCrimes(player)
	if fromModule then
		return fromModule
	end
	return getStat(player, "Robberies", ROBBERY_PATTERNS)
end

getCaptureValue = function(player, bounty)
	-- НОВОЕ: выплата за арест из констант игры, если она там прописана
	local fromModule = getModuleCapture(player)
	if fromModule then
		return fromModule
	end

	local value = getStat(player, "Capture", CAPTURE_PATTERNS)
	if value > 0 then
		return value
	end
	if CAPTURE_PERCENT > 0 and bounty > 0 then
		return math.floor(bounty * CAPTURE_PERCENT)
	end
	return 0
end

--==================================================
-- DROP
--==================================================
-- Дроп может быть и моделью, и одиночной деталью
local function getDropPart(instance)
	if instance:IsA("BasePart") then
		return instance
	end
	if instance:IsA("Model") then
		return instance.PrimaryPart
			or instance:FindFirstChildWhichIsA("BasePart")
	end
	return nil
end

local function findDrop()
	-- пока найденный дроп жив, второй раз не ищем
	if dropCache.instance and dropCache.instance.Parent then
		local part = getDropPart(dropCache.instance)
		if part then
			return dropCache.instance, part
		end
	end

	if dropCache.instance then
		dropCache.instance = nil
	end

	if os.clock() < dropCache.nextScan then
		return nil, nil
	end

	local queue = { { Workspace, 0 } }
	local index = 1
	while index <= #queue do
		local container = queue[index][1]
		local depth = queue[index][2]
		index = index + 1
		for _, child in ipairs(container:GetChildren()) do
			-- персонажей игроков не трогаем
			if not Players:GetPlayerFromCharacter(child) then
				-- точки сдачи мешков (SackDropOffs и подобные) пропускаем
				-- целиком: ни сами дропом не считаются, ни то, что внутри
				local excluded =
					nameMatchesAny(child.Name, DROP_EXCLUDE)
				if not excluded
					and nameMatchesAny(child.Name, DROP_PATTERNS) then
					local part = getDropPart(child)
					if part then
						dropCache.instance = child
						return child, part
					end
				end
				-- внутрь деталей (и Terrain) лезть незачем
				if not excluded
					and depth < DROP_SEARCH_DEPTH
					and not child:IsA("BasePart") then
					table.insert(queue, { child, depth + 1 })
				end
			end
		end
	end

	dropCache.nextScan = os.clock() + RESCAN_INTERVAL
	return nil, nil
end

local function createDropVisuals(instance, part, distance)
	-- BOX + TAG
	if espEnabled then
		local box = instance:FindFirstChild("DropESP")
		if not box then
			box = Instance.new("BoxHandleAdornment")
			box.Name = "DropESP"
			box.AlwaysOnTop = true
			box.ZIndex = 6
			box.Color3 = DROP_COLOR
			box.Transparency = 0.35
			box.Parent = instance
		end
		box.Adornee = part
		box.Size = part.Size + Vector3.new(0.6, 0.6, 0.6)

		local tag = instance:FindFirstChild("DropTag")
		if not tag then
			tag = Instance.new("BillboardGui")
			tag.Name = "DropTag"
			tag.Size = UDim2.new(0, 200, 0, 50)
			tag.StudsOffset = Vector3.new(0, 3, 0)
			tag.AlwaysOnTop = true
			tag.Parent = instance

			local newLabel = Instance.new("TextLabel")
			newLabel.Name = "Text"
			newLabel.Size = UDim2.new(1, 0, 1, 0)
			newLabel.BackgroundTransparency = 1
			newLabel.TextColor3 = DROP_COLOR
			newLabel.Font = Enum.Font.SourceSansBold
			newLabel.TextSize = 18
			newLabel.TextStrokeTransparency = 0
			newLabel.TextStrokeColor3 = Color3.fromRGB(0, 0, 0)
			newLabel.Parent = tag
		end
		tag.Adornee = part

		local label = tag:FindFirstChild("Text")
		if label then
			if distance < MAX_DISTANCE then
				label.Text = "DROP ["
					.. tostring(math.floor(distance))
					.. "m]"
			else
				label.Text = "DROP"
			end
		end
	else
		local box = instance:FindFirstChild("DropESP")
		if box then
			box:Destroy()
		end

		local tag = instance:FindFirstChild("DropTag")
		if tag then
			tag:Destroy()
		end
	end

	-- LINE
	if linesEnabled then
		local myCharacter = LocalPlayer.Character
		local myRoot =
			myCharacter
			and myCharacter:FindFirstChild("HumanoidRootPart")
		if myRoot then
			-- имя с ANCHOR_PREFIX, чтобы общая чистка якорей его подхватила
			local myAttachment =
				myRoot:FindFirstChild(ANCHOR_PREFIX .. "DROP")
			if not myAttachment then
				myAttachment = Instance.new("Attachment")
				myAttachment.Name = ANCHOR_PREFIX .. "DROP"
				myAttachment.Parent = myRoot
			end

			local targetAttachment = part:FindFirstChild("DropTarget")
			if not targetAttachment then
				targetAttachment = Instance.new("Attachment")
				targetAttachment.Name = "DropTarget"
				targetAttachment.Parent = part
			end

			local beam = instance:FindFirstChild("DropLine")
			if not beam then
				beam = Instance.new("Beam")
				beam.Name = "DropLine"
				beam.Width0 = 0.18
				beam.Width1 = 0.18
				beam.Color = ColorSequence.new(DROP_COLOR)
				beam.FaceCamera = true
				beam.ZOffset = 1
				beam.Parent = instance
			end
			beam.Attachment0 = myAttachment
			beam.Attachment1 = targetAttachment
		end
	else
		local beam = instance:FindFirstChild("DropLine")
		if beam then
			beam:Destroy()
		end

		local targetAttachment = instance:FindFirstChild("DropTarget", true)
		if targetAttachment then
			targetAttachment:Destroy()
		end
	end
end

--==================================================
-- ФИЛЬТР СПИСКА
--==================================================
-- НОВОЕ: кого показывать, решает выбранный в панели режим.
-- Раньше это была жёстко зашитая isCriminal
matchesFilter = function(player)
	if player == LocalPlayer then
		return false
	end

	if teamFilter.mode == "all" then
		return true
	end

	if teamFilter.mode == "team" then
		-- сравнение по имени, а не по объекту: тиму могли пересоздать
		return player.Team ~= nil
			and player.Team.Name == teamFilter.teamName
	end

	-- "auto" — прежнее поведение: криминальная тима ИЛИ ненулевая награда.
	-- НОВОЕ: если модули игры доступны, спрашиваем сначала их —
	-- ровно так же, как это делает сама игра
	local jobIsCriminal = hasCriminalJob(player)
	if jobIsCriminal ~= nil then
		if jobIsCriminal then
			return true
		end
		-- работа уже не криминал, но розыск мог остаться
		if isPlayerWanted(player) == true then
			return true
		end
	end

	if player.Team
		and nameMatchesAny(player.Team.Name, CRIMINAL_TEAM_PATTERNS) then
		return true
	end

	return getBountyValue(player) > 0
end

--==================================================
-- PLAYER LIST
--==================================================
local function clearList()
	for _, child in ipairs(ScrollingFrame:GetChildren()) do
		if child:IsA("Frame") then
			child:Destroy()
		end
	end
end

-- НОВОЕ: секунды розыска в вид «м:сс». nil означает «данных нет»
local function formatWantedTime(seconds)
	if not seconds then
		return "—"
	end
	if seconds <= 0 then
		return "0:00"
	end
	return string.format("%d:%02d", math.floor(seconds / 60), seconds % 60)
end

local function createPlayerItem(data, layoutOrder)
	local item = Instance.new("Frame")
	item.Name = "Player_" .. data.Player.UserId
	item.Size = UDim2.new(1, -6, 0, 44)
	item.BackgroundColor3 = COLOR_ROW
	item.BorderSizePixel = 0
	item.LayoutOrder = layoutOrder
	item.Parent = ScrollingFrame

	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, 4)
	corner.Parent = item

	-- НОВОЕ: цвет тимы игрока — им красится ник и полоска слева
	local teamColor = getPlayerColor(data.Player)

	-- НОВОЕ: полоска у левого края карточки цветом тимы. Видно, за кого
	-- игрок, даже когда ник сидит на жёлтом фоне дорогой поимки
	local accentBar = Instance.new("Frame")
	accentBar.Name = "AccentBar"
	accentBar.Size = UDim2.new(0, 2, 1, -8)
	accentBar.Position = UDim2.new(0, 0, 0, 4)
	accentBar.BackgroundColor3 = teamColor
	accentBar.BorderSizePixel = 0
	accentBar.Parent = item

	local distanceText
	if data.Distance < MAX_DISTANCE then
		distanceText =
			string.format("%.0f", data.Distance) .. "m"
	else
		distanceText = "?m"
	end

	--=== СТРОКА 1: ник + ограбления ===
	-- НОВОЕ: цена за поимку от BIG_CAPTURE_VALUE — фон за ником жёлтый,
	-- как у строки дропа. Объявляем до создания ника: значение нужно
	-- и при создании, и внутри обработчика клика
	local bigCapture = data.Capture >= BIG_CAPTURE_VALUE
	-- НОВОЕ: обычный цвет ника — цвет его тимы. На жёлтом фоне дорогой
	-- поимки он бы не читался, поэтому там текст остаётся тёмным
	local plainNameColor = teamColor
	if bigCapture then
		plainNameColor = DROP_TEXT_COLOR
	end

	-- TextButton вместо TextLabel: по нику можно кликнуть,
	-- чтобы выделить линию до этого игрока
	local nameLabel = Instance.new("TextButton")
	nameLabel.Size = UDim2.new(0.55, 0, 0, 20)
	nameLabel.Position = UDim2.new(0, 5, 0, 2)
	nameLabel.BackgroundTransparency = 1
	nameLabel.AutoButtonColor = false
	nameLabel.Text = data.Player.DisplayName
	if selectedUserId == data.Player.UserId then
		nameLabel.TextColor3 = SELECT_COLOR
	else
		nameLabel.TextColor3 = plainNameColor
	end
	nameLabel.TextXAlignment = Enum.TextXAlignment.Left
	nameLabel.Font = Enum.Font.SourceSansBold
	nameLabel.TextSize = 14
	nameLabel.TextTruncate = Enum.TextTruncate.AtEnd
	nameLabel.Parent = item

	-- НОВОЕ: сама подсветка ника
	if bigCapture then
		nameLabel.BackgroundTransparency = 0
		nameLabel.BackgroundColor3 = DROP_ROW_COLOR

		local nameCorner = Instance.new("UICorner")
		nameCorner.CornerRadius = UDim.new(0, 3)
		nameCorner.Parent = nameLabel

		-- отступ слева, чтобы текст не лип к краю плашки
		local namePadding = Instance.new("UIPadding")
		namePadding.PaddingLeft = UDim.new(0, 4)
		namePadding.Parent = nameLabel
	end

	-- Клик по нику: выделяем линию, повторный клик снимает выделение
	nameLabel.MouseButton1Click:Connect(function()
		local previousUserId = selectedUserId
		if selectedUserId == data.Player.UserId then
			selectedUserId = nil
			nameLabel.TextColor3 = plainNameColor
		else
			selectedUserId = data.Player.UserId
			nameLabel.TextColor3 = SELECT_COLOR
		end

		-- Перекрашиваем сразу, не дожидаясь следующего апдейта
		createLine(data.Player)

		if previousUserId
			and previousUserId ~= data.Player.UserId then
			local previousPlayer =
				Players:GetPlayerByUserId(previousUserId)
			if previousPlayer then
				createLine(previousPlayer)
			end
		end
	end)

	local robberyLabel = Instance.new("TextLabel")
	-- НОВОЕ: когда таймер розыска показывается, строка ограблений короче
	-- на его ширину; в Jail break таймера нет и место свободно
	local robberyWidth = 0
	if features.wantedTimer then
		robberyWidth = -46
	end
	robberyLabel.Size = UDim2.new(0.4, robberyWidth, 0, 20)
	robberyLabel.Position = UDim2.new(0.58, -5, 0, 2)
	robberyLabel.BackgroundTransparency = 1
	robberyLabel.Text =
		tostring(data.Robberies)
		.. " огр. ("
		.. distanceText
		.. ")"
	robberyLabel.TextColor3 = COLOR_TEXT_DIM
	robberyLabel.TextXAlignment = Enum.TextXAlignment.Right
	robberyLabel.Font = Enum.Font.SourceSansBold
	robberyLabel.TextSize = 12
	robberyLabel.TextTruncate = Enum.TextTruncate.AtEnd
	robberyLabel.Parent = item

	-- НОВОЕ: таймер показывается только там, где розыск вообще есть
	if features.wantedTimer then
		-- НОВОЕ: таймер розыска в правом верхнем углу карточки
		local timerLabel = Instance.new("TextLabel")
		timerLabel.Size = UDim2.new(0, 42, 0, 20)
		timerLabel.Position = UDim2.new(0.98, -47, 0, 2)
		timerLabel.BackgroundTransparency = 1
		timerLabel.Text = formatWantedTime(data.WantedTime)
		if data.WantedTime and data.WantedTime > 0 then
			if data.WantedTime <= WANTED_SOON then
				-- вот-вот истечёт: гнаться уже почти бессмысленно
				timerLabel.TextColor3 = COLOR_ACCENT
			else
				timerLabel.TextColor3 = COLOR_TEXT
			end
		else
			timerLabel.TextColor3 = Color3.fromRGB(95, 86, 88)
		end
		timerLabel.TextXAlignment = Enum.TextXAlignment.Right
		timerLabel.Font = Enum.Font.SourceSansBold
		timerLabel.TextSize = 12
		timerLabel.TextTruncate = Enum.TextTruncate.AtEnd
		timerLabel.Parent = item
	end

	--=== СТРОКА 2: награда + цена за поимку ===
	local bountyLabel = Instance.new("TextLabel")
	bountyLabel.Size = UDim2.new(0.4, 0, 0, 18)
	bountyLabel.Position = UDim2.new(0, 5, 0, 22)
	bountyLabel.BackgroundTransparency = 1
	if data.Bounty > 0 then
		bountyLabel.Text = "$" .. tostring(data.Bounty)
		bountyLabel.TextColor3 = COLOR_ACCENT
	elseif teamFilter.mode == "auto" then
		-- в авторежиме игрок попал в список именно как преступник
		bountyLabel.Text = "WANTED"
		bountyLabel.TextColor3 = COLOR_ACCENT
	else
		-- НОВОЕ: при выборе тимы вручную нулевая награда — норма,
		-- «WANTED» здесь врал бы
		bountyLabel.Text = "нет награды"
		bountyLabel.TextColor3 = COLOR_TEXT_DIM
	end
	bountyLabel.TextXAlignment = Enum.TextXAlignment.Left
	bountyLabel.Font = Enum.Font.SourceSansBold
	bountyLabel.TextSize = 12
	bountyLabel.TextTruncate = Enum.TextTruncate.AtEnd
	bountyLabel.Parent = item

	local captureLabel = Instance.new("TextLabel")
	captureLabel.Size = UDim2.new(0.55, 0, 0, 18)
	captureLabel.Position = UDim2.new(0.44, -5, 0, 22)
	captureLabel.BackgroundTransparency = 1
	if data.Capture > 0 then
		captureLabel.Text =
			"за поимку +$" .. tostring(data.Capture)
	else
		captureLabel.Text = "за поимку —"
	end
	captureLabel.TextColor3 = COLOR_MONEY
	captureLabel.TextXAlignment = Enum.TextXAlignment.Right
	captureLabel.Font = Enum.Font.SourceSansBold
	captureLabel.TextSize = 12
	captureLabel.TextTruncate = Enum.TextTruncate.AtEnd
	captureLabel.Parent = item
end

-- LayoutOrder = 0, поэтому строка дропа всегда выше игроков (те с 1)
local function createDropItem(instance, distance)
	local item = Instance.new("Frame")
	item.Name = "DropRow"
	item.Size = UDim2.new(1, -6, 0, 44)
	item.BackgroundColor3 = DROP_ROW_COLOR
	item.BorderSizePixel = 0
	item.LayoutOrder = 0
	item.Parent = ScrollingFrame

	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, 4)
	corner.Parent = item

	local distanceText
	if distance < MAX_DISTANCE then
		distanceText =
			string.format("%.0f", distance) .. "m"
	else
		distanceText = "?m"
	end

	--=== СТРОКА 1: DROP + дистанция ===
	local titleLabel = Instance.new("TextLabel")
	titleLabel.Size = UDim2.new(0.55, 0, 0, 20)
	titleLabel.Position = UDim2.new(0, 5, 0, 2)
	titleLabel.BackgroundTransparency = 1
	titleLabel.Text = "DROP"
	titleLabel.TextColor3 = DROP_TEXT_COLOR
	titleLabel.TextXAlignment = Enum.TextXAlignment.Left
	titleLabel.Font = Enum.Font.SourceSansBold
	titleLabel.TextSize = 16
	titleLabel.Parent = item

	local distanceLabel = Instance.new("TextLabel")
	distanceLabel.Size = UDim2.new(0.4, 0, 0, 20)
	distanceLabel.Position = UDim2.new(0.58, -5, 0, 2)
	distanceLabel.BackgroundTransparency = 1
	distanceLabel.Text = "(" .. distanceText .. ")"
	distanceLabel.TextColor3 = DROP_TEXT_COLOR
	distanceLabel.TextXAlignment = Enum.TextXAlignment.Right
	distanceLabel.Font = Enum.Font.SourceSansBold
	distanceLabel.TextSize = 14
	distanceLabel.Parent = item

	--=== СТРОКА 2: что именно нашлось ===
	local sourceLabel = Instance.new("TextLabel")
	sourceLabel.Size = UDim2.new(1, -10, 0, 18)
	sourceLabel.Position = UDim2.new(0, 5, 0, 22)
	sourceLabel.BackgroundTransparency = 1
	sourceLabel.Text = instance.Name
	sourceLabel.TextColor3 = Color3.fromRGB(90, 70, 0)
	sourceLabel.TextXAlignment = Enum.TextXAlignment.Left
	sourceLabel.Font = Enum.Font.SourceSans
	sourceLabel.TextSize = 12
	sourceLabel.TextTruncate = Enum.TextTruncate.AtEnd
	sourceLabel.Parent = item
end

--==================================================
-- UPDATE
--==================================================
local updating = false

-- без local: переменная объявлена в начале файла,
-- чтобы её видели обработчики выпадающего списка тим
function updateList()
	if updating then
		return
	end
	updating = true

	local success, errorMessage = pcall(function()
		clearList()

		local myCharacter = LocalPlayer.Character
		local myRoot =
			myCharacter
			and myCharacter:FindFirstChild("HumanoidRootPart")

		local validPlayers = {}
		for _, player in ipairs(Players:GetPlayers()) do
			if matchesFilter(player) then
				local distance = MAX_DISTANCE + 1
				if player.Character and myRoot then
					local targetRoot =
						player.Character:FindFirstChild(
							"HumanoidRootPart"
						)
					if targetRoot then
						distance =
							(myRoot.Position
								- targetRoot.Position).Magnitude
					end
				end

				local bounty = getBountyValue(player)
				table.insert(validPlayers, {
					Player = player,
					Distance = distance,
					Bounty = bounty,
					Robberies = getRobberyCount(player),
					Capture = getCaptureValue(player, bounty),
					-- НОВОЕ: остаток розыска в секундах, nil если данных нет
					WantedTime = getWantedRemaining(player)
				})
			end
		end

		-- НОВОЕ: сортировка по цене за поимку — дороже сверху.
		-- При равной цене выше тот, у кого больше награда, дальше — кто ближе
		table.sort(validPlayers, function(a, b)
			if a.Capture == b.Capture then
				if a.Bounty == b.Bounty then
					return a.Distance < b.Distance
				end
				return a.Bounty > b.Bounty
			end
			return a.Capture > b.Capture
		end)

		local activeUserIds = {}
		local rowCount = #validPlayers
		-- НОВОЕ: в нижнюю строку идут только игроки, без строки DROP
		CountLabel.Text = "в списке: " .. #validPlayers

		-- DROP: всегда первая строка списка
		local dropInstance, dropPart = findDrop()
		if dropInstance and dropPart then
			local dropDistance = MAX_DISTANCE + 1
			if myRoot then
				dropDistance =
					(myRoot.Position - dropPart.Position).Magnitude
			end
			createDropVisuals(dropInstance, dropPart, dropDistance)
			createDropItem(dropInstance, dropDistance)
			rowCount = rowCount + 1
		end

		for index, data in ipairs(validPlayers) do
			activeUserIds[data.Player.UserId] = true
			if data.Player.Character then
				createESP(
					data.Player,
					data.Distance
				)
				createLine(data.Player)
			end
			createPlayerItem(
				data,
				index
			)
		end

		-- ФИКС: с игрока, который выпал из списка (сел, сдался, награда
		-- обнулилась, сменили фильтр тимы), метки и линия раньше не снимались
		for _, player in ipairs(Players:GetPlayers()) do
			if player ~= LocalPlayer
				and not activeUserIds[player.UserId] then
				if player.Character then
					removeVisuals(player.Character)
				end
				removeAnchor(player.UserId)
			end
		end

		-- ФИКС: высота считалась как n * 34, лишние 4 пикселя от последнего
		-- отступа давали ложную прокрутку. Карточка 44px + 4 отступ,
		-- строка дропа тоже учитывается
		ScrollingFrame.CanvasSize =
			UDim2.new(
				0,
				0,
				0,
				math.max(0, rowCount * 48 - 4)
			)
	end)

	if not success then
		warn(
			"[BountyTracker] Update error:",
			errorMessage
		)
	end

	updating = false
end

--==================================================
-- BUTTONS
--==================================================
EspButton.MouseButton1Click:Connect(function()
	espEnabled = not espEnabled
	-- НОВОЕ: цвет переезжает плавно, а не прыгает
	if espEnabled then
		setEspColor(COLOR_ON)
	else
		setEspColor(COLOR_OFF)
	end

	-- ФИКС: раньше метки снимались только с тех, кто попал в список
	-- на этом апдейте, остальные оставались подсвеченными
	if not espEnabled then
		for _, player in ipairs(Players:GetPlayers()) do
			local character = player.Character
			if character then
				local box = character:FindFirstChild("BountyESP")
				if box then
					box:Destroy()
				end
				local tag = character:FindFirstChild("BountyNameTag")
				if tag then
					tag:Destroy()
				end
			end
		end
	end

	updateList()
end)

LineButton.MouseButton1Click:Connect(function()
	linesEnabled = not linesEnabled
	if linesEnabled then
		setLineColor(COLOR_ON)
	else
		setLineColor(COLOR_OFF)
	end

	-- Удаляем старые линии
	if not linesEnabled then
		for _, player in ipairs(Players:GetPlayers()) do
			local character = player.Character
			if character then
				local line =
					character:FindFirstChild(
						"BountyLine"
					)
				if line then
					line:Destroy()
				end
				-- ФИКС: Attachment лежит в HumanoidRootPart
				local attachment =
					character:FindFirstChild(
						"BountyTarget",
						true
					)
				if attachment then
					attachment:Destroy()
				end
			end
		end

		local myCharacter = LocalPlayer.Character
		if myCharacter then
			-- ФИКС: обход по GetDescendants, а не GetChildren
			for _, object in ipairs(myCharacter:GetDescendants()) do
				if object:IsA("Attachment")
					and object.Name:sub(1, #ANCHOR_PREFIX)
						== ANCHOR_PREFIX then
					object:Destroy()
				end
			end
		end
	end

	updateList()
end)

--==================================================
-- PLAYER EVENTS
--==================================================
-- ФИКС: у игроков, которые уже были в сервере на момент запуска скрипта,
-- CharacterAdded не подключался вообще
local function hookCharacter(player)
	player.CharacterAdded:Connect(function()
		task.wait(0.5)
		updateList()
	end)
end

for _, player in ipairs(Players:GetPlayers()) do
	if player ~= LocalPlayer then
		hookCharacter(player)
	end
end

Players.PlayerRemoving:Connect(function(player)
	if player.Character then
		removeVisuals(player.Character)
	end

	-- ФИКС: якорь ушедшего игрока висел на нашем персонаже до респавна
	removeAnchor(player.UserId)

	-- чтобы кэш найденных значений не держал ссылки на мёртвые объекты
	statCache[player.UserId] = nil

	-- Игрок ушёл — выделение больше ни на что не указывает.
	-- Без сброса зелёная линия неожиданно вернётся, если он зайдёт снова
	if selectedUserId == player.UserId then
		selectedUserId = nil
	end

	task.defer(updateList)
end)

Players.PlayerAdded:Connect(function(player)
	hookCharacter(player)
	task.defer(updateList)
end)

--==================================================
-- LOCAL PLAYER RESPAWN
--==================================================
LocalPlayer.CharacterAdded:Connect(function()
	task.wait(1)
	removeAllVisuals()
	updateList()
end)

--==================================================
-- АВТООБНОВЛЕНИЕ
--==================================================
task.spawn(function()
	while ScreenGui.Parent do
		task.wait(UPDATE_INTERVAL)
		if ScreenGui.Parent then
			updateList()
		end
	end
end)

--==================================================
-- DRAG GUI
--==================================================
local dragging = false
local dragInput
local dragStart
local startPosition

local function updateDrag(input)
	if not dragging then
		return
	end
	local delta =
		input.Position - dragStart
	MainFrame.Position =
		UDim2.new(
			startPosition.X.Scale,
			startPosition.X.Offset + delta.X,
			startPosition.Y.Scale,
			startPosition.Y.Offset + delta.Y
		)
end

MainFrame.InputBegan:Connect(function(input)
	if input.UserInputType
			== Enum.UserInputType.MouseButton1
		or input.UserInputType
			== Enum.UserInputType.Touch then
		dragging = true
		dragStart = input.Position
		startPosition = MainFrame.Position

		input.Changed:Connect(function()
			if input.UserInputState
				== Enum.UserInputState.End then
				dragging = false
				-- ФИКС: без сброса dragInput окно продолжало «липнуть»
				-- к курсору после следующего касания
				dragInput = nil
			end
		end)
	end
end)

MainFrame.InputChanged:Connect(function(input)
	if input.UserInputType
			== Enum.UserInputType.MouseMovement
		or input.UserInputType
			== Enum.UserInputType.Touch then
		dragInput = input
	end
end)

UserInputService.InputChanged:Connect(function(input)
	if input == dragInput and dragging then
		updateDrag(input)
	end
end)

--==================================================
-- ЗАПРОС РАБОТЫ ПО КНОПКЕ ШЕР (НОВОЕ)
--==================================================
local JOB_REMOTE_NAME = "RequestStartJobSession"
local JOB_ARGS = { "Security", "jobPad" }

local function requestJob()
	-- FindFirstChild, а не WaitForChild: ждать внутри обработчика клика
	-- значило бы подвесить кнопку, если папки нет вовсе
	local remotes = ReplicatedStorage:FindFirstChild("Remotes")
	if not remotes then
		return false, "нет папки Remotes"
	end

	local remote = remotes:FindFirstChild(JOB_REMOTE_NAME)
	if not remote then
		return false, "нет " .. JOB_REMOTE_NAME
	end

	local ok, err = pcall(function()
		remote:FireServer(table.unpack(JOB_ARGS))
	end)
	if not ok then
		return false, tostring(err)
	end

	return true, nil
end

-- НОВОЕ: в Jail break кнопки нет, вешать обработчик не на что
if JobButton then
	JobButton.MouseButton1Click:Connect(function()
		local ok, problem = requestJob()
		if ok then
			-- «ушло» значит именно ушло: ответа сервера тут не видно
			JobButton.Text = "ушло"
		else
			JobButton.Text = "нет"
			warn("[BountyTracker] запрос работы не прошёл:", problem)
		end

		task.delay(1, function()
			JobButton.Text = SHER_TEXT
		end)
	end)
end

--==================================================
-- АВТОЗАПУСК ПОСЛЕ ТЕЛЕПОРТА (НОВОЕ)
--==================================================
-- Исполнители умеют поставить код в очередь на следующий сервер: после
-- телепорта он запускается сам. Функция называется у всех по-разному,
-- поэтому пробуем все известные имена
local function queueAfterTeleport()
	if AUTORUN_URL == "" then
		warn(
			"[BountyTracker] автозапуск выключен:",
			"впиши ссылку на скрипт в AUTORUN_URL"
		)
		return false
	end

	-- в очередь уходит загрузчик, а не сам скрипт: своего исходного текста
	-- у уже запущенного кода нет
	local source =
		'loadstring(game:HttpGet("' .. AUTORUN_URL .. '", true))()'

	local env = {}
	if type(getgenv) == "function" then
		local ok, result = pcall(getgenv)
		if ok and type(result) == "table" then
			env = result
		end
	end

	local syn = env.syn
	local fluxus = env.fluxus

	local candidates = {
		{
			name = "queue_on_teleport",
			fn = env.queue_on_teleport or queue_on_teleport,
		},
		{
			name = "queueonteleport",
			fn = env.queueonteleport or queueonteleport,
		},
		{
			name = "syn.queue_on_teleport",
			fn = type(syn) == "table" and syn.queue_on_teleport or nil,
		},
		{
			name = "fluxus.queue_on_teleport",
			fn = type(fluxus) == "table" and fluxus.queue_on_teleport or nil,
		},
	}

	for _, candidate in ipairs(candidates) do
		if type(candidate.fn) == "function" then
			local ok, err = pcall(candidate.fn, source)
			if ok then
				print(
					"[BountyTracker] автозапуск поставлен через",
					candidate.name
				)
				return true
			end
			warn(
				"[BountyTracker]",
				candidate.name,
				"не сработал:",
				err
			)
		end
	end

	warn(
		"[BountyTracker] исполнитель не умеет queue_on_teleport,",
		"автозапуска после смены сервера не будет"
	)
	return false
end

--==================================================
-- SUSPENSION EDITOR
-- Отдельное окно в стиле Агузни
--==================================================


if pickedMode == MODE_DRIVE_EMPIRE then
local SUSPENSION_GUI_NAME = "AguznyaSuspensionEditor"

local oldSuspensionGui = PlayerGui:FindFirstChild(SUSPENSION_GUI_NAME)
if oldSuspensionGui then
	oldSuspensionGui:Destroy()
end

local SuspensionGui = Instance.new("ScreenGui")
SuspensionGui.Name = SUSPENSION_GUI_NAME
SuspensionGui.ResetOnSpawn = false
SuspensionGui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
SuspensionGui.Parent = PlayerGui

local SuspensionFrame = Instance.new("Frame")
SuspensionFrame.Name = "SuspensionFrame"
SuspensionFrame.Size = UDim2.new(0, 300, 0, 390)
SuspensionFrame.Position = UDim2.new(0.35, 0, 0.3, 0)
SuspensionFrame.BackgroundColor3 = COLOR_BG
SuspensionFrame.BorderSizePixel = 0
SuspensionFrame.Active = true
SuspensionFrame.Parent = SuspensionGui

local SuspensionStroke = Instance.new("UIStroke")
SuspensionStroke.Color = COLOR_EDGE
SuspensionStroke.Thickness = 1
SuspensionStroke.Parent = SuspensionFrame

local SuspensionCorner = Instance.new("UICorner")
SuspensionCorner.CornerRadius = UDim.new(0, 8)
SuspensionCorner.Parent = SuspensionFrame

local SuspensionTitle = Instance.new("TextLabel")
SuspensionTitle.Size = UDim2.new(1, -45, 0, 30)
SuspensionTitle.Position = UDim2.new(0, 5, 0, 0)
SuspensionTitle.BackgroundColor3 = COLOR_HEADER
SuspensionTitle.Text = " ПОДВЕСКА"
SuspensionTitle.TextColor3 = COLOR_TEXT
SuspensionTitle.TextXAlignment = Enum.TextXAlignment.Left
SuspensionTitle.Font = Enum.Font.SourceSansBold
SuspensionTitle.TextSize = 16
SuspensionTitle.BorderSizePixel = 0
SuspensionTitle.Parent = SuspensionFrame

local SuspensionTitleCorner = Instance.new("UICorner")
SuspensionTitleCorner.CornerRadius = UDim.new(0, 8)
SuspensionTitleCorner.Parent = SuspensionTitle

local SuspensionUnderline = Instance.new("Frame")
SuspensionUnderline.Size = UDim2.new(1, -10, 0, 1)
SuspensionUnderline.Position = UDim2.new(0, 5, 0, 31)
SuspensionUnderline.BackgroundColor3 = COLOR_ACCENT
SuspensionUnderline.BackgroundTransparency = 0.35
SuspensionUnderline.BorderSizePixel = 0
SuspensionUnderline.Parent = SuspensionFrame

local SuspensionClose = Instance.new("TextButton")
SuspensionClose.Size = UDim2.new(0, 28, 0, 22)
SuspensionClose.Position = UDim2.new(1, -33, 0, 4)
SuspensionClose.BackgroundColor3 = COLOR_OFF
SuspensionClose.Text = "X"
SuspensionClose.TextColor3 = COLOR_TEXT
SuspensionClose.Font = Enum.Font.SourceSansBold
SuspensionClose.TextSize = 12
SuspensionClose.BorderSizePixel = 0
SuspensionClose.Parent = SuspensionFrame

local SuspensionCloseCorner = Instance.new("UICorner")
SuspensionCloseCorner.CornerRadius = UDim.new(0, 4)
SuspensionCloseCorner.Parent = SuspensionClose
addHover(SuspensionClose, 0.08)

SuspensionClose.MouseButton1Click:Connect(function()
	SuspensionFrame.Visible = false
end)

-- Перетаскивание окна за заголовок
local suspensionDragging = false
local suspensionDragStart
local suspensionStartPosition

SuspensionTitle.InputBegan:Connect(function(input)
	if input.UserInputType == Enum.UserInputType.MouseButton1 then
		suspensionDragging = true
		suspensionDragStart = input.Position
		suspensionStartPosition = SuspensionFrame.Position
	end
end)

SuspensionTitle.InputEnded:Connect(function(input)
	if input.UserInputType == Enum.UserInputType.MouseButton1 then
		suspensionDragging = false
	end
end)

UserInputService.InputChanged:Connect(function(input)
	if suspensionDragging and input.UserInputType == Enum.UserInputType.MouseMovement then
		local delta = input.Position - suspensionDragStart
		SuspensionFrame.Position = UDim2.new(
			suspensionStartPosition.X.Scale,
			suspensionStartPosition.X.Offset + delta.X,
			suspensionStartPosition.Y.Scale,
			suspensionStartPosition.Y.Offset + delta.Y
		)
	end
end)

-- Кнопка повторного открытия: RightShift
UserInputService.InputBegan:Connect(function(input, gameProcessed)
	if gameProcessed then return end
	if input.KeyCode == Enum.KeyCode.RightShift then
		SuspensionFrame.Visible = not SuspensionFrame.Visible
	end
end)

local suspensionMode = "All"
local suspensionButtons = {}
local suspensionSliders = {}

local suspensionRanges = {
	Damping = {Min = 0, Max = 5000, Decimals = 0},
	FreeLength = {Min = 0, Max = 10, Decimals = 2},
	MaxForce = {Min = 0, Max = 100000, Decimals = 0},
	Stiffness = {Min = 0, Max = 100000, Decimals = 0},
}

local function getSuspensionSprings()
	local vehicles = Workspace:FindFirstChild("Vehicles")
	if not vehicles then return nil end

	local vehicle = vehicles:FindFirstChild(LocalPlayer.Name)
	if not vehicle then return nil end

	local constraints = vehicle:FindFirstChild("Constraints")
	if not constraints then return nil end

	return {
		FrontLeft = constraints:FindFirstChild("FLSpring"),
		FrontRight = constraints:FindFirstChild("FRSpring"),
		RearLeft = constraints:FindFirstChild("RLSpring"),
		RearRight = constraints:FindFirstChild("RRSpring"),
	}
end

local function getSelectedSuspensionSprings()
	local springs = getSuspensionSprings()
	if not springs then return {} end

	if suspensionMode == "Front" then
		return {springs.FrontLeft, springs.FrontRight}
	elseif suspensionMode == "Rear" then
		return {springs.RearLeft, springs.RearRight}
	end

	return {
		springs.FrontLeft,
		springs.FrontRight,
		springs.RearLeft,
		springs.RearRight,
	}
end

local function formatSuspensionNumber(value, decimals)
	if decimals == 0 then
		return tostring(math.floor(value + 0.5))
	end
	return string.format("%." .. decimals .. "f", value)
end

-- Выбор: ПЕРЕД / ЗАД / ПОЛНОСТЬЮ
local suspensionTabs = Instance.new("Frame")
suspensionTabs.Size = UDim2.new(1, -10, 0, 30)
suspensionTabs.Position = UDim2.new(0, 5, 0, 38)
suspensionTabs.BackgroundTransparency = 1
suspensionTabs.Parent = SuspensionFrame

local suspensionTabLayout = Instance.new("UIListLayout")
suspensionTabLayout.FillDirection = Enum.FillDirection.Horizontal
suspensionTabLayout.Padding = UDim.new(0, 4)
suspensionTabLayout.Parent = suspensionTabs

local function updateSuspensionTabs()
	for mode, button in pairs(suspensionButtons) do
		if mode == suspensionMode then
			button.BackgroundColor3 = COLOR_ACCENT
		else
			button.BackgroundColor3 = COLOR_FIELD
		end
	end
end

for _, modeData in ipairs({
	{Name = "Front", Text = "ПЕРЕД"},
	{Name = "Rear", Text = "ЗАД"},
	{Name = "All", Text = "4 КОЛЕСА"},
}) do
	local button = Instance.new("TextButton")
	button.Name = modeData.Name
	button.Size = UDim2.new(1 / 3, -3, 1, 0)
	button.BackgroundColor3 = COLOR_FIELD
	button.Text = modeData.Text
	button.TextColor3 = COLOR_TEXT
	button.Font = Enum.Font.SourceSansBold
	button.TextSize = 11
	button.BorderSizePixel = 0
	button.Parent = suspensionTabs

	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, 4)
	corner.Parent = button

	addHover(button, 0.06)
	suspensionButtons[modeData.Name] = button

	button.MouseButton1Click:Connect(function()
		suspensionMode = modeData.Name
		updateSuspensionTabs()
	end)
end

updateSuspensionTabs()

local function createSuspensionSlider(property, y)
	local range = suspensionRanges[property]

	local container = Instance.new("Frame")
	container.Name = property
	container.Size = UDim2.new(1, -20, 0, 62)
	container.Position = UDim2.new(0, 10, 0, y)
	container.BackgroundTransparency = 1
	container.Parent = SuspensionFrame

	local label = Instance.new("TextLabel")
	label.Size = UDim2.new(0.6, 0, 0, 18)
	label.BackgroundTransparency = 1
	label.Text = property
	label.TextColor3 = COLOR_TEXT
	label.Font = Enum.Font.SourceSansBold
	label.TextSize = 13
	label.TextXAlignment = Enum.TextXAlignment.Left
	label.Parent = container

	local valueLabel = Instance.new("TextLabel")
	valueLabel.Size = UDim2.new(0.4, 0, 0, 18)
	valueLabel.Position = UDim2.new(0.6, 0, 0, 0)
	valueLabel.BackgroundTransparency = 1
	valueLabel.TextColor3 = COLOR_MONEY
	valueLabel.Font = Enum.Font.SourceSansBold
	valueLabel.TextSize = 13
	valueLabel.TextXAlignment = Enum.TextXAlignment.Right
	valueLabel.Parent = container

	local bar = Instance.new("Frame")
	bar.Size = UDim2.new(1, 0, 0, 7)
	bar.Position = UDim2.new(0, 0, 0, 28)
	bar.BackgroundColor3 = COLOR_FIELD
	bar.BorderSizePixel = 0
	bar.Active = true
	bar.Parent = container

	local barCorner = Instance.new("UICorner")
	barCorner.CornerRadius = UDim.new(1, 0)
	barCorner.Parent = bar

	local fill = Instance.new("Frame")
	fill.Size = UDim2.new(0, 0, 1, 0)
	fill.BackgroundColor3 = COLOR_ACCENT
	fill.BorderSizePixel = 0
	fill.Parent = bar

	local fillCorner = Instance.new("UICorner")
	fillCorner.CornerRadius = UDim.new(1, 0)
	fillCorner.Parent = fill

	local knob = Instance.new("TextButton")
	knob.Size = UDim2.new(0, 16, 0, 16)
	knob.AnchorPoint = Vector2.new(0.5, 0.5)
	knob.Position = UDim2.new(0, 0, 0.5, 0)
	knob.BackgroundColor3 = COLOR_TEXT
	knob.Text = ""
	knob.AutoButtonColor = false
	knob.BorderSizePixel = 0
	knob.Parent = bar

	local knobCorner = Instance.new("UICorner")
	knobCorner.CornerRadius = UDim.new(1, 0)
	knobCorner.Parent = knob

	local currentValue = range.Min
	local dragging = false

	local function setValue(value)
		value = math.clamp(value, range.Min, range.Max)

		if range.Decimals == 0 then
			value = math.floor(value + 0.5)
		else
			local multiplier = 10 ^ range.Decimals
			value = math.floor(value * multiplier + 0.5) / multiplier
		end

		currentValue = value

		local percent = 0
		if range.Max ~= range.Min then
			percent = (value - range.Min) / (range.Max - range.Min)
		end

		fill.Size = UDim2.new(percent, 0, 1, 0)
		knob.Position = UDim2.new(percent, 0, 0.5, 0)
		valueLabel.Text = formatSuspensionNumber(value, range.Decimals)

		for _, spring in ipairs(getSelectedSuspensionSprings()) do
			if spring and spring:IsA("SpringConstraint") then
				pcall(function()
					spring[property] = value
				end)
			end
		end
	end

	local function updateFromMouse(mouseX)
		local width = bar.AbsoluteSize.X
		if width <= 0 then return end

		local percent = math.clamp(
			(mouseX - bar.AbsolutePosition.X) / width,
			0,
			1
		)

		setValue(range.Min + (range.Max - range.Min) * percent)
	end

	knob.MouseButton1Down:Connect(function()
		dragging = true
	end)

	bar.InputBegan:Connect(function(input)
		if input.UserInputType == Enum.UserInputType.MouseButton1 then
			dragging = true
			updateFromMouse(input.Position.X)
		end
	end)

	UserInputService.InputChanged:Connect(function(input)
		if dragging and input.UserInputType == Enum.UserInputType.MouseMovement then
			updateFromMouse(input.Position.X)
		end
	end)

	UserInputService.InputEnded:Connect(function(input)
		if input.UserInputType == Enum.UserInputType.MouseButton1 then
			dragging = false
		end
	end)

	suspensionSliders[property] = {
		SetValue = setValue,
		GetValue = function()
			return currentValue
		end,
	}
end

createSuspensionSlider("Damping", 78)
createSuspensionSlider("FreeLength", 140)
createSuspensionSlider("MaxForce", 202)
createSuspensionSlider("Stiffness", 264)

local suspensionRefresh = Instance.new("TextButton")
suspensionRefresh.Size = UDim2.new(1, -20, 0, 26)
suspensionRefresh.Position = UDim2.new(0, 10, 0, 335)
suspensionRefresh.BackgroundColor3 = COLOR_FIELD
suspensionRefresh.Text = "ОБНОВИТЬ"
suspensionRefresh.TextColor3 = COLOR_TEXT
suspensionRefresh.Font = Enum.Font.SourceSansBold
suspensionRefresh.TextSize = 12
suspensionRefresh.BorderSizePixel = 0
suspensionRefresh.Parent = SuspensionFrame

local suspensionRefreshCorner = Instance.new("UICorner")
suspensionRefreshCorner.CornerRadius = UDim.new(0, 4)
suspensionRefreshCorner.Parent = suspensionRefresh
addHover(suspensionRefresh, 0.06)

local suspensionStatus = Instance.new("TextLabel")
suspensionStatus.Size = UDim2.new(1, -20, 0, 20)
suspensionStatus.Position = UDim2.new(0, 10, 0, 365)
suspensionStatus.BackgroundTransparency = 1
suspensionStatus.Text = "FLSpring • FRSpring • RLSpring • RRSpring"
suspensionStatus.TextColor3 = COLOR_TEXT_DIM
suspensionStatus.Font = Enum.Font.SourceSans
suspensionStatus.TextSize = 10
suspensionStatus.TextXAlignment = Enum.TextXAlignment.Left
suspensionStatus.TextTruncate = Enum.TextTruncate.AtEnd
suspensionStatus.Parent = SuspensionFrame

local function loadSuspensionValues()
	local springs = getSuspensionSprings()
	if not springs then
		suspensionStatus.Text = "Машина или Constraints не найдены"
		return
	end

	local selected = getSelectedSuspensionSprings()
	local firstSpring = nil

	for _, spring in ipairs(selected) do
		if spring and spring:IsA("SpringConstraint") then
			firstSpring = spring
			break
		end
	end

	if not firstSpring then
		suspensionStatus.Text = "SpringConstraint не найден"
		return
	end

	for property, slider in pairs(suspensionSliders) do
		local ok, value = pcall(function()
			return firstSpring[property]
		end)

		if ok and typeof(value) == "number" then
			slider.SetValue(value)
		end
	end

	suspensionStatus.Text = "Подвеска подключена • " .. suspensionMode
end

suspensionRefresh.MouseButton1Click:Connect(loadSuspensionValues)

for _, button in pairs(suspensionButtons) do
	button.MouseButton1Click:Connect(function()
		task.defer(loadSuspensionValues)
	end)
end

-- Открытие окна по клавише RightShift даже после закрытия крестиком.
loadSuspensionValues()
end

--==================================================
-- START
--==================================================
-- НОВОЕ: дамп модулей до первого апдейта, чтобы в Output было видно,
-- что вообще удалось подключить
if DEBUG_MODULES then
	dumpGameModules()
end

-- НОВОЕ: очередь на следующий сервер ставится сразу при запуске,
-- чтобы после любого телепорта скрипт поднялся сам
queueAfterTeleport()

-- НОВОЕ: первый апдейт до показа окна, чтобы оно выехало уже с игроками,
-- а не пустым
updateList()
refreshPing()

-- НОВОЕ: Back с небольшим перелётом — окно будто подпрыгивает у края
MainFrame.Visible = true
TweenService:Create(
	MainFrame,
	TweenInfo.new(0.45, Enum.EasingStyle.Back, Enum.EasingDirection.Out),
	{ Position = UDim2.new(0.05, 0, 0.3, 0) }
):Play()

print("[BountyTracker] Loaded successfully")
