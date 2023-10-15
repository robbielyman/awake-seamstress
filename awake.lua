-- awake: time changes
-- based on v2.6.0 by @tehn
-- v0.1 @alanza
--
-- top loop plays notes
-- transposed by bottom loop
--
-- (grid optional)
--
-- mouse control! try it out
--
-- keyboard control! instructions:
-- TAB: toggles modes
-- ENTER: switches loops
-- ARROW KEYS: navigate / edit

musicutil = require "musicutil"

Grid = grid.connect()
Midi = midi.connect()

running = true

mode = 1
mode_names = { "STEP", "LOOP", "OPTION" }

one = {
  pos = 0,
  length = 8,
  data = { 1, 0, 3, 5, 6, 7, 8, 7, 0, 0, 0, 0, 0, 0, 0, 0 },
}

two = {
  pos = 0,
  length = 7,
  data = { 5, 7, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0 }
}

function add_pattern_params()
  params:add_separator("pattern_data", "pattern data")
  params:add_group("pattern_1", "pattern 1", 17)
  params:add {
    type = "number",
    id = "one_length",
    name = "length",
    min = 1,
    max = 16,
    default = one.length,
    action = function(x)
      one.length = x
    end
  }
  for i = 1, 16 do
    params:add {
      type = "number",
      id = "one_data_" .. i,
      name = "data " .. i,
      min = 0,
      max = 8,
      default = one.data[i],
      action = function(x)
        one.data[i] = x
      end
    }
  end

  params:add_group("pattern_2", "pattern 2", 17)
  params:add {
    type = "number",
    id = "two_length",
    name = "length",
    min = 1,
    max = 16,
    default = two.length,
    action = function(x)
      two.length = x
    end
  }
  for i = 1, 16 do
    params:add {
      type = "number",
      id = "two_data_" .. i,
      name = "data " .. i,
      min = 0,
      max = 8,
      default = two.data[i],
      action = function(x)
        two.data[i] = x
      end
    }
  end
end

set_loop_data = function(which, step, val)
  params:set(which .. "_data_" .. step, val)
end

local midi_devices
local midi_device
local midi_channel

local scale_names = {}
local notes = {}
local active_notes = {}

local edit_ch = 1
local edit_pos = 1
local entry_pos = 1

notes_off_metro = metro.init()

function build_scale()
  notes = musicutil.generate_scale_of_length(params:get("root_note"),
    params:get("scale_mode"),
    16)
  local num_to_add = 16 - #notes
  for i = 1, num_to_add do
    table.insert(notes, notes[16 - num_to_add])
  end
end

function all_notes_off()
  for _, note in pairs(active_notes) do
    midi_device:note_off(note, nil, midi_channel)
  end
  active_notes = {}
end

function morph(loop, which)
  for i = 1, loop.length do
    if loop.data[i] > 0 then
      set_loop_data(which, i, util.clamp(loop.data[i] + math.floor(math.random() * 3) - 1, 1, 8))
    end
  end
end

function random()
  for i = 1, one.length do
    set_loop_data("one", i, math.floor(math.random() * 9))
  end
  for i = 1, two.length do
    set_loop_data("two", i, math.floor(math.random() * 9))
  end
end

function step()
  while true do
    clock.sync(1 / params:get("step_div"))
    if running then
      all_notes_off()

      one.pos = one.pos % one.length + 1
      two.pos = two.pos % two.length + 1

      if one.data[one.pos] > 0 then
        local note_num = notes[one.data[one.pos] + two.data[two.pos]]
        if math.random(100) <= params:get("probability") then
          midi_device:note_on(note_num, 96, midi_channel)
          table.insert(active_notes, note_num)
          if params:get("note_length") < 4 then
            notes_off_metro:start((60 / params:get("clock_tempo")))
            notes_off_metro:start(
              (60 / params:get("clock_tempo") / params:get("step_div")) * params:get("note_length") * 0.25, 1)
          end
        end
      end
      if Grid then
        gridredraw()
      end
      redraw()
    end
  end
end

function stop()
  running = false
  all_notes_off()
end

function start()
  running = true
end

