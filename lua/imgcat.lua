#!/usr/bin/env lua

-- Module table to export functions
local M = {}

-- Global variables
local IMGCAT_BASE64_VERSION = nil
local has_image_displayed = false

-- Debug logging variables
local DEBUG_ENABLED = true -- os.getenv("IMGCAT_DEBUG") == "1" or false
local DEBUG_FILE = "debug.txt"
local debug_file_handle = nil

-- Debug logging function
local function debug_log(message)
    if not DEBUG_ENABLED then return end

    if not debug_file_handle then
        debug_file_handle = io.open(DEBUG_FILE, "a")
        if debug_file_handle then
            debug_file_handle:write(string.format("[%s] === DEBUG SESSION START ===\n", os.date("%Y-%m-%d %H:%M:%S")))
        else
            -- Fallback to stderr if file can't be opened
            io.stderr:write("DEBUG: Failed to open debug file: " .. DEBUG_FILE .. "\n")
            return
        end
    end

    if debug_file_handle then
        debug_file_handle:write(string.format("[%s] %s\n", os.date("%Y-%m-%d %H:%M:%S"), message))
        debug_file_handle:flush()
    end
end

-- Function to enable debug logging programmatically
function M.enable_debug(filename)
    DEBUG_ENABLED = true
    if filename then
        DEBUG_FILE = filename
    end
    debug_log("Debug logging enabled")
end

-- Function to disable debug logging
function M.disable_debug()
    debug_log("Debug logging disabled")
    DEBUG_ENABLED = false
    if debug_file_handle then
        debug_file_handle:close()
        debug_file_handle = nil
    end
end

-- Try to load base64 library, fallback to simple implementation
local base64_lib = nil
local has_base64_lib = pcall(function() base64_lib = require('base64') end)
debug_log("Base64 library check: " .. (has_base64_lib and "found" or "not found"))

