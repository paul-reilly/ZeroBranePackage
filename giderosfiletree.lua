--
--              Contributed by Paul Reilly (@paul-reilly) 2017
--
--
-- Features:
--
--    1. Adds Lua files to the ZBS project file tree that are listed in a Gideros
--       project file, but are not in the project directory.
--
--       Gideros project file required at root level of project directory.
--
--    2. Filters folders in project root from file tree that start with entries in
--       ignore table set in preferences/config file user.lua
--
-- Example:
--                giderosfiletree = {
--                     ignore = { "Export", ".tmp" },
--                  recursive = true
--                }
--
--    This will remove the folder (eg) "PROJECTDIRECTORY/Export Android/" from the file
--    tree, but will not remove (eg) "PROJECTDIRECTORY/Export Manager.lua"
--
----------------------------------------------------------------------------------------------------

local projectPath = nil
local giderosProj = false
local tree = {}
local config = {}

-- shorten path by 'levels' number of levels
local function getPathLevelsUp(path, levels)
  if levels <= 0 then return nil end
  local last_pos = #path
  while levels > -1 do
    local s = path:sub(last_pos, last_pos)
    if s:find("[\\/]") then levels = levels -1 end
    last_pos = last_pos - 1
    if last_pos < 0 then return nil end
  end
  return path:sub(1, last_pos)
end

--
local function getFullPathFromPathRelativeToProjectPath(s)
  local rel = string.find(s, "[A-z]")
  if rel > 1 then
    s = getPathLevelsUp(projectPath, (rel-1)/3) .. s:sub(rel - 1, #s)
  end
  return s, rel
end

-- returns table of lua files, either relative to project
-- path when children or absolute when not in project path
local function luaFilesFromGidProj(projStr, relativeOnly)
  local files = {}
  local i = 0
  local tokenStart = "source=\""
  local tokenEnd = "\"/"
  while true do
    i = string.find(projStr, tokenStart, i)

    if i == nil then
      if #files == 0 then return nil end
      return files
    end

    i = i + #tokenStart
    local j = string.find(projStr, tokenEnd, i)
    if j then
      local s = string.sub(projStr, i, j - 1)
      local orig = s
      if string.sub(s, -4) == ".lua" then
        local rel
        s, rel = getFullPathFromPathRelativeToProjectPath(s)
        if s then
          if (rel <= 1 and not relativeOnly) or (rel > 1) then
            files[#files+1] = {fn = s, orig = orig}
          end
        end
      end
    end
  end
end


local function patternDeleteNodes(child, pattern, recursive)
  local text
  while child:IsOk() do
    text = tree.ctrl:GetItemText(child)
    if text:find(pattern) and not text:find("%.lua") then
      child = tree.ctrl:GetNextSibling(child)
      tree.ctrl:Delete(tree.ctrl:GetPrevSibling(child))
    else
      if recursive and tree.ctrl:ItemHasChildren(child) then
        patternDeleteNodes(tree.ctrl:GetFirstChild(child), pattern, true)
      end
      child = tree.ctrl:GetNextSibling(child)
    end
  end
end


--
local function updateFiletree(projName)
  local projStr = FileRead(projectPath .. projName)
  if not projStr then return end
  local files = luaFilesFromGidProj(projStr, true)
  --if not files then return end
  local root = tree.ctrl:GetRootItem()
  -- prevent UI updates in control to stop flickering
  ide:GetProjectNotebook():Freeze()

  -- freezing whole notebook, so protect call in case of error
  pcall( function ()
    -- delete nodes with directories starting with what's in ignore table
    for _, v in pairs(config.ignoreTable) do
      v = "^" .. v
      local child, text = tree.ctrl:GetFirstChild(tree.ctrl:GetRootItem()), nil
      patternDeleteNodes(child, v, config.recursive)
    end
    -- add our external Gideros project file
    for _, v in pairs(files) do
      if not tree.getFileNode(v.orig) then
        local item = tree.ctrl:InsertItem(root, 0, v.orig)
      end
    end
  end)

  ide:GetProjectNotebook():Thaw()
end

--
tree.getFileNode = function(fn)
  return tree.getChildByItemText(tree.ctrl:GetRootItem(), fn)
end

--
tree.getChildByItemText = function(parentItem, childName)
  local child, text = tree.ctrl:GetFirstChild(parentItem), nil
  while child:IsOk() do
    text = tree.ctrl:GetItemText(child)
    if text == childName then return child end
    child = tree.ctrl:GetNextSibling(child)
  end
  return nil
end

--
tree.setDataTable = function(item, t)
  local itemData = tree.ctrl:GetItemData(item)
  if itemData == nil then itemData = wx.wxLuaTreeItemData() end
  itemData:SetData(t)
  tree.ctrl:SetItemData(item, itemData)
end

-- our plugin/package object/table
local package = {
  name = "Gideros Filetree Assistant",
  description = "Adds external Gideros files to file tree / Configurable directory filtering.",
  author = "Paul Reilly",
  version = 0.1,
  dependencies = 1.60,

  --
  onRegister = function(self)
    config.ignoreTable = self:GetConfig().ignore or {}
    config.recursive = self:GetConfig().recursive or false
    tree.ctrl = ide:GetProjectTree()
  end,

  --
  onProjectPreLoad = function(self, project)
    -- do this here because this is called before onFileTreeRefresh when
    -- switching projects, whereas onProjectLoad is called after.
    -- Filetree is not valid for searching here, so use files and set
    -- correct project path if Gideros project found for Refresh event to use.
    tree.ctrl = ide:GetProjectTree()
    projectPath = project
    local projName
    for _, filePath in ipairs(ide:GetFileList(projectPath, false, "*.gproj")) do
      projName = filePath:gsub(projectPath, "")
    end
    if projName then
      giderosProj = projName
    else
      giderosProj = nil
    end
  end,

  --
  onProjectLoad = function(self, project)
    if giderosProj then
      ide:DoWhenIdle(function()
          updateFiletree(giderosProj)
        end
      )
    end
  end,

  --
  onFiletreeFileRefresh = function(self, tree, item, filepath)
    if giderosProj then updateFiletree(giderosProj) end
  end,

  onFiletreeActivate = function(self, tree, event, item)
    if not giderosProj then return true end
    tree.ctrl = ide:GetProjectTree()
    local txt = tree.ctrl:GetItemText(item)
    if txt:sub(1,2) == ".." then
      local fullPath = getFullPathFromPathRelativeToProjectPath(txt)
      if wx.wxFileExists(fullPath) then
        LoadFile(fullPath, nil, true)
        return false
      end
    end
    return true
  end
}

return package