function reset()
  one.pos = 1
  two.pos = 1
end

function clock.transport.start()
  start()
end

function clock.transport.stop()
  stop()
end

function clock.transport.reset()
  reset()
end

function midi_event(data)
  msg = midi.to_msg(data)
  if msg.type == "continue" then
    if running then
      clock.transport.stop()
    else
      clock.transport.start()
    end
  end
end

function build_midi_device_list()
  midi_devices = {}
  for i = 1, #midi.vports do
    local long_name = midi.vports[i].name
    local short_name = string.len(long_name) > 15 and util.acronym(long_name) or long_name
    table.insert(midi_devices, i .. ": " .. short_name)
  end
end

function init()
  params:set('clock_source', 3)
  for i = 1, #musicutil.SCALES do
    table.insert(scale_names, string.lower(musicutil.SCALES[i].name))
  end

  build_midi_device_list()

  notes_off_metro.event = all_notes_off

  params:add_separator('awake_sep', "AWAKE")
  params:add {
    type = "option",
    id = "midi_device",
    name = "midi output",
    options = midi_devices, default = 1,
    action = function(value)
      midi_device = midi.connect(value)
    end
  }
  params:add {
    type = "number",
    id = "midi_out_channel",
    name = "midi out channel",
    min = 1,
    max = 16,
    default = 1,
    action = function(value)
      all_notes_off()
      midi_channel = value
    end
  }
  params:add_group("step", "step", 8)
  params:add {
    type = "number",
    id = "step_div",
    name = "step division",
    min = 1,
    max = 16,
    default = 4
  }
  params:add {
    type = "option",
    id = "note_length",
    name = "note length",
    options = { "25%", "50%", "75%", "100%" },
    default = 4,
  }
  params:add {
    type = "option",
    id = "scale_mode",
    name = "scale mode",
    options = scale_names,
    default = 5,
    action = function()
      build_scale()
    end
  }
  params:add {
    type = "number",
    id = "root_note",
    name = "root note",
    min = 0,
    max = 127,
    default = 60,
    formatter = function(param)
      return musicutil.note_num_to_name(param:get(), true)
    end,
    action = function()
      build_scale()
    end
  }
  params:add {
    type = "number",
    id = "probability",
    name = "probability",
    min = 0,
    max = 100,
    default = 100,
  }
  params:add {
    type = "trigger",
    id = "stop",
    name = "stop",
    action = function()
      stop()
      reset()
    end,
  }
  params:add {
    type = "trigger",
    id = "start",
    name = "start",
    action = function() start() end,
  }
  params:add {
    type = "trigger",
    id = "reset",
    name = "reset",
    action = function() reset() end
  }

  add_pattern_params()
  params:bang()
  midi_device.event = midi_event
  clock.run(step)
end

function Grid.key(x, y, z)
  local grid_height = Grid.rows
  if z == 0 then return end
  if (grid_height == 8 and edit_ch == 1) or (grid_height == 16 and y <= 8) then
    if one.data[x] == 9 - y then
      set_loop_data("one", x, 0)
    else
      set_loop_data("one", x, 9 - y)
    end
  end
  if (grid_height == 8 and edit_ch == 2) or (grid_height == 16 and y > 8) then
    if grid_height == 16 then y = y - 8 end
    if two.data[x] == 9 - y then
      set_loop_data("two", x, 0)
    else
      set_loop_data("two", x, 9 - y)
    end
  end
  gridredraw()
  redraw()
end

function gridredraw()
  local grid_height = Grid.rows
  Grid:all(0)
  if edit_ch == 1 or grid_height == 16 then
    for x = 1, 16 do
      if one.data[x] > 0 then Grid:led(x, 9 - one.data[x], 5) end
    end
    if one.pos > 0 and one.data[one.pos] > 0 then
      Grid:led(one.pos, 9 - one.data[one.pos], 15)
    else
      Grid:led(one.pos, 1, 3)
    end
  end
  if edit_ch == 2 or grid_height == 16 then
    local y_offset = 0
    if grid_height == 16 then y_offset = 8 end
    for x = 1, 16 do
      if two.data[x] > 0 then Grid:led(x, 9 - two.data[x] + y_offset, 5) end
    end
    if two.pos > 0 and two.data[two.pos] > 0 then
      Grid:led(two.pos, 9 - two.data[two.pos] + y_offset, 15)
    else
      Grid:led(two.pos, 1 + y_offset, 3)
    end
  end
  Grid:refresh()
