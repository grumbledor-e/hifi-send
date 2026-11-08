local mods = require 'core/mods'
local root = _path.code .. 'hifi-send/'
local data = _path.data .. 'hifi-send/'
local state = {message='setup required', devices={}, target='', volume=20, heartbeat=0, buffer=500, draft=500}
local row, serial, timer = 1, 0, nil
local function quote(s) return "'" .. s:gsub("'", "'\\''") .. "'" end
local function launch()
  local f = io.open(data .. 'config.json', 'r')
  if not f then return end
  f:close()
  -- Worker is managed by norns-hifi-worker.service.

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
  row=math.max(1,math.min(row,#state.devices+3))
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
  launch(); read(); state.draft=state.buffer
  timer=metro.init(function() read(); mods.menu.redraw() end,1,-1)
  timer:start()
end
menu.deinit=function() if timer then timer:stop(); timer=nil end end
menu.enc=function(n,d)
  if n==2 then row=math.max(1,math.min(row+d,#state.devices+3))
  elseif n==3 then
    if row==3 then
      state.draft=math.max(100,math.min(2100,state.draft+d*50))
      mods.menu.redraw(); return
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
    else
      local device=state.devices[row-3]
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
  for i=first,math.min(first+2,#state.devices+3) do
    local text
    if i==1 then text='disconnect'
    elseif i==2 then text='refresh devices'
    elseif i==3 then text='buffer ' .. state.draft .. 'ms (' .. state.buffer .. ')'
    else
      local device=state.devices[i-3]
      text=(device.id==state.target and '* ' or '') .. device.name
    end
    screen.level(i==row and 15 or 4); screen.move(0,29+(i-first)*10)
    screen.text((i==row and '> ' or '  ') .. text:sub(1,24))
  end
  screen.level(4); screen.move(0,63); screen.text(row==3 and 'e3 adjust   k3 apply' or 'e2 select   k3 connect   e3 vol')
  screen.update()
end
mods.hook.register('system_post_startup','hifi-send startup',launch)
mods.menu.register(mods.this_name,menu)
return {stop=function() send('stop') end}
