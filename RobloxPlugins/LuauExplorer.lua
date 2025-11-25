--[[
LuauExplorer
]]

local ExplorerPluginName = "Explorer"
local PropertiesPluginName = "Properties"

local RunService = game:GetService("RunService")

local CoreGui = game:GetService("CoreGui")

local Packages = script.Packages

local Fusion = require(Packages.Fusion)
local Cleanup = Fusion.Cleanup
local New = Fusion.New
local Tween = Fusion.Tween
local Value = Fusion.Value
local Children = Fusion.Children
local Scoped = Fusion.scoped

local GoodSignal = require(Packages.GoodSignal)
local Janitor = require(Packages.Janitor)

local PluginSignal = GoodSignal.new()
local PluginJanitor = Janitor.new()

local ExplorerScope = Scoped(Fusion)
local PropertiesScope = Scoped(Fusion)

local ExplorerActive = false
local PropertiesActive = false

local IsExplorerFirstRun = ExplorerScope.Value(ExplorerScope, true)
local IsPropertiesFirstRun = PropertiesScope.Value(PropertiesScope, true)

toolbar = plugin:CreateToolbar("StudioNT")

local widgetInfo = DockWidgetPluginGuiInfo.new(
	Enum.InitialDockState.Left, -- Widget will be initialized in floating panel
	false, -- Widget will be initially enabled
	false, -- Don't override the previous enabled state
	200, -- Default width of the floating window
	300, -- Default height of the floating window
	150, -- Minimum width of the floating window (optional)
	150 -- Minimum height of the floating window (optional)
)

local ExplorerWidget = plugin:CreateDockWidgetPluginGui("Explorer", widgetInfo)
--local PropertiesWidget = plugin:CreateDockWidgetPluginGui("Properties", widgetInfo)

local function createUtilityUI(Launch: string)
	if Launch == "Explorer" then
		local UtilityUI = ExplorerScope:New("ScreenGui")({
			Name = "UtilityUI",
			Parent = CoreGui:WaitForChild(Launch),
		})
	elseif Launch == "Properties" then
		local UtilityUI = PropertiesScope:New("ScreenGui")({
			Name = "UtilityUI",
			Parent = CoreGui:WaitForChild(Launch),
		})
	end
end

local ExplorerButton =
	toolbar:CreateButton("Explorer", "View a list of objects in the game tree.", "rbxassetid://125300760963399")
ExplorerButton.ClickableWhenViewportHidden = true

local PropertiesButton =
	toolbar:CreateButton("Properties", "View and modify the properties of objects.", "rbxassetid://14978048121")
PropertiesButton.ClickableWhenViewportHidden = true
PropertiesButton.Click:Connect(function()
	PropertiesActive:set(not PropertiesScope:peek(PropertiesActive))
	createUtilityUI("Properties")
	--PropertiesWidget.Enabled = not PropertiesWidget.Enabled
end)

-- Explorer

local function CalculatePixelDensity(ScreenWidthInInches: number)
	local PixelDensity = workspace.Camera.ViewportSize.X / ScreenWidthInInches
	print(PixelDensity)
	return PixelDensity
end

local Order = {
	"Workspace",
	"Players",
	"CoreGui",
	"Lighting",
	"MaterialService",
	"PluginDebugService",
	"PluginGuiService",
	"ReplicatedFirst",
	"ReplicatedStorage",
	"RobloxPluginGuiService",
	"ServerScriptService",
}

local ExplorerRootFrame = ExplorerScope:New("Frame")({
	Name = "MainContentContainer",
	Parent = ExplorerWidget,
	Size = UDim2.fromScale(1, 1),
	BackgroundTransparency = 1,
})

local SearchField: TextBox = ExplorerScope:New("TextBox")({
	Name = "SearchField",
	Parent = ExplorerRootFrame,
	PlaceholderText = "Search for an Instance",
	ZIndex = 10, -- Much higher ZIndex to ensure it's on top
	Size = UDim2.new(0.75, 0, 0, 30),
	Position = UDim2.new(0, 0, 0, 5),
	LayoutOrder = 1, -- Explicitly set layout order
	BackgroundColor3 = Color3.fromRGB(255, 255, 255),
	TextColor3 = Color3.fromRGB(0, 0, 0),
	BorderColor3 = Color3.fromRGB(202, 202, 202),
	FontFace = Font.fromEnum(Enum.Font.Roboto),

	[Children] = {
		ExplorerScope:New("UICorner")({
			Name = "SearchUICorner",
			CornerRadius = UDim.new(0, 4),
		}),
	},
})

SearchField.MouseEnter:Connect(function()
	SearchField.BorderSizePixel = 1
end)

SearchField.MouseLeave:Connect(function()
	SearchField.BorderSizePixel = 0
end)

SearchField.Focused:Connect(function()
	SearchField.BorderSizePixel = 2
end)