end

local function normal()
  return 155, 155, 150
end
local function highlight()
  return 100, 255, 245
end
local function inactive()
  return 100, 100, 75
end
local function barelythere()
  return 75, 60, 60
end

function redraw()
  screen.clear()
  screen.color(inactive())
  screen.move(10, 10)
  local len, height = screen.get_text_size(mode_names[mode])
  screen.rect_fill(4 + len, 2 + height)
  screen.move_rel(2, 1)
  screen.color(highlight())
  screen.text(mode_names[mode])
  if mode == 1 then
    screen.color(highlight())
    screen.move(52 + edit_pos * 12, edit_ch == 1 and 66 or 126)
    screen.line_rel(8, 0)
    screen.move(10, 70)
  end
  if mode == 2 then screen.color(normal()) else screen.color(barelythere()) end
  screen.move(64, 60)
  screen.line_rel(one.length * 12 - 4, 0)
  screen.move(64, 120)
  screen.line_rel(two.length * 12 - 4, 0)
  for i = 1, one.length do
    screen.move(52 + i * 12, 60 - one.data[i] * 6)
    if i == one.pos then
      screen.color(highlight())
    elseif edit_ch == 2 and two.data[i] > 0 then
      screen.color(inactive())
    elseif mode == 2 then
      screen.color(normal())
    else
      screen.color(barelythere())
    end
    screen.line_rel(8, 0)
  end
  for i = 1, two.length do
    screen.move(52 + i * 12, 120 - two.data[i] * 6)
    if i == two.pos then
      screen.color(highlight())
    elseif edit_ch == 2 and two.data[i] > 0 then
      screen.color(inactive())
    elseif mode == 2 then
      screen.color(normal())
    else
      screen.color(barelythere())
    end
    screen.line_rel(8, 0)
  end
  screen.color(inactive())
  screen.move(10, 30)
  screen.text("bpm")
  if mode == 3 and entry_pos == 1 then screen.color(highlight()) else screen.color(normal()) end
  screen.move(10, 40)
  screen.text(params:get("clock_tempo"))
  screen.color(inactive())
  screen.move(10, 50)
  screen.text("div")
  if mode == 3 and entry_pos == 2 then screen.color(highlight()) else screen.color(normal()) end
  screen.move(10, 60)
  screen.text(params:string("step_div"))
  screen.color(inactive())
  screen.move(10, 70)
  screen.text("root")
  if mode == 3 and entry_pos == 3 then screen.color(highlight()) else screen.color(normal()) end
  screen.move(10, 80)
  screen.text(params:string("root_note"))
  screen.color(inactive())
  screen.move(10, 90)
  screen.text("scale")
  if mode == 3 and entry_pos == 4 then screen.color(highlight()) else screen.color(normal()) end
  screen.move(10, 100)
  screen.text(params:string("scale_mode"))
  screen.color(inactive())
  screen.move(10, 110)
  screen.text("prob")
  if mode == 3 and entry_pos == 5 then screen.color(highlight()) else screen.color(normal()) end
  screen.move(10, 120)
  screen.text(params:get("probability"))

  screen.refresh()
end

