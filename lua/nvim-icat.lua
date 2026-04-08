-- Image Popup Plugin for Neovim
-- Usage: :lua require('image_popup').show_image('/path/to/image.png')

local M = {}
local DEBUG_ENABLED = os.getenv("IMGCAT_DEBUG") == "1" or false
local DEBUG_FILE = "debug-plugin.txt"
local debug_file_handle = nil
local IMAGE_EXTENSIONS = {
    avif = true,
    bmp = true,
    gif = true,
    heic = true,
    heif = true,
    ico = true,
    jpeg = true,
    jpg = true,
    png = true,
    tif = true,
    tiff = true,
    webp = true,
}

local function debug_log(message)
    if not DEBUG_ENABLED then return end

    if not debug_file_handle then
        debug_file_handle = io.open(DEBUG_FILE, "a")
        if debug_file_handle then
            debug_file_handle:write(string.format("[%s] === DEBUG SESSION START ===\n", os.date("%Y-%m-%d %H:%M:%S")))
        else
            io.stderr:write("DEBUG: Failed to open debug file: " .. DEBUG_FILE .. "\n")
            return
        end
    end

    if debug_file_handle then
        debug_file_handle:write(string.format("[%s] %s\n", os.date("%Y-%m-%d %H:%M:%S"), message))
        debug_file_handle:flush()
    end
end

local function join_path(dir, name)
    if not dir or dir == "" or not name or name == "" then return nil end
    if name:match("^/") or name:match("^%a:[/\\]") then return name end
    return dir:gsub("[/\\]$", "") .. "/" .. name
end

local function is_image_file(path)
    if not path or path == "" then return false end

    local expanded = vim.fn.fnamemodify(vim.fn.expand(path), ":p")
    local ext = vim.fn.fnamemodify(expanded, ":e"):lower()
    return IMAGE_EXTENSIONS[ext] and vim.fn.filereadable(expanded) == 1
end

local function open_regular_file_browser_entry()
    if vim.bo.filetype == "oil" then
        local ok, actions = pcall(require, "oil.actions")
        if ok and actions.select and actions.select.callback then
            actions.select.callback()
            return true
        end
    elseif vim.bo.filetype == "netrw" then
        local keys = vim.api.nvim_replace_termcodes("<Plug>NetrwLocalBrowseCheck", true, false, true)
        vim.api.nvim_feedkeys(keys, "m", false)
        return true
    end

    return false
end

local function oil_cursor_path()
    local ok, oil = pcall(require, "oil")
    if not ok then return nil end

    local entry = oil.get_cursor_entry()
    if not entry or entry.type == "directory" then return nil end

    local dir = oil.get_current_dir()
    if not dir or dir:match("^%w+://") then return nil end

    return join_path(dir, entry.name)
end

local function netrw_cursor_path()
    local dir = vim.b.netrw_curdir
    if not dir or dir == "" then return nil end

    local ok, name = pcall(vim.fn["netrw#Call"], "NetrwGetWord")
    if not ok or not name or name == "" then
        name = vim.fn.expand("<cfile>")
    end

    name = (name or ""):gsub("^%s+", ""):gsub("%s+$", "")
    if name == "" or name == "./" or name == "../" then return nil end

    return join_path(dir, name)
end

local function get_iterm2_cell_size()
  -- iTerm2 proprietary sequence: OSC 1337 ; ReportCellSize ST
  -- \27 is Escape, \7 is BEL (terminator)
  local query = "\27]1337;ReportCellSize\a"
  -- Create a pipe to capture stdin (terminal response)
  local stdin = vim.loop.new_tty(0, true)
  -- Send the query to stdout
  io.write(query)
  io.flush()

  -- Listen for the response
  stdin:read_start(function(err, data)
    assert(not err, err)
    if data then
      -- Response format: ^[]1337;ReportCellSize=Height;Width;Scale^G
      local h, w, s = data:match("ReportCellSize=([%d%.]+);([%d%.]+);?([%d%.]*)")
      if h and w then
        vim.schedule(function()
          print(string.format("Cell Size: %sx%s (Scale: %s)", w, h, s ~= "" and s or "1.0"))
        end)
      end
      -- Stop reading and clean up
      stdin:read_stop()
      stdin:close()
    end
  end)