-- Simple base64 encoding fallback
local function b64_encode_simple(data)
    debug_log("Using simple base64 encoding for " .. #data .. " bytes")
    local b64chars = 'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/'
    local result = ''
    local pad = 2 - ((#data - 1) % 3)

    data = data .. string.rep('\0', pad)

    for i = 1, #data, 3 do
        local n = string.byte(data, i) * 65536 + string.byte(data, i + 1) * 256 + string.byte(data, i + 2)
        result = result .. b64chars:sub(math.floor(n / 262144) + 1, math.floor(n / 262144) + 1)
        result = result .. b64chars:sub(math.floor(n / 4096) % 64 + 1, math.floor(n / 4096) % 64 + 1)
        result = result .. b64chars:sub(math.floor(n / 64) % 64 + 1, math.floor(n / 64) % 64 + 1)
        result = result .. b64chars:sub(n % 64 + 1, n % 64 + 1)
    end

    return result:sub(1, #result - pad) .. string.rep('=', pad)
end

local function get_tty_name()
    -- Leverage tty, which reads the terminal name
    debug_log("get tty name")
    local handle = io.popen("tty 2>/dev/null")
    if not handle then
        debug_log("Could not find tty")
        return nil
    end
    debug_log("Found a handle ")
    local result = handle:read("*a")
    debug_log("read handle ")
    handle:close()
    debug_log("closed handle " .. result)
    result = vim.fn.trim(result)
    debug_log("Found tty: " .. result)
    if result == "" then return nil end
    return result
end

local function make_writer()
    debug_log("Setting up TTY writer")
    local tty_name = get_tty_name()
    local tty = nil
    if tty_name then
        debug_log("TTY io writer " .. tty_name)
        tty = io.open(tty_name, "w")
    end
    if tty then
        debug_log("TTY writer: using /dev/tty")
        return function(s)
            tty:write(s)
            tty:flush()
        end, tty
    else
        debug_log("TTY writer: fallback to io.write")
        return function(s)
            io.write(s)
        end, nil
    end
end

local tty_write, tty_handle = nil, nil

-- Helper function to check if a command exists
local function command_exists(cmd)
    debug_log("Checking if command exists: " .. cmd)
    local handle = io.popen("which " .. cmd .. " 2>/dev/null")
    if not handle then
        debug_log("Command check failed: " .. cmd)
        return false
    end
    local result = handle:read("*a")
    handle:close()
    local exists = result ~= ""
    debug_log("Command " .. cmd .. ": " .. (exists and "found" or "not found"))
    return exists
end

-- tmux requires unrecognized OSC sequences to be wrapped with DCS tmux;
-- <sequence> ST, and for all ESCs in <sequence> to be replaced with ESC ESC.
local function print_osc()
    local term = os.getenv("TERM") or ""
    debug_log("Terminal type: " .. term)
    if string.match(term, "^screen") or string.match(term, "^tmux") then
        debug_log("Using tmux OSC wrapper")
        tty_write("\027Ptmux;\027\027]")
    else
        debug_log("Using standard OSC")
        tty_write("\027]")
    end
end

local function print_st()
    local term = os.getenv("TERM") or ""
    if string.match(term, "^screen") or string.match(term, "^tmux") then
        debug_log("Using tmux ST wrapper")
        tty_write("\007\027\\")
    else
        debug_log("Using standard ST")
        tty_write("\007")
    end
end

local function load_version()
    if not IMGCAT_BASE64_VERSION then
        debug_log("Loading base64 version info")
        local handle = io.popen("base64 --version 2>&1")
        if handle then
            IMGCAT_BASE64_VERSION = handle:read("*a") or ""
            handle:close()
            debug_log("Base64 version: " .. IMGCAT_BASE64_VERSION:gsub("\n", " "))
        else
            IMGCAT_BASE64_VERSION = ""
            debug_log("Failed to get base64 version")
        end
    end
end

local function b64_encode(data)
    debug_log("Encoding " .. #data .. " bytes to base64")

    -- Use base64 library if available
    if has_base64_lib and base64_lib.encode then
        debug_log("Using base64 library for encoding")
        return base64_lib.encode(data)
    end

    -- Use system base64 command via temporary file (avoids shell escaping)
    local temp_file = os.tmpname()
    debug_log("Using temporary file for base64 encoding: " .. temp_file)
    local file = io.open(temp_file, "wb")
    if file then
        file:write(data)
        file:close()

        load_version()
        local cmd
        if string.match(IMGCAT_BASE64_VERSION, "GNU") then
            cmd = "base64 -w0 < " .. temp_file
            debug_log("Using GNU base64 command")
        else
            cmd = "base64 < " .. temp_file
            debug_log("Using standard base64 command")
        end

        local handle = io.popen(cmd)
        if handle then
            local result = handle:read("*a")
            handle:close()
            os.remove(temp_file)
            if result then
                debug_log("Base64 encoding successful, output length: " .. #result)
                return string.gsub(result, "\n", "")
            end
        end
        os.remove(temp_file)
    end

    -- Fallback to simple base64 implementation only if system command fails
    debug_log("Falling back to simple base64 implementation")
    return b64_encode_simple(data)
end

local function b64_decode(data)
    debug_log("Decoding base64 data, length: " .. #data)

    -- Use base64 library if available
    if has_base64_lib and base64_lib.decode then
        debug_log("Using base64 library for decoding")
        return base64_lib.decode(data)
    end

    -- Use system command via temporary file (avoids shell escaping)
    local temp_file = os.tmpname()
    debug_log("Using temporary file for base64 decoding: " .. temp_file)
    local file = io.open(temp_file, "w")
    if file then
        file:write(data)
        file:close()

        load_version()
        local base64arg
        if string.match(IMGCAT_BASE64_VERSION, "fourmilab") then
            base64arg = "-d"
            debug_log("Using fourmilab base64 decoder")
        elseif string.match(IMGCAT_BASE64_VERSION, "GNU") then
            base64arg = "-di"
            debug_log("Using GNU base64 decoder")
        else
            base64arg = "-D"
            debug_log("Using standard base64 decoder")
        end

        local cmd = "base64 " .. base64arg .. " < " .. temp_file
        local handle = io.popen(cmd)
        if handle then
            local result = handle:read("*a")
            handle:close()
            os.remove(temp_file)
            debug_log("Base64 decoding successful")
            return result or ""
        end
        os.remove(temp_file)
    end

    -- Fallback to estimation if system command fails
    debug_log("Base64 decoding failed, using size estimation")
    return string.rep("x", math.floor(string.len(data) * 3 / 4))
end

local function print_image(filename, inline, base64contents, print_filename, width, height, preserve_aspect_ratio, file_type, legacy)
    debug_log("Printing image: " .. (filename or "stdin"))
    debug_log("Parameters: inline=" .. inline .. ", legacy=" .. legacy .. ", width=" .. (width or "auto") .. ", height=" .. (height or "auto"))

    print_osc()
    tty_write("1337;")

    if legacy == 1 then
        debug_log("Using legacy protocol")
        tty_write("File")
    else
        debug_log("Using multipart protocol")
        tty_write("MultipartFile")
    end

    tty_write(string.format("=inline=%s", inline))

    local decoded = b64_decode(base64contents)
    local size = string.len(decoded)
    debug_log("Image size: " .. size .. " bytes")
    tty_write(string.format(";size=%d", size))

    if filename and filename ~= "" then
        debug_log("Setting filename: " .. filename)
        tty_write(string.format(";name=%s", b64_encode(filename)))
    end

    if width and width ~= "" then
        debug_log("Setting width: " .. width)
        tty_write(string.format(";width=%s", width))
    end

    if height and height ~= "" then
        debug_log("Setting height: " .. height)
        tty_write(string.format(";height=%s", height))
    end

    if preserve_aspect_ratio and preserve_aspect_ratio ~= "" then
        debug_log("Setting preserve aspect ratio: " .. preserve_aspect_ratio)
        tty_write(string.format(";preserveAspectRatio=%s", preserve_aspect_ratio))
    end

    if file_type and file_type ~= "" then
        debug_log("Setting file type: " .. file_type)
        tty_write(string.format(";type=%s", file_type))
    end

    if legacy == 1 then
        debug_log("Sending image data in single sequence")
        tty_write(string.format(":%s", base64contents))
        print_st()
    else
        print_st()
        local chunks = 0
        local i = 1
        while i <= string.len(base64contents) do
            local chunk = string.sub(base64contents, i, i + 199)
            print_osc()
            tty_write(string.format("1337;FilePart=%s", chunk))
            print_st()
            i = i + 200
            chunks = chunks + 1
        end
        debug_log("Sent image data in " .. chunks .. " chunks")

        print_osc()
        tty_write("1337;FileEnd")
        print_st()
        debug_log("Sent FileEnd marker")
    end

    tty_write("\n")
    if print_filename == 1 and filename then
        tty_write(filename .. "\n")
        debug_log("Printed filename: " .. filename)
    end
    has_image_displayed = true
    debug_log("Image display completed successfully")
end

-- print_image filename inline base64contents print_filename width height preserve_aspect_ratio file_type legacy
local function print_image_io(filename, inline, base64contents, print_filename, width, height, preserve_aspect_ratio, file_type, legacy)
    debug_log("Printing image via io: " .. (filename or "stdin"))

    -- Send metadata to begin transfer
    print_osc()
    io.write("1337;")

    if legacy == 1 then
        debug_log("Using legacy protocol (io)")
        io.write("File")
    else
        debug_log("Using multipart protocol (io)")
        io.write("MultipartFile")
    end

    io.write(string.format("=inline=%s", inline))

    -- Calculate size
    local decoded = b64_decode(base64contents)
    local size = string.len(decoded)
    debug_log("Image size (io): " .. size .. " bytes")
    io.write(string.format(";size=%d", size))

    if filename and filename ~= "" then
        io.write(string.format(";name=%s", b64_encode(filename)))
    end

    if width and width ~= "" then
        io.write(string.format(";width=%s", width))
    end

    if height and height ~= "" then
        io.write(string.format(";height=%s", height))
    end

    if preserve_aspect_ratio and preserve_aspect_ratio ~= "" then
        io.write(string.format(";preserveAspectRatio=%s", preserve_aspect_ratio))
    end

    if file_type and file_type ~= "" then
        io.write(string.format(";type=%s", file_type))
    end

    if legacy == 1 then
        io.write(string.format(":%s", base64contents))
        print_st()
    else
        print_st()

        -- Split into 200-byte chunks
        local chunks = 0
        local i = 1
        while i <= string.len(base64contents) do
            local chunk = string.sub(base64contents, i, i + 199)
            print_osc()
            io.write(string.format("1337;FilePart=%s", chunk))
            print_st()
            i = i + 200
            chunks = chunks + 1
        end
        debug_log("Sent image data (io) in " .. chunks .. " chunks")

        -- Indicate completion
        print_osc()
        io.write("1337;FileEnd")
        print_st()
    end

    io.write("\n")
    if print_filename == 1 and filename then
        print(filename)
    end
    has_image_displayed = true
    debug_log("Image display (io) completed successfully")
end

local function error_msg(msg)
    debug_log("ERROR: " .. msg)
    io.stderr:write("ERROR: " .. msg .. "\n")
end

local function errcho(msg)
    debug_log("ERRCHO: " .. msg)
    io.stderr:write(msg .. "\n")
end

local function show_help()
    debug_log("Showing help message")
    errcho("")
    errcho("Usage: imgcat [-p] [-n] [-W width] [-H height] [-r] [-s] [-u] [-t file-type] [-f] filename ...")
    errcho("       cat filename | imgcat [-W width] [-H height] [-r] [-s]")
    errcho("")
    errcho("Display images inline in the iTerm2 using Inline Images Protocol")
    errcho("")
    errcho("Options:")
    errcho("")
    errcho("    -h, --help                      Display help message")
    errcho("    -p, --print                     Enable printing of filename or URL after each image")
    errcho("    -n, --no-print                  Disable printing of filename or URL after each image")
    errcho("    -u, --url                       Interpret following filename arguments as remote URLs")
    errcho("    -f, --file                      Interpret following filename arguments as regular Files")
    errcho("    -t, --type file-type            Provides a type hint")
    errcho("    -r, --preserve-aspect-ratio     When scaling image preserve its original aspect ratio")
    errcho("    -s, --stretch                   Stretch image to specified width and height (this option is opposite to -r)")
    errcho("    -W, --width N                   Set image width to N character cells, pixels or percent (see below)")
    errcho("    -H, --height N                  Set image height to N character cells, pixels or percent (see below)")
    errcho("    -l, --legacy                    Use legacy protocol that sends the whole image in a single control sequence")
    errcho("")
    errcho("    If you don't specify width or height an appropriate value will be chosen automatically.")
    errcho("    The width and height are given as word 'auto' or number N followed by a unit:")
    errcho("        N      character cells")
    errcho("        Npx    pixels")
    errcho("        N%     percent of the session's width or height")
    errcho("        auto   the image's inherent size will be used to determine an appropriate dimension")
    errcho("")
    errcho("    If a type is provided, it is used as a hint to disambiguate.")
    errcho("    The file type can be a mime type like text/markdown, a language name like Java, or a file extension like .c")
    errcho("    The file type can usually be inferred from the extension or its contents. -t is most useful when")
    errcho("    a filename is not available, such as when input comes from a pipe.")
    errcho("")
    errcho("Debug logging:")
    errcho("    Set IMGCAT_DEBUG=1 environment variable to enable debug logging to debug.txt")
    errcho("")
    errcho("Examples:")
    errcho("")
    errcho("    $ lua imgcat.lua -W 250px -H 250px -s avatar.png")
    errcho("    $ cat graph.png | lua imgcat.lua -W 100%")
    errcho("    $ lua imgcat.lua -p -W 500px -u http://host.tld/path/to/image.jpg -W 80 -f image.png")
    errcho("    $ lua imgcat.lua -t application/json config.json")
    errcho("    $ IMGCAT_DEBUG=1 lua imgcat.lua image.png")
    errcho("")
end

local function check_dependency(dep)
    debug_log("Checking dependency: " .. dep)
    if not command_exists(dep) then
        error_msg("missing dependency: can't find " .. dep)
        os.exit(1)
    end
end

local function validate_size_unit(unit)
    debug_log("Validating size unit: " .. unit)
    local valid = string.match(unit, "^%d+p?x?%%?$") or unit == "auto"
    if not valid then
        error_msg("Invalid image sizing unit - '" .. unit .. "'")
        show_help()
        os.exit(1)
    end
end

local function read_file(filename)
    debug_log("Reading file: " .. filename)
    local file = io.open(filename, "rb")
    if not file then
        debug_log("Failed to open file: " .. filename)
        return nil
    end
    local content = file:read("*a")
    file:close()
    debug_log("Successfully read " .. #content .. " bytes from " .. filename)
    return content
end

local function read_url(url)
    debug_log("Reading URL: " .. url)
    -- Use curl for URL fetching since it's more reliable than pure Lua HTTP
    -- Use temporary file to avoid shell escaping issues
    local temp_file = os.tmpname()
    debug_log("Using temporary file for URL fetch: " .. temp_file)
    local cmd = string.format("curl -fs '%s' -o '%s'", url:gsub("'", "'\\''"), temp_file:gsub("'", "'\\''"))
    debug_log("Curl command: " .. cmd)
    local success = os.execute(cmd)

    if success == 0 or success == true then -- Lua 5.1 vs 5.2+ compatibility
        local file = io.open(temp_file, "rb")
        if file then
            local content = file:read("*a")
            file:close()
            os.remove(temp_file)
            debug_log("Successfully fetched " .. #content .. " bytes from URL")
            return content
        end
    end

    debug_log("Failed to fetch URL: " .. url)
    os.remove(temp_file)
    return nil
end

local function has_stdin()
    debug_log("Checking for stdin input")
    -- Check if stdin is a terminal or has data
    local handle = io.popen("[ -t 0 ] && echo 'terminal' || echo 'pipe'")
    if not handle then
        debug_log("Failed to check stdin")
        return false
    end
    local result = handle:read("*a")
    handle:close()
    local has_pipe = string.match(result or "", "pipe") ~= nil
    debug_log("Stdin check result: " .. (has_pipe and "has input" or "no input"))
    return has_pipe
end

-- Main execution - now exported as a module function
function M.main(args)
    tty_write, tty_handle = make_writer()

    debug_log("=== IMGCAT MAIN START ===")
    debug_log("Arguments: " .. table.concat(args, " "))

    local has_stdin_input = has_stdin()

    -- Show help if no arguments and no stdin
    if not has_stdin_input and #args == 0 then
        debug_log("No arguments and no stdin, showing help")
        show_help()
        return
    end

    check_dependency("base64")

    -- Default values
    local print_filename = 0
    local width = ""
    local height = ""
    local preserve_aspect_ratio = ""
    local file_type = ""
    local legacy = 0
    local is_url = false

    debug_log("Default parameters set")

    -- Parse command line arguments
    local i = 1
    while i <= #args do
        local arg = args[i]
        debug_log("Processing argument: " .. arg)

        if arg == "-h" or arg == "--help" then
            show_help()
            return
        elseif arg == "-p" or arg == "--print" then
            print_filename = 1
            debug_log("Print filename enabled")
        elseif arg == "-n" or arg == "--no-print" then
            print_filename = 0
            debug_log("Print filename disabled")
        elseif arg == "-W" or arg == "--width" then
            i = i + 1
            if i <= #args then
                validate_size_unit(args[i])
                width = args[i]
                debug_log("Width set to: " .. width)
            end
        elseif arg == "-H" or arg == "--height" then
            i = i + 1
            if i <= #args then
                validate_size_unit(args[i])
                height = args[i]
                debug_log("Height set to: " .. height)
            end
        elseif arg == "-r" or arg == "--preserve-aspect-ratio" then
            preserve_aspect_ratio = "1"
            debug_log("Preserve aspect ratio enabled")
        elseif arg == "-s" or arg == "--stretch" then
            preserve_aspect_ratio = "0"
            debug_log("Stretch mode enabled")
        elseif arg == "-l" or arg == "--legacy" then
            legacy = 1
            debug_log("Legacy mode enabled")
        elseif arg == "-f" or arg == "--file" then
            has_stdin_input = false
            is_url = false
            debug_log("File mode enabled")
        elseif arg == "-u" or arg == "--url" then
            check_dependency("curl")
            has_stdin_input = false
            is_url = true
            debug_log("URL mode enabled")
        elseif arg == "-t" or arg == "--type" then
            i = i + 1
            if i <= #args then
                file_type = args[i]
                debug_log("File type set to: " .. file_type)
            end
        elseif string.match(arg, "^%-") then
            error_msg("Unknown option flag: " .. arg)
            show_help()
            return
        else
            -- Process file/URL
            debug_log("Processing " .. (is_url and "URL" or "file") .. ": " .. arg)
            local encoded_image
            if is_url then
                local data = read_url(arg)
                if not data then
                    error_msg("Could not retrieve image from URL " .. arg)
                    return
                end
                encoded_image = b64_encode(data)
            else
                local data = read_file(arg)
                if not data then
                    error_msg("imgcat: " .. arg .. ": No such file or directory")
                    return
                end
                encoded_image = b64_encode(data)
            end

            has_stdin_input = false
            print_image(arg, 1, encoded_image, print_filename, width, height, preserve_aspect_ratio, file_type, legacy)
        end

        i = i + 1
    end

    -- Read and print stdin
    if has_stdin_input then
        debug_log("Reading from stdin")
        local stdin_data = io.read("*a")
        if stdin_data then
            debug_log("Read " .. #stdin_data .. " bytes from stdin")
            local encoded_image = b64_encode(stdin_data)
            print_image("", 1, encoded_image, 0, width, height, preserve_aspect_ratio, file_type, legacy)
        else
            debug_log("No data received from stdin")
        end
    end

    if not has_image_displayed then
        error_msg("No image provided. Check command line options.")
        show_help()
        return
    end

    debug_log("=== IMGCAT MAIN END ===")
end

-- Cleanup function to close debug file
local function cleanup()
    if debug_file_handle then
        debug_log("=== DEBUG SESSION END ===")
        debug_file_handle:close()
        debug_file_handle = nil
    end
end

-- Run main if executed as CLI script
if not pcall(debug.getlocal, 4, 1) then
    local args = {}
    for i = 1, #arg do table.insert(args, arg[i]) end
    M.main(args)
    if tty_handle then tty_handle:close() end
    cleanup()
end

-- Export updated functions
M.print_image = print_image
M.b64_encode = b64_encode
M.read_file = read_file
M.read_url = read_url
M.main = M.main
M.enable_debug = M.enable_debug
M.disable_debug = M.disable_debug
M.get_tty_name = get_tty_name

return M