function screen.key(char, modifiers, _, state)
  if state == 0 then return end
  if char.name == "tab" then
    if tab.contains(modifiers, "shift") then
      mode = util.wrap(mode - 1, 1, 3)
    else
      mode = util.wrap(mode + 1, 1, 3)
    end
  elseif char.name == "enter" then
    edit_ch = edit_ch % 2 + 1
  elseif char.name == "left" or char.name == "right" then
    if mode == 1 then
      edit_pos = util.clamp(edit_pos + (char.name == "right" and 1 or -1), 1, 16)
    elseif mode == 2 then
      params:delta(edit_ch == 1 and "one_length" or "two_length", char.name == "right" and 1 or -1)
    elseif mode == 3 then
      if entry_pos == 1 then
        params:delta("clock_tempo", char.name == "right" and 1 or -1)
      elseif entry_pos == 2 then
        params:delta("step_div", char.name == "right" and 1 or -1)
      elseif entry_pos == 3 then
        params:delta("root_note", char.name == "right" and 1 or -1)
      elseif entry_pos == 4 then
        params:delta("scale_mode", char.name == "right" and 1 or -1)
      else
        params:default("probability", char.name == "right" and 1 or -1)
      end
    end
  elseif char.name == "up" or char.name == "down" then
    if mode == 1 then
      local val = edit_ch == 1 and one.data[edit_pos] or two.data[edit_pos]
      local newval = util.clamp(val + (char.name == "up" and 1 or -1), 0, 8)
      set_loop_data(edit_ch == 1 and "one" or "two", edit_pos, newval)
    elseif mode == 2 then
      edit_ch = edit_ch % 2 + 1
    elseif mode == 3 then
      entry_pos = util.clamp(entry_pos + (char.name == "up" and 1 or -1), 1, 5)
    end
  end
  redraw()
  gridredraw()
end

local click = nil
local last = {
  x = 0,
  y = 0,
}
local accum = 0
local wheel_accum = 0

function screen.click(x, y, state, button)
  if button ~= 1 then return end
  wheel_accum = 0
  if state == 0 then
    click = nil
    accum = 0
    return
  end
  click = {
    x = x,
    y = y,
  }
  if 10 <= x and x <= screen.get_text_size(mode_names[mode]) + 4 and y >= 10 and y <= 22 then
    mode = mode % 3 + 1
    redraw()
  end
end

function screen.wheel(x, y)
  if mode == 2 then
    wheel_accum = wheel_accum + x
  end
  wheel_accum = wheel_accum + y
  if mode == 1 then
    while wheel_accum >= 6 do
      local val = edit_ch == 1 and one.data[edit_pos] or two.data[edit_pos]
      set_loop_data(edit_ch == 1 and "one" or "two", edit_pos, util.clamp(val + 1, 0, 8))
      wheel_accum = wheel_accum - 6
    end
    while wheel_accum <= -6 do
      local val = edit_ch == 1 and one.data[edit_pos] or two.data[edit_pos]
      set_loop_data(edit_ch == 1 and "one" or "two", edit_pos, util.clamp(val - 1, 0, 8))
      wheel_accum = wheel_accum + 6
    end
  elseif mode == 2 then
    while wheel_accum >= 6 do
      params:delta(edit_ch == 1 and "one_length" or "two_length", 1)
      wheel_accum = wheel_accum - 6
    end
    while wheel_accum <= -6 do
      params:delta(edit_ch == 1 and "one_length" or "two_length", -1)
      wheel_accum = wheel_accum + 6
    end
  elseif mode == 3 then
    local prm
    if entry_pos == 1 then
      prm = "clock_tempo"
    elseif entry_pos == 2 then
      prm = "step_div"
    elseif entry_pos == 3 then
      prm = "root_note"
    elseif entry_pos == 4 then
      prm = "scale_mode"
    elseif entry_pos == 5 then
      prm = "probability"
    end
    while wheel_accum >= 6 do
      params:delta(prm, 1)
      wheel_accum = wheel_accum - 6
    end
    while wheel_accum <= -6 do
      params:delta(prm, -1)
      wheel_accum = wheel_accum + 6
    end
  end
end