end

-- Store the imgcat script path - relative to this plugin file
-- Gets the directory of the current file and looks for imgcat.lua there
local current_file_dir = debug.getinfo(1, "S").source:sub(2):match("(.*)/")
local IMGCAT_SCRIPT = current_file_dir .. '/imgcat.lua'  -- Go up one level from lua/ dir

-- Function to check if imgcat script exists
local function check_imgcat()
    -- Expand the path to handle relative paths properly
    local expanded_path = vim.fn.expand(IMGCAT_SCRIPT)

    if vim.fn.filereadable(expanded_path) == 0 then
        vim.notify('imgcat script not found at: ' .. expanded_path, vim.log.levels.ERROR)
        vim.notify('Current working directory: ' .. vim.fn.getcwd(), vim.log.levels.INFO)
        vim.notify('Please check the path or set the correct path in the plugin', vim.log.levels.ERROR)
        return false
    end
    return true
end

local function read_command_output(cmd)
    local handle = io.popen(cmd)
    if not handle then return nil end
    local result = handle:read("*a")
    handle:close()
    result = (result or ""):match("^%s*(.-)%s*$")
    if result == "" then return nil end
    return result
end

local function imgcat_tty_name()
    local result = read_command_output("tty 2>/dev/null")
    if not result or result == "not a tty" or not result:match("^/dev/") then
        return nil
    end
    return result
end

local function nvim_process_tty_name()
    local uv = vim.uv or vim.loop
    if not uv or not uv.os_getpid then return nil end

    local result = read_command_output(string.format("ps -o tty= -p %d 2>/dev/null", uv.os_getpid()))
    if not result or result:match("^%?+$") then return nil end
    if result:match("^/dev/") then return result end
    return "/dev/" .. result
end

function M.tty_info()
    local imgcat_tty = imgcat_tty_name()
    local process_tty = nvim_process_tty_name()

    return {
        imgcat_tty = imgcat_tty,
        nvim_process_tty = process_tty,
        startup_tty = vim.g.nvim_icat_startup_tty,
        configured_tty = vim.g.nvim_icat_tty,
        term = vim.env.TERM,
        tmux = vim.env.TMUX,
        bufname = vim.api.nvim_buf_get_name(0),
        buftype = vim.bo.buftype,
        filetype = vim.bo.filetype,
        win = vim.api.nvim_get_current_win(),
    }
end

function M.notify_tty()
    local info = M.tty_info()
    local lines = {
        "imgcat tty: " .. (info.imgcat_tty or "nil"),
        "nvim process tty: " .. (info.nvim_process_tty or "nil"),
        "startup tty: " .. (info.startup_tty or "nil"),
        "vim.g.nvim_icat_tty: " .. (info.configured_tty or "nil"),
        "TERM: " .. (info.term or "nil"),
        "TMUX: " .. (info.tmux and "set" or "nil"),
        "bufname: " .. (info.bufname ~= "" and info.bufname or "[No Name]"),
        "buftype: " .. (info.buftype ~= "" and info.buftype or "normal"),
        "filetype: " .. (info.filetype ~= "" and info.filetype or "none"),
        "win: " .. tostring(info.win),
    }
    local message = table.concat(lines, "\n")
    debug_log("tty diagnostics:\n" .. message)
    vim.notify(message, vim.log.levels.INFO, { title = "icat tty" })
    return info
end

