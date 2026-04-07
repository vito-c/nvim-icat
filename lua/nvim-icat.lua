-- Image Popup Plugin for Neovim
-- Usage: :lua require('image_popup').show_image('/path/to/image.png')

local M = {}
local DEBUG_ENABLED = os.getenv("IMGCAT_DEBUG") == "1" or false
local DEBUG_FILE = "debug-plugin.txt"
local debug_file_handle = nil

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

    -- 2. tmux: #{client_cell_width} / #{client_cell_height}
    if os.getenv('TMUX') then
        local h = io.popen("tmux display-message -p '#{client_cell_width} #{client_cell_height}' 2>/dev/null")
        if h then
            local out = h:read('*a')
            h:close()
            local cw, ch = out:match('(%d+) (%d+)')
            if cw and ch then return tonumber(cw), tonumber(ch), "tmux" end
        end
    end

    -- 3. Fallback.
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

-- Returns image dimensions in character cells using sips (macOS built-in).
-- Falls back to nil if sips is unavailable or the image can't be read.
local function image_size_in_cells(image_path)
    local handle = io.popen(string.format('sips -g pixelWidth -g pixelHeight "%s" 2>/dev/null', image_path))
    if not handle then return nil, nil end
    local out = handle:read("*a")
    handle:close()
    local px_w = tonumber(out:match("pixelWidth: (%d+)"))
    local px_h = tonumber(out:match("pixelHeight: (%d+)"))
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

-- Setup function for configuration
function M.setup(opts)
    opts = opts or {}
    debug_file_handle = nil

    -- Allow user to override imgcat script path if needed
    if opts.imgcat_path then
        IMGCAT_SCRIPT = vim.fn.expand(opts.imgcat_path)
    end
    debug_log("imgcat script path: " .. IMGCAT_SCRIPT)

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

    debug_log("setup complete")
end

return M