function screen.mouse(x, y)
  local delta_x = x - last.x
  local delta_y = last.y - y
  last.x = x
  last.y = y
  if click == nil then
    if mode == 1 then
      if y <= 66 then
        if x <= 64 or x >= 256 then
          return
        else
          edit_pos = math.floor((x - 52) // 12)
          edit_ch = 1
        end
      elseif y <= 126 then
        if x <= 64 or x >= 256 then
          return
        else
          edit_pos = math.floor((x - 52) // 12)
          edit_ch = 2
        end
      end
    elseif mode == 2 then
      if y <= 66 then
        if x <= 64 then return else edit_ch = 1 end
      elseif y <= 126 then
        if x <= 64 then return else edit_ch = 2 end
      end
    elseif mode == 3 then
      if x > 60 then return end
      if y < 30 then
        return
      elseif y < 50 then
        entry_pos = 1
      elseif y < 70 then
        entry_pos = 2
      elseif y < 90 then
        entry_pos = 3
      elseif y < 110 then
        entry_pos = 4
      else
        entry_pos = 5
      end
    end
    redraw()
  else
    if click.x >= 10 and click.x <= 50 then
      if click.y >= 40 and click.y <= 50 then
        mode = 3
        entry_pos = 1
        accum = accum + delta_y
        while accum >= 5 do
          params:delta("clock_tempo", 1)
          accum = accum - 5
        end
        while accum <= -5 do
          params:delta("clock_tempo", -1)
          accum = accum + 5
        end
      elseif click.y >= 60 and click.y <= 70 then
        mode = 3
        entry_pos = 2
        accum = accum + delta_y
        while accum >= 5 do
          params:delta("step_div", 1)
          accum = accum - 5
        end
        while accum <= -5 do
          params:delta("step_div", -1)
          accum = accum + 5
        end
      elseif click.y >= 80 and click.y <= 90 then
        mode = 3
        entry_pos = 3
        accum = accum + delta_y
        while accum >= 5 do
          params:delta("root_note", 1)
          accum = accum - 5
        end
        while accum <= -5 do
          params:delta("root_note", -1)
          accum = accum + 5
        end
      elseif click.y >= 100 and click.y <= 110 then
        mode = 3
        entry_pos = 4
        accum = accum + delta_y
        while accum >= 5 do
          params:delta("scale_mode", 1)
          accum = accum - 5
        end
        while accum <= -5 do
          params:delta("scale_mode", -1)
          accum = accum + 5
        end
      elseif click.y >= 120 and click.y <= 130 then
        mode = 3
        entry_pos = 5
        accum = accum + delta_y
        while accum >= 5 do
          params:delta("probability", 1)
          accum = accum - 5
        end
        while accum <= -5 do
          params:delta("probability", -1)
          accum = accum + 5
        end
      end
    elseif click.x >= 64 and click.x < 256 then
      if click.y < 60 then
        mode = 1
        local step = math.floor((click.x - 52) // 12)
        edit_pos = step
        edit_ch = 1
        accum = accum + delta_y
        while accum >= 6 do
          local val = one.data[edit_pos]
          set_loop_data("one", step, util.clamp(val + 1, 0, 8))
          accum = accum - 6
        end
        while accum <= -6 do
          local val = one.data[edit_pos]
          set_loop_data("one", step, util.clamp(val - 1, 0, 8))
          accum = accum + 6
        end
      elseif click.y <= 66 then
        mode = 2
        edit_ch = 1
        accum = accum + delta_x
        while accum >= 12 do
          params:delta("one_length", 1)
          accum = accum - 12
        end
        while accum <= -12 do
          params:delta("one_length", -1)
          accum = accum + 12
        end
      elseif click.y < 120 then
        mode = 1
        local step = math.floor((click.x - 52) // 12)
        edit_pos = step
        edit_ch = 2
        accum = accum + delta_y
        while accum >= 6 do
          local val = two.data[edit_pos]
          set_loop_data("two", step, util.clamp(val + 1, 0, 8))
          accum = accum - 6
        end
        while accum <= -6 do
          local val = two.data[edit_pos]
          set_loop_data("two", step, util.clamp(val - 1, 0, 8))
          accum = accum + 6
        end
      elseif click.y <= 126 then
        mode = 2
        edit_ch = 2
        accum = accum + delta_x
        while accum >= 12 do
          params:delta("two_length", 1)
          accum = accum - 12
        end
        while accum <= -12 do
          params:delta("two_length", -1)
          accum = accum + 12
        end
      end
    end
    redraw()
    gridredraw()
  end
end

function cleanup()
  all_notes_off()
  Grid:all(0)
  Grid:refresh()
end