SearchField.FocusLost:Connect(function()
	SearchField.BorderSizePixel = 0
end)

local HistoryButton = ExplorerScope:New("ImageButton")({
	Name = "HistoryButton",
	Image = "rbxassetid://79107480279997",
	Parent = ExplorerRootFrame,

	Position = UDim2.new(0.8, 0, 0, 5),
})

local InstancesFrame = ExplorerScope:New("ScrollingFrame")({
	Name = "GameTree",
	Parent = ExplorerRootFrame,
	ZIndex = 5,
	Size = UDim2.new(1, -10, 1, -40),
	Position = UDim2.new(0, 5, 0, 40),
	CanvasSize = UDim2.new(0, 0, 0, 0),
	AutomaticCanvasSize = Enum.AutomaticSize.Y,
	ScrollBarThickness = 8,
	LayoutOrder = 2,
	BackgroundTransparency = 1,
	BorderSizePixel = 1,
})

ExplorerScope:New("UIListLayout")({
	Parent = ExplorerRootFrame,
	FillDirection = Enum.FillDirection.Vertical,
	HorizontalAlignment = Enum.HorizontalAlignment.Left,
	VerticalAlignment = Enum.VerticalAlignment.Top,
	Padding = UDim.new(0, 5),
	SortOrder = Enum.SortOrder.LayoutOrder,
})

ExplorerScope:New("UIPadding")({
	Parent = ExplorerRootFrame,
	PaddingTop = UDim.new(0, 12),
	PaddingBottom = UDim.new(0, 12),
	PaddingLeft = UDim.new(0, 24),
	PaddingRight = UDim.new(0, 24),
})

-- Search Logic (Note to myself (or you if you're reading my code), find a better way to do this.)
-- I had to hook this into the main update code, this will be buggy.

local ExplorerSections = {}

local function ClearAndRestore()
	for ItemButton, Button in ipairs(InstancesFrame:GetDescendants()) do
		if Button:IsA("TextButton") then
			Button:Destroy()
		end
	end

	table.clear(ExplorerSections)

	local ServicesIndex
	for ServiceIndex, ServiceName in ipairs(Order) do
		table.insert(
			ExplorerSections,
			ExplorerScope:New("TextButton")({
				Name = "S_" .. ServiceName,
				Text = ServiceName,
				Parent = InstancesFrame,
				Size = UDim2.new(1, -10, 0, 25),
				Position = UDim2.new(0, 5, 0, (ServiceIndex - 1) * 30),
				BackgroundTransparency = 0.5,

				FontFace = Font.fromEnum(Enum.Font.Roboto),
			})
		)
		ServicesIndex = ServiceIndex
	end
end

local ServicesIndex
for ServiceIndex, ServiceName in ipairs(Order) do
	table.insert(
		ExplorerSections,
		ExplorerScope:New("TextButton")({
			Name = "S_" .. ServiceName,
			Text = ServiceName,
			Parent = InstancesFrame,
			Size = UDim2.new(1, 0, 0, 25),
			Position = UDim2.new(0, 0, 0, (ServiceIndex - 1) * 30),
			BackgroundTransparency = 0.5,
			FontFace = Font.fromEnum(Enum.Font.Roboto),

			[Children] = {
				ExplorerScope:New("UICorner")({
					Name = "S_" .. ServiceName .. "UICorner",
					CornerRadius = UDim.new(0, 4),
				}),
			},
		})
	)
	ServicesIndex = ServiceIndex
end

local ExistingResults = {}
SearchField:GetPropertyChangedSignal("Text"):Connect(function()
	if SearchField.Text ~= "" then
		ClearAndRestore()
		for ItemNumber, Button in ipairs(InstancesFrame:GetDescendants()) do
			if Button:IsA("TextButton") then
				if not Button.Name:match("S_") then
					Button:Destroy()
				end
			end
		end

		task.wait()
		for ResultNumber, ResultButton in ipairs(ExistingResults) do
			if ResultButton and ResultButton.Parent then
				ResultButton:Destroy()
			end
		end
		table.clear(ExistingResults)
		ExistingResults = {}

		print(SearchField.Text)
		local Descendants = game:GetDescendants()
		for i, v in ipairs(Descendants) do
			if v.Name:match(SearchField.Text) then
				table.insert(
					ExistingResults,
					ExplorerScope:New("TextButton")({
						Name = v.Name,
						Text = v.Name,
						Parent = InstancesFrame:WaitForChild("S_" .. v.Parent.Name),
						Size = UDim2.new(1, -10, 0, 25),
						Position = UDim2.new(0, 5, 0, ((ServicesIndex + i) - 1) * 30),
						BackgroundTransparency = 0.8,
					})
				)
			end
		end
	else
		ClearAndRestore()
	end
end)

ExplorerButton.Click:Connect(function()
	ExplorerActive = not ExplorerActive
	ExplorerWidget.Enabled = not ExplorerWidget.Enabled
end)