-- Function to create image display tab
local function create_image_tab(image_path)
    -- Create a new tab
    vim.cmd('tabnew')

    debug_log("created new tab")
    -- Get the current buffer
    local buf = vim.api.nvim_get_current_buf()

    -- Set buffer properties to make it locked and special
    vim.bo[buf].buftype = 'nofile'
    vim.bo[buf].bufhidden = 'wipe'
    vim.bo[buf].swapfile = false
    vim.bo[buf].modifiable = false
    vim.bo[buf].readonly = true
    vim.bo[buf].filetype = 'image_viewer'

    -- Set buffer name
    local filename = vim.fn.fnamemodify(image_path, ':t')
    vim.api.nvim_buf_set_name(buf, 'Image: ' .. filename)

    -- Add some info text (optional)
    local info_lines = {
        '  Path: ' .. image_path,
        '',
    }

    -- Temporarily make buffer modifiable to add content
    vim.bo[buf].modifiable = true
    vim.bo[buf].readonly = false
    vim.api.nvim_buf_set_lines(buf, 0, -1, false, info_lines)
    vim.bo[buf].modifiable = false
    vim.bo[buf].readonly = true
    local tabnr = vim.fn.tabpagenr()


    -- Set up key mappings for the image tab
    local function close_image_tab()
        local tab_handle = vim.fn.tabpagebuflist(tabnr)
        if tab_handle ~= nil and tab_handle ~= 0 then
            vim.cmd('tabclose ' .. tabnr)

            vim.defer_fn(function()
                vim.cmd('redrawstatus!')
                vim.cmd('redraw!')
                vim.cmd('redrawtabline')
            end, 100)
        end
    end

    vim.api.nvim_buf_set_keymap(buf, 'n', 'q', '', {
        noremap = true,
        silent = true,
        callback = close_image_tab,
        desc = 'Close image tab'
    })

    vim.api.nvim_buf_set_keymap(buf, 'n', '<Esc>', '', {
        noremap = true,
        silent = true,
        callback = close_image_tab,
        desc = 'Close image tab'
    })

    -- Auto-close behavior (optional)
    vim.api.nvim_create_autocmd('TabLeave', {
        buffer = buf,
        callback = function()
            vim.defer_fn(close_image_tab, 100)
        end
    })
    return buf
end

-- Function to display image in the current tab
local function display_image_in_tab(image_path, width, height)
    debug_log("display image in tab")
    if not check_imgcat() then
        debug_log("failed to find imgcat")
        return
    end

    -- Build the command
    local expanded_script_path = vim.fn.expand(IMGCAT_SCRIPT)
    local cmd = string.format('lua "%s"', expanded_script_path)
    debug_log("Displaying image " .. expanded_script_path)
    debug_log("Imgcat path " .. IMGCAT_SCRIPT)

    -- Calculate appropriate dimensions if not provided
    if not width or not height then
        local term_width = vim.o.columns
        local term_height = vim.o.lines - 8  -- Leave space for info text and tab bar

        width = width or tostring(math.floor(term_width * 0.9))
        height = height or tostring(math.floor(term_height * 0.8))
    end

    cmd = cmd .. ' "' .. image_path .. '"'

    -- Position cursor at the end of the info text to place image there
    vim.api.nvim_win_set_cursor(0, {2, 0})  -- Line 12 (after our info text)

    -- Execute the command to display the image
    vim.fn.system(cmd)

    vim.defer_fn(function()
        debug_log("executing imgcat")
        require('imgcat').main({image_path})
    end, 100)
end

-- Main function to show image in a new tab
function M.show_image(image_path, options)
    options = options or {}

    debug_log("Loading image: " .. image_path)
    -- Check if image file exists
    if vim.fn.filereadable(image_path) == 0 then
        vim.notify('Image file not found: ' .. image_path, vim.log.levels.ERROR)
        return
    end

    -- Create the image tab
    local buf = create_image_tab(image_path)

    display_image_in_tab(image_path)
    -- Display the image after a short delay to ensure tab is ready
end

local function parse_iterm_cell_size(out)
    if not out or out == "" then return nil, nil end

    -- iTerm2 response format: ESC ] 1337 ; ReportCellSize=Height;Width;Scale BEL
    -- Also accepts manually stripped output like Height;Width;Scale.
    local h, w, s = out:match("ReportCellSize=([%d%.]+);([%d%.]+);([%d%.]+)")
    if not h or not w then
        h, w, s = out:match("^%s*([%d%.]+);([%d%.]+);([%d%.]+)")
    end

    if s then s = tonumber(s) else s = 1 end
    if h and w then return tonumber(w)*s, tonumber(h)*s end
    return nil, nil
