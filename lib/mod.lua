local mods = require 'core/mods'
local data = _path.data .. 'hifi-send/'
local state = {message='setup required', devices={}, target='', volume=20, heartbeat=0, buffer=500, draft=500}
local row, serial, timer = 1, 0, nil
-- menu rows before the device list: disconnect, refresh, buffer, cover
local FIXED = 4
-- album cover refresh from the norns screen, in seconds (0 = off).
-- A Samsung TV stopped redrawing the cover at 1-2 s; 3 s is the fastest.
local COVER_CHOICES = {0, 3, 5, 10, 15, 30, 60}
local cover_seconds = 5
do
  local f = io.open(data .. 'cover.txt', 'r')
  local saved = f and tonumber(f:read('l'))
  if f then f:close() end
  -- round a saved value up to the nearest choice
  for _, v in ipairs(COVER_CHOICES) do
    if saved and v >= saved then cover_seconds = v; break end
  end
end
local function set_cover(d)
  local i = 1
  for n, v in ipairs(COVER_CHOICES) do if v <= cover_seconds then i = n end end
  cover_seconds = COVER_CHOICES[util.clamp(i + d, 1, #COVER_CHOICES)]
  local f = io.open(data .. 'cover.txt', 'w')
  if f then f:write(cover_seconds, '\n'); f:close() end
end
local function read()
  local f = io.open(data .. 'status.tsv', 'r')
  if not f then return end
  state.devices = {}
  for line in f:lines() do
    local fields = {}
    for value in line:gmatch('[^\t]+') do fields[#fields+1] = value end
    if fields[1]=='status' then state.message=fields[2] or 'off'
    elseif fields[1]=='target' then state.target=fields[2] or ''
    elseif fields[1]=='volume' then state.volume=tonumber(fields[2]) or 20
    elseif fields[1]=='heartbeat' then state.heartbeat=tonumber(fields[2]) or 0
    elseif fields[1]=='buffer' then state.buffer=tonumber(fields[2]) or 500
    elseif fields[1]=='device' then
      state.devices[#state.devices+1]={id=fields[2],name=fields[3] or '?'}
    end
  end
  f:close()
  if os.time()-state.heartbeat > 15 then state.message='worker offline; see install guide' end
  row=math.max(1,math.min(row,#state.devices+FIXED))
end
local function send(command)
  serial=serial+1
  local path=data .. 'commands/' .. string.format('%010d-%06d',os.time(),serial)
  local f=io.open(path .. '.tmp','w')
  if not f then state.message='run setup.sh first'; return end
  f:write(command .. '\n'); f:close()
  os.rename(path .. '.tmp',path .. '.cmd')
end
local menu = {}
menu.init=function()
  read(); state.draft=state.buffer
  timer=metro.init(function() read(); mods.menu.redraw() end,1,-1)
  timer:start()
end
menu.deinit=function() if timer then timer:stop(); timer=nil end end
menu.enc=function(n,d)
  if n==2 then row=math.max(1,math.min(row+d,#state.devices+FIXED))
  elseif n==3 then
    if row==3 then
      state.draft=math.max(100,math.min(2100,state.draft+d*50))
      mods.menu.redraw(); return
    elseif row==4 then
      set_cover(d); mods.menu.redraw(); return
    end
    state.volume=math.max(0,math.min(100,state.volume+d))
    send('volume\t' .. state.volume)
  end
  mods.menu.redraw()
end
menu.key=function(n,z)
  if z~=1 then return end
  if n==2 then mods.menu.exit()
  elseif n==3 then
    if row==1 then send('stop')
    elseif row==2 then send('refresh')
    elseif row==3 then send('buffer\t' .. state.draft)
    elseif row==4 then return
    else
      local device=state.devices[row-FIXED]
      if device then
        if device.id==state.target then send('stop') else send('connect\t' .. device.id) end
      end
    end
  end
end
menu.redraw=function()
  screen.clear(); screen.font_face(1); screen.font_size(8)
  screen.level(15); screen.move(0,8); screen.text('hifi send')
  screen.move(128,8); screen.text_right(state.volume .. '%')
  screen.level(6); screen.move(0,18); screen.text(state.message:sub(1,29))
  local first=math.max(1,row-2)
  for i=first,math.min(first+2,#state.devices+FIXED) do
    local text
    if i==1 then text='disconnect'
    elseif i==2 then text='refresh devices'
    elseif i==3 then text='buffer ' .. state.draft .. 'ms (' .. state.buffer .. ')'
    elseif i==4 then text='cover ' .. (cover_seconds==0 and 'off' or ('every ' .. cover_seconds .. 's'))
    else
      local device=state.devices[i-FIXED]
      text=(device.id==state.target and '* ' or '') .. device.name
    end
    screen.level(i==row and 15 or 4); screen.move(0,29+(i-first)*10)
    screen.text((i==row and '> ' or '  ') .. text:sub(1,24))
  end
  screen.level(4); screen.move(0,63); screen.text(row==3 and 'e3 adjust   k3 apply' or row==4 and 'e3 adjust' or 'e2 select   k3 connect   e3 vol')
  screen.update()
end
mods.menu.register(mods.this_name,menu)

-- now playing: the receiver shows the script's name and author, the loaded
-- PSET's name as the album, and a snapshot of the screen. The worker reads
-- these files; matron does no network or image work.
local ticker,ticks,last_screen=nil,0,nil
local now={title='norns',artist='norns',album='norns'}
local pset=nil -- name of the PSET loaded since the script started
local function one_line(s) return (tostring(s or ''):gsub('[\t\r\n]',' ')) end
local function write_now_playing()
  local path=data .. 'now-playing.tsv'
  local f=io.open(path .. '.tmp','w')
  if not f then return end
  f:write('title\t',one_line(now.title),'\nartist\t',one_line(now.artist),
    '\nalbum\t',one_line(now.album),'\n')
  f:close()
  os.rename(path .. '.tmp',path)
end
local function read_file(path)
  local f=io.open(path,'r')
  if not f then return '' end
  local text=f:read('a') or ''
  f:close()
  return text
end
local function nonempty(s) return type(s)=='string' and s:match('%S') and s or nil end
-- 'a b c' -> 'a, b & c' (the catalog separates co-authors with spaces)
local function join_names(text)
  local names={}
  for name in text:gmatch('%S+') do names[#names+1]=name end
  if #names<2 then return names[1] end
  return table.concat(names,', ',1,#names-1) .. ' & ' .. names[#names]
end
-- author: norns.community catalog, then '@name' in the script header,
-- then the GitHub owner of the install.
local function script_author()
  local dir=norns.state.script:match('(.*/)') or ''
  -- maiden's install record; has a catalog entry for catalog installs
  local ok,project=pcall(json.decode,read_file(dir .. '.project'))
  if not ok or type(project)~='table' then project={} end
  local entry=type(project.catalog_entry)=='table' and project.catalog_entry or {}
  if nonempty(entry.author) then return join_names(entry.author) end
  local ok_header,header=pcall(norns.script.metadata,norns.state.script)
  for _,line in ipairs(ok_header and header or {}) do
    local author=line:match('^@([%w_%-%.]+)') or line:match('%s@([%w_%-%.]+)')
    if author then return author end
  end
  return (nonempty(project.project_url) or ''):match('^https?://github%.com/([^/]+)/')
end
-- PSET name: the '-- name' first line of the file, as norns reads it.
-- Returns nil if the file is missing, '' if it has no name.
local function pset_name(filename)
  filename=filename or norns.state.pset_last
  if type(filename)=='number' then
    filename=string.format('%s%s-%02d.pset',norns.state.data,norns.state.shortname,filename)
  end
  local f=type(filename)=='string' and io.open(filename,'r')
  if not f then return nil end
  local first=f:read('l') or ''
  f:close()
  return first:match('^%-%- ?(.-)%s*$') or ''
end
-- catch every PSET load: PSET menu, params:default() in init, script calls
if not paramset.hifi_send_read then
  paramset.hifi_send_read=paramset.read
  paramset.read=function(self,filename,...)
    local name=self==params and pset_name(filename)
    local results=table.pack(paramset.hifi_send_read(self,filename,...))
    if name then
      pset=name
      now.album=nonempty(name) or 'norns'
      write_now_playing()
    end
    return table.unpack(results,1,results.n)
  end
end
-- screen snapshot: raw levels (one byte per pixel), written only when the
-- screen changed; the worker turns it into the cover image
local function snapshot()
  ticks=ticks+1
  if cover_seconds==0 or _menu.mode then return end
  if ticks~=2 and ticks%cover_seconds~=0 then return end
  local pixels=screen.peek(0,0,128,64)
  if not pixels or pixels==last_screen then return end
  last_screen=pixels
  local path=data .. 'screen.raw'
  local f=io.open(path .. '.tmp','wb')
  if not f then return end
  f:write(pixels); f:close()
  os.rename(path .. '.tmp',path)
end
mods.hook.register('script_pre_init','hifi-send now playing',function()
  pset=nil
end)
mods.hook.register('script_post_init','hifi-send now playing',function()
  local ok,author=pcall(script_author)
  now.title=norns.state.shortname
  now.artist=ok and author or 'norns'
  now.album=nonempty(pset) or 'norns'
  write_now_playing()
  ticks,last_screen=0,nil
  ticker=metro.init(snapshot,1,-1)
  if ticker then ticker:start() end
end)
mods.hook.register('script_post_cleanup','hifi-send now playing',function()
  -- norns frees script metros right after this hook
  if ticker then ticker:stop(); ticker=nil end
  now={title='norns',artist='norns',album='norns'}
  write_now_playing()
end)

return {stop=function() send('stop') end}
