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
    vim.api.nvim_create_user_command('ImageShow', function(args)
        M.show_image(args.args)
    end, {
        nargs = '?',
        complete = 'file',
        desc = 'Show image in popup'
    })

    debug_log("setup complete")
end

return M