end

-- Returns terminal cell size in pixels as (cell_w, cell_h).
-- Tries iTerm2 ReportCellSize, then tmux, then falls back to 8x16.
local function get_cell_px_size()
    -- In tmux, prefer the client cell size directly and avoid sending iTerm
    -- ReportCellSize probes through the terminal multiplexer.
    if os.getenv('TMUX') then
        local h = io.popen("tmux display-message -p '#{client_cell_width} #{client_cell_height}' 2>/dev/null")
        if h then
            local out = h:read('*a')
            h:close()
            local cw, ch = out:match('(%d+) (%d+)')
            if cw and ch then return tonumber(cw), tonumber(ch), "tmux" end
        end
    end

    -- 1. iTerm2 ReportCellSize.
    local cell_w, cell_h
    local autocmd_id
    local ok, err = pcall(function()
        autocmd_id = vim.api.nvim_create_autocmd('TermResponse', {
            callback = function(args)
                local out = ((args.data or {}).sequence or vim.v.termresponse or '')
                debug_log(string.format("ReportCellSize response: %q", out))

                local cw, ch = parse_iterm_cell_size(out)
                if cw and ch then
                    cell_w, cell_h = cw, ch
                    pcall(vim.api.nvim_del_autocmd, autocmd_id)
                end
            end,
        })

        io.stdout:write("\027]1337;ReportCellSize\a")
        io.stdout:flush()
        vim.wait(500, function() return cell_w ~= nil end, 10)
    end)

    if autocmd_id and not cell_w then
        pcall(vim.api.nvim_del_autocmd, autocmd_id)
    end
    if not ok then
        debug_log("ReportCellSize probe failed: " .. tostring(err))
    elseif not cell_w then
        debug_log("ReportCellSize probe timed out")
    end
    if ok and cell_w and cell_h then
        return cell_w, cell_h, "iterm2"
    end

    -- 2. Fallback.
    return 8, 16, "fallback"
end

-- Cache cell size so we only query once per session
local _cell_px_w, _cell_px_h

local function cell_px_size()
    if not _cell_px_w then
        local cell_w, cell_h, source = get_cell_px_size()
        debug_log(string.format("cell pixel size: %dx%d (%s)", cell_w, cell_h, source))
        if source ~= "fallback" then
            _cell_px_w, _cell_px_h = cell_w, cell_h
        else
            return cell_w, cell_h
        end
    end
    return _cell_px_w, _cell_px_h
end

local function be16(data, offset)
    local b1, b2 = data:byte(offset, offset + 1)
    if not b1 or not b2 then return nil end
    return b1 * 256 + b2
end

local function be32(data, offset)
    local b1, b2, b3, b4 = data:byte(offset, offset + 3)
    if not b1 or not b2 or not b3 or not b4 then return nil end
    return ((b1 * 256 + b2) * 256 + b3) * 256 + b4
end

local function le16(data, offset)
    local b1, b2 = data:byte(offset, offset + 1)
    if not b1 or not b2 then return nil end
    return b1 + b2 * 256
end

local function le24(data, offset)
    local b1, b2, b3 = data:byte(offset, offset + 2)
    if not b1 or not b2 or not b3 then return nil end
    return b1 + b2 * 256 + b3 * 65536
end

local function jpeg_pixel_size(data)
    if data:sub(1, 2) ~= "\255\216" then return nil, nil end

    local pos = 3
    while pos + 8 <= #data do
        while data:byte(pos) == 0xFF do
            pos = pos + 1
        end

        local marker = data:byte(pos)
        if not marker then return nil, nil end
        pos = pos + 1

        if marker == 0xD9 or marker == 0xDA then
            return nil, nil
        elseif marker == 0x01 or (marker >= 0xD0 and marker <= 0xD8) then
            -- Standalone markers have no segment payload.
        else
            local length = be16(data, pos)
            if not length or length < 2 or pos + length - 1 > #data then return nil, nil end

            local is_sof = marker == 0xC0 or marker == 0xC1 or marker == 0xC2 or
                marker == 0xC3 or marker == 0xC5 or marker == 0xC6 or
                marker == 0xC7 or marker == 0xC9 or marker == 0xCA or
                marker == 0xCB or marker == 0xCD or marker == 0xCE or
                marker == 0xCF
            if is_sof then
                return be16(data, pos + 5), be16(data, pos + 3)
            end

            pos = pos + length
        end
    end

    return nil, nil
