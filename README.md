# nvim-icat

A Neovim plugin for displaying images inline in iTerm2 using the Inline Images Protocol.

## Features

- Display images directly in Neovim using iTerm2's inline image protocol
- Opens images in a dedicated tab for clean viewing
- Automatic tab cleanup with `q` or `<Esc>` key bindings
- Support for custom image dimensions
- Works with local files and URLs (via curl)
- Debug logging support

## Requirements

- Neovim 0.5+
- iTerm2 (macOS) with inline image support
- `base64` command-line utility (usually pre-installed)
- `curl` (for URL support)

## Installation

### Using [lazy.nvim](https://github.com/folke/lazy.nvim)

```lua
return {
    'vito-c/nvim-icat',
    config = function()
        require('nvim-icat').setup()
    end,
}
```

### Using [packer.nvim](https://github.com/wbthomason/packer.nvim)

```lua
use {
    'vito-c/nvim-icat',
    config = function()
        require('nvim-icat').setup()
    end
}
```

### Using [vim-plug](https://github.com/junegunn/vim-plug)

```vim
Plug 'vito-c/nvim-icat'

lua << EOF
require('nvim-icat').setup()
EOF
```

## Configuration

### Basic Setup

```lua
require('nvim-icat').setup()
```

### Custom Configuration

```lua
require('nvim-icat').setup({
    -- Custom path to imgcat.lua if needed
    imgcat_path = '/path/to/imgcat.lua'
})
```

## Usage

### Commands

- `:IcatShow <path>` - Display an image from the specified path

### Lua API

```lua
-- Show an image
require('nvim-icat').show_image('/path/to/image.png')

-- Show an image with custom options
require('nvim-icat').show_image('/path/to/image.png', {
    width = '80',    -- Width in character cells
    height = '40'    -- Height in character cells
})
```

### Key Bindings (in image viewer)

- `q` - Close the image viewer
- `<Esc>` - Close the image viewer

The image tab will also auto-close when you switch to another tab.

## Examples

```lua
-- Display an image
:IcatShow ~/Pictures/photo.jpg

-- From Lua
:lua require('nvim-icat').show_image(vim.fn.expand('~/Pictures/photo.jpg'))
```

## How It Works

This plugin uses iTerm2's proprietary inline images protocol to display images directly in the terminal. The `imgcat.lua` script handles the low-level communication with iTerm2, while the Neovim plugin (`nvim-icat.lua`) provides a user-friendly interface.

When you display an image:
1. A new tab is created with image metadata
2. The imgcat script encodes the image to base64
3. The encoded image is sent to iTerm2 using escape sequences
4. iTerm2 renders the image inline in the terminal

## Debug Logging

To enable debug logging, set the environment variable before starting Neovim:

```bash
export IMGCAT_DEBUG=1
nvim
```

Debug logs will be written to:
- `debug.txt` - imgcat script logs
- `debug-plugin.txt` - plugin logs

## Supported Image Formats

All formats supported by iTerm2:
- PNG
- JPEG/JPG
- GIF
- BMP
- WebP
- And more

## Limitations

- Only works in iTerm2 on macOS
- Image display may not work in tmux (depending on configuration)
- Images are not persistent after closing Neovim

## Troubleshooting

### Images not displaying

1. Verify you're using iTerm2
2. Check that inline images are enabled in iTerm2 preferences
3. Enable debug logging to see what's happening
4. Ensure the image file exists and is readable

### Command not found

Make sure you've called `setup()` in your Neovim configuration:

```lua
require('nvim-icat').setup()
```

## Contributing

Contributions are welcome! Please feel free to submit issues or pull requests.

## License

MIT

## Credits

Based on the iTerm2 imgcat script, reimplemented in Lua for Neovim integration.

## See Also

- [iTerm2 Inline Images Protocol](https://iterm2.com/documentation-images.html)
- [Original imgcat script](https://iterm2.com/utilities/imgcat)
