vim.opt.runtimepath:prepend(vim.fn.getcwd())

local function fail(message)
    error(message, 2)
end

local function assert_eq(actual, expected, message)
    if actual ~= expected then
        fail(string.format("%s\nexpected: %s\nactual:   %s", message or "assertion failed", vim.inspect(expected), vim.inspect(actual)))
    end
end

local function assert_match(value, pattern, message)
    if not tostring(value):match(pattern) then
        fail(string.format("%s\npattern: %s\nvalue:   %s", message or "pattern assertion failed", pattern, tostring(value)))
    end
end

local calls = {
    imgcat = {},
    imgcat_win = {},
    notifications = {},
    oil_select = 0,
    snacks_win = nil,
    system = nil,
    popen = {},
    forbidden_open = nil,
}

local original = {
    defer_fn = vim.defer_fn,
    filereadable = vim.fn.filereadable,
    notify = vim.notify,
    system = vim.fn.system,
    wait = vim.wait,
    open = io.open,
    popen = io.popen,
    write = io.write,
    stdout = io.stdout,
}

vim.defer_fn = function(fn)
    fn()
end

vim.fn.filereadable = function()
    return 1
end

vim.notify = function(message, level, opts)
    calls.notifications[#calls.notifications + 1] = {
        message = message,
        level = level,
        opts = opts,
    }
end

vim.fn.system = function(cmd)
    calls.system = cmd
    return ""
end

vim.wait = function()
    return false
end

io.stdout = {
    write = function() end,
    flush = function() end,
}

local function pipe(contents)
    return {
        read = function()
            return contents
        end,
        close = function() end,
    }
end