end

local function webp_pixel_size(data)
    if data:sub(1, 4) ~= "RIFF" or data:sub(9, 12) ~= "WEBP" then return nil, nil end

    local chunk = data:sub(13, 16)
    if chunk == "VP8X" and #data >= 30 then
        return le24(data, 25) + 1, le24(data, 28) + 1
    elseif chunk == "VP8 " and #data >= 30 and data:sub(24, 26) == "\157\001\042" then
        local w = le16(data, 27)
        local h = le16(data, 29)
        if w and h then return w % 16384, h % 16384 end
    elseif chunk == "VP8L" and #data >= 25 and data:byte(21) == 0x2F then
        local bits = le16(data, 22) + (le16(data, 24) or 0) * 65536
        return (bits % 16384) + 1, (math.floor(bits / 16384) % 16384) + 1
    end

    return nil, nil
end

local function image_pixel_size_from_header(image_path)
    local file = io.open(image_path, "rb")
    if not file then return nil, nil end
    local data = file:read(1024 * 1024) or ""
    file:close()

    if data:sub(1, 8) == "\137PNG\r\n\026\n" and data:sub(13, 16) == "IHDR" then
        return be32(data, 17), be32(data, 21)
    elseif data:sub(1, 6) == "GIF87a" or data:sub(1, 6) == "GIF89a" then
        return le16(data, 7), le16(data, 9)
    elseif data:sub(1, 2) == "\255\216" then
        return jpeg_pixel_size(data)
    elseif data:sub(1, 4) == "RIFF" and data:sub(9, 12) == "WEBP" then
        return webp_pixel_size(data)
    end

    return nil, nil
end

local function image_pixel_size_with_sips(image_path)
    local handle = io.popen(string.format('sips -g pixelWidth -g pixelHeight %s 2>/dev/null', vim.fn.shellescape(image_path)))
    if not handle then return nil, nil end
    local out = handle:read("*a")
    handle:close()
    local px_w = tonumber(out:match("pixelWidth: (%d+)"))
    local px_h = tonumber(out:match("pixelHeight: (%d+)"))
    return px_w, px_h
end

local function image_pixel_size_with_identify(image_path)
    local escaped = vim.fn.shellescape(image_path)
    local commands = {
        string.format("identify -format '%%w %%h' %s 2>/dev/null", escaped),
        string.format("magick identify -format '%%w %%h' %s 2>/dev/null", escaped),
    }

    for _, cmd in ipairs(commands) do
        local handle = io.popen(cmd)
        if handle then
            local out = handle:read("*a")
            handle:close()
            local px_w, px_h = out:match("(%d+)%s+(%d+)")
            if px_w and px_h then return tonumber(px_w), tonumber(px_h) end
        end
    end

    return nil, nil
end

-- Returns image dimensions in character cells.
-- Uses small header parsing first, then external tools as fallbacks.
local function image_size_in_cells(image_path)
    local px_w, px_h = image_pixel_size_from_header(image_path)
    if not px_w or not px_h then
        px_w, px_h = image_pixel_size_with_sips(image_path)
    end
    if not px_w or not px_h then
        px_w, px_h = image_pixel_size_with_identify(image_path)
    end
    if not px_w or not px_h then return nil, nil end
    local cw, ch = cell_px_size()
    return math.ceil(px_w / cw), math.ceil(px_h / ch)
end