io.popen = function(cmd)
    calls.popen[#calls.popen + 1] = cmd

    if cmd:match("^sips ") then
        return pipe("pixelWidth: 160\npixelHeight: 80\n")
    elseif cmd == "tty 2>/dev/null" then
        return pipe("/dev/ttys.imgcat\n")
    elseif cmd:match("^ps %-o tty= %-p %d+ 2>/dev/null$") then
        return pipe("ttys.nvim\n")
    elseif cmd:match("^%[ %-t 0 %]") then
        return pipe("terminal\n")
    elseif cmd:match("^which base64") then
        return pipe("/usr/bin/base64\n")
    end

    return nil
end

io.open = function(path, mode)
    if path == "debug.txt" then
        return {
            write = function() end,
            flush = function() end,
            close = function() end,
        }
    end

    return original.open(path, mode)
end

package.loaded.imgcat = {
    main = function(args)
        calls.imgcat[#calls.imgcat + 1] = args
        calls.imgcat_win[#calls.imgcat_win + 1] = vim.api.nvim_get_current_win()
    end,
}

Snacks = {
    win = function(opts)
        local buf = vim.api.nvim_create_buf(false, true)
        local win = vim.api.nvim_open_win(buf, true, {
            relative = "editor",
            row = 0,
            col = 0,
            width = opts.width,
            height = opts.height,
            style = "minimal",
            border = opts.border,
        })

        calls.snacks_win = opts
        return { buf = buf, opts = opts, win = win }
    end,
}

local icat = require("nvim-icat")
icat.setup({
    file_browser = {
        enabled = false,
    },
})

vim.cmd("IcatTty")
local tty_notification = calls.notifications[#calls.notifications]
assert_match(tty_notification.message, "imgcat tty: /dev/ttys%.imgcat", "IcatTty should report the tty imgcat would use")
assert_match(tty_notification.message, "nvim process tty: /dev/ttys%.nvim", "IcatTty should report the Neovim process tty")
assert_match(tty_notification.message, "startup tty: /dev/ttys%.imgcat", "IcatTty should report the startup tty cache")
assert_match(tty_notification.message, "vim%.g%.nvim_icat_tty: /dev/ttys%.imgcat", "IcatTty should report configured tty state")
assert_eq(tty_notification.opts.title, "icat tty", "IcatTty should use a tty diagnostic notification title")

local image_path = "/tmp/nvim-icat-test-image.png"
vim.fn.writefile({ "fake image bytes" }, image_path, "b")

vim.cmd("IcatShow " .. vim.fn.fnameescape(image_path))
assert_match(vim.api.nvim_buf_get_name(0), "Image: nvim%-icat%-test%-image%.png$", "IcatShow should create an image buffer")
assert_eq(vim.bo.buftype, "nofile", "IcatShow should create a nofile buffer")
assert_eq(vim.bo.filetype, "image_viewer", "IcatShow should mark the buffer as an image viewer")
assert_eq(vim.api.nvim_buf_get_lines(0, 0, 1, false)[1], "  Path: " .. image_path, "IcatShow should record the image path")
assert_match(calls.system, "imgcat%.lua", "IcatShow should invoke the imgcat script")
assert_match(calls.system, "nvim%-icat%-test%-image%.png", "IcatShow should pass the image path to imgcat")
assert_eq(calls.imgcat[#calls.imgcat][1], image_path, "IcatShow should render the image through imgcat")

local oil_buf = vim.api.nvim_create_buf(false, true)
vim.api.nvim_set_current_buf(oil_buf)
vim.bo[oil_buf].filetype = "oil"
package.loaded.oil = {
    get_cursor_entry = function()
        return { type = "file", name = "photo.png" }
    end,
    get_current_dir = function()
        return "/tmp"
    end,
}
calls.imgcat = {}
calls.snacks_win = nil
assert_eq(icat.open_file_browser_entry(), true, "oil image entries should open in the icat popup")
assert_eq(calls.imgcat[#calls.imgcat][1], "/tmp/photo.png", "oil image entries should render the selected image")

local oil_text_buf = vim.api.nvim_create_buf(false, true)
vim.api.nvim_set_current_buf(oil_text_buf)
vim.bo[oil_text_buf].filetype = "oil"
package.loaded.oil = {
    get_cursor_entry = function()
        return { type = "file", name = "notes.txt" }
    end,
    get_current_dir = function()
        return "/tmp"
    end,
}
package.loaded["oil.actions"] = {
    select = {
        callback = function()
            calls.oil_select = calls.oil_select + 1
        end,
    },
}
assert_eq(icat.open_file_browser_entry(), true, "oil non-image entries should fall through to oil select")
assert_eq(calls.oil_select, 1, "oil non-image entries should call oil select")

vim.cmd("tabprevious")
calls.imgcat = {}
calls.imgcat_win = {}
calls.snacks_win = nil

vim.cmd("IcatShowPop " .. vim.fn.fnameescape(image_path))
assert_eq(calls.snacks_win.border, "rounded", "IcatShowPop should create a rounded popup")
assert_eq(calls.snacks_win.title, " nvim-icat-test-image.png ", "IcatShowPop should use the image filename as the title")
assert_eq(calls.snacks_win.bo.filetype, "image_viewer", "IcatShowPop should mark the popup buffer as an image viewer")
assert_eq(calls.snacks_win.width, 20, "IcatShowPop should size the popup from image dimensions")
assert_eq(calls.snacks_win.height, 6, "IcatShowPop should enforce the minimum popup height")
assert_eq(calls.imgcat[#calls.imgcat][1], image_path, "IcatShowPop should render the image through imgcat")
assert_eq(calls.imgcat_win[#calls.imgcat_win], vim.api.nvim_get_current_win(), "IcatShowPop should render inside the popup window")

local original_popen = io.popen
io.popen = function(cmd)
    calls.popen[#calls.popen + 1] = cmd

    if cmd:match("^sips ") then
        return pipe("not image metadata\n")
    elseif cmd:match("^identify %-format ") then
        return pipe("240 96")
    elseif cmd:match("^%[ %-t 0 %]") then
        return pipe("terminal\n")
    elseif cmd:match("^which base64") then
        return pipe("/usr/bin/base64\n")
    end

    return nil
end
calls.imgcat = {}
calls.imgcat_win = {}
calls.snacks_win = nil
vim.cmd("IcatShowPop " .. vim.fn.fnameescape(image_path))
assert_eq(calls.snacks_win.width, 30, "IcatShowPop should fall back to ImageMagick identify when sips cannot read dimensions")
assert_eq(calls.snacks_win.height, 6, "IcatShowPop should apply minimum popup height after identify sizing")
io.popen = original_popen

local png_header = string.char(137, 80, 78, 71, 13, 10, 26, 10, 0, 0, 0, 13) ..
    "IHDR" .. string.char(0, 0, 1, 64, 0, 0, 0, 160, 8, 2, 0, 0, 0)
local png_file = original.open(image_path, "wb")
png_file:write(png_header)
png_file:close()
io.popen = function(cmd)
    calls.popen[#calls.popen + 1] = cmd

    if cmd:match("^sips ") then
        return pipe("not image metadata\n")
    elseif cmd:match("^identify %-format ") or cmd:match("^magick identify %-format ") then
        return nil
    elseif cmd:match("^%[ %-t 0 %]") then
        return pipe("terminal\n")
    elseif cmd:match("^which base64") then
        return pipe("/usr/bin/base64\n")
    end

    return nil
end
calls.imgcat = {}
calls.imgcat_win = {}
calls.snacks_win = nil
vim.cmd("IcatShowPop " .. vim.fn.fnameescape(image_path))
assert_eq(calls.snacks_win.width, 40, "IcatShowPop should size common images from header metadata before external tools")
assert_eq(calls.snacks_win.height, 10, "IcatShowPop should use header metadata height")
io.popen = original_popen

vim.fn.writefile({ "fake image bytes" }, image_path, "b")
io.popen = function(cmd)
    calls.popen[#calls.popen + 1] = cmd

    if cmd:match("^sips ") then
        return pipe("not image metadata\n")
    elseif cmd:match("^%[ %-t 0 %]") then
        return pipe("terminal\n")
    elseif cmd:match("^which base64") then
        return pipe("/usr/bin/base64\n")
    end

    return nil
end
calls.imgcat = {}
calls.imgcat_win = {}
calls.snacks_win = nil
vim.cmd("IcatShowPop " .. vim.fn.fnameescape(image_path))
assert_eq(calls.snacks_win.width, math.floor(vim.o.columns * 0.8), "IcatShowPop should fall back to editor width when image dimensions are unavailable")
assert_eq(calls.snacks_win.height, math.floor(vim.o.lines * 0.8), "IcatShowPop should fall back to editor height when image dimensions are unavailable")
io.popen = original_popen

package.loaded.imgcat = nil
local rendered = {}
io.write = function(s)
    rendered[#rendered + 1] = s
end
local real_imgcat = require("imgcat")
real_imgcat.disable_debug()
calls.snacks_win = nil

vim.cmd("IcatShowPop " .. vim.fn.fnameescape(image_path))
local rendered_output = table.concat(rendered)
assert_eq(calls.snacks_win.title, " nvim-icat-test-image.png ", "IcatShowPop should create a popup before rendering the image")
assert_match(rendered_output, "\027%]1337;MultipartFile=inline=1", "IcatShowPop should emit the inline image header")
assert_match(rendered_output, "\027%]1337;FilePart=", "IcatShowPop should emit image payload chunks")
assert_match(rendered_output, "\027%]1337;FileEnd\007", "IcatShowPop should terminate the inline image")

rendered = {}
local tty_rendered = {}
io.popen = function(cmd)
    calls.popen[#calls.popen + 1] = cmd

    if cmd == "tty 2>/dev/null" then
        return pipe("not a tty\n")
    elseif cmd:match("^sips ") then
        return pipe("pixelWidth: 160\npixelHeight: 80\n")
    elseif cmd:match("^%[ %-t 0 %]") then
        return pipe("terminal\n")
    elseif cmd:match("^which base64") then
        return pipe("/usr/bin/base64\n")
    end

    return nil
end
io.open = function(path, mode)
    if path == "not a tty" then
        calls.forbidden_open = path
        return nil
    elseif path == "/dev/ttys.imgcat" then
        return {
            write = function(_, s)
                tty_rendered[#tty_rendered + 1] = s
            end,
            flush = function() end,
            close = function() end,
        }
    elseif path == "debug.txt" then
        return {
            write = function() end,
            flush = function() end,
            close = function() end,
        }
    end

    return original.open(path, mode)
end
vim.cmd("IcatShowPop " .. vim.fn.fnameescape(image_path))
assert_eq(calls.forbidden_open, nil, "imgcat should ignore invalid tty output")
assert_match(table.concat(tty_rendered), "\027%]1337;MultipartFile=inline=1", "imgcat should fall back to the cached startup tty when render-time tty is invalid")

vim.defer_fn = original.defer_fn
vim.fn.filereadable = original.filereadable
vim.notify = original.notify
vim.fn.system = original.system
vim.wait = original.wait
io.open = original.open
io.popen = original.popen
io.write = original.write
io.stdout = original.stdout
os.remove(image_path)

print("nvim-icat tests passed")