-- Function to show image in a floating popup using snacks.nvim
function M.show_image_popup(image_path, options)
    options = options or {}

    debug_log("Loading image in popup: " .. image_path)

    if vim.fn.filereadable(image_path) == 0 then
        vim.notify('Image file not found: ' .. image_path, vim.log.levels.ERROR)
        return
    end

    if not check_imgcat() then return end

    local filename = vim.fn.fnamemodify(image_path, ':t')

    -- Gather sizing info
    local cell_w, cell_h = cell_px_size()
    local img_w, img_h = image_size_in_cells(image_path)
    local max_w = math.floor(vim.o.columns * 0.92)
    local max_h = math.floor(vim.o.lines * 0.92)

    local win_w, win_h
    if img_w and img_h then
        local scale = math.min(1.0, max_w / img_w, max_h / img_h)
        win_w = math.max(20, math.floor(img_w * scale))
        win_h = math.max(6,  math.floor(img_h * scale))
    else
        win_w = math.floor(vim.o.columns * 0.8)
        win_h = math.floor(vim.o.lines * 0.8)
    end

    local snacks_win = Snacks.win({
        border = 'rounded',
        width = win_w,
        height = win_h,
        title = ' ' .. filename .. ' ',
        title_pos = 'center',
        bo = {
            buftype = 'nofile',
            bufhidden = 'wipe',
            swapfile = false,
            filetype = 'image_viewer',
        },
        keys = {
            q = 'close',
            ['<Esc>'] = 'close',
        },
    })

    vim.defer_fn(function()
        require('imgcat').main({ image_path })

        vim.notify(
            string.format(
                'image: %s x %s cells  |  window: %d x %d cells  |  cell: %d x %d px',
                img_w or '?', img_h or '?', win_w, win_h, cell_w, cell_h
            ),
            vim.log.levels.INFO,
            { title = 'icat' }
        )
    end, 100)
end

function M.open_file_browser_entry()
    local path
    if vim.bo.filetype == "oil" then
        path = oil_cursor_path()
    elseif vim.bo.filetype == "netrw" then
        path = netrw_cursor_path()
    else
        return false
    end

    if is_image_file(path) then
        M.show_image_popup(path)
        return true
    end

    return open_regular_file_browser_entry()
end

local function setup_file_browser_mapping(opts)
    opts = opts or {}
    if opts.enabled == false then return end

    local key = opts.key or "<CR>"
    local group = vim.api.nvim_create_augroup("NvimIcatFileBrowser", { clear = true })
    vim.api.nvim_create_autocmd("FileType", {
        group = group,
        pattern = { "oil", "netrw" },
        callback = function(args)
            vim.schedule(function()
                if not vim.api.nvim_buf_is_valid(args.buf) then return end
                vim.keymap.set("n", key, function()
                    M.open_file_browser_entry()
                end, {
                    buffer = args.buf,
                    desc = "Open image in icat popup",
                    silent = true,
                })
            end)
        end,
    })
end

-- Setup function for configuration
function M.setup(opts)
    opts = opts or {}
    debug_file_handle = nil

    -- Allow user to override imgcat script path if needed
    if opts.imgcat_path then
        IMGCAT_SCRIPT = vim.fn.expand(opts.imgcat_path)
    end
    debug_log("imgcat script path: " .. IMGCAT_SCRIPT)
    if not vim.g.nvim_icat_startup_tty then
        vim.g.nvim_icat_startup_tty = imgcat_tty_name()
        if vim.g.nvim_icat_startup_tty then
            debug_log("cached startup tty: " .. vim.g.nvim_icat_startup_tty)
        end
    end
    if not vim.g.nvim_icat_tty then
        vim.g.nvim_icat_tty = vim.g.nvim_icat_startup_tty
    end

    -- Create user commands
    vim.api.nvim_create_user_command('IcatShow', function(args)
        M.show_image(args.args)
    end, {
        nargs = '?',
        complete = 'file',
        desc = 'Show image in a new tab'
    })

    vim.api.nvim_create_user_command('IcatShowPop', function(args)
        M.show_image_popup(args.args)
    end, {
        nargs = '?',
        complete = 'file',
        desc = 'Show image in a floating popup'
    })

    vim.api.nvim_create_user_command('IcatTty', function()
        M.notify_tty()
    end, {
        desc = 'Show nvim-icat tty diagnostics'
    })

    setup_file_browser_mapping(opts.file_browser)

    debug_log("setup complete")
end

return M
