# TAC (Terminal Access Control) System

A comprehensive, modular access control system for ComputerCraft that provides secure authentication, flexible door management, and extensible functionality through a robust extension system.

## Quick Installation

**One-line installer command:**
**One-line installer command:**
```bash
wget https://raw.githubusercontent.com/Twijn/tac/main/installer.lua && lua installer.lua
```

## Features

- 🔐 **Secure Access Control** - Card-based authentication with configurable permissions
- 🚪 **Door Management** - Support for multiple doors with individual access controls  
- 📊 **Comprehensive Logging** - Detailed access logs with timestamps and user tracking
- 🔧 **Modular Extensions** - Easy-to-add modules for extended functionality
- 💳 **SHOPK Integration** - Payment-based access control with subscription support
- 📱 **User-Friendly Interface** - Intuitive command system and UI components
- ⚡ **Background Processing** - Non-blocking operations for smooth performance

## Installation Options

### Full Interactive Installation
```bash
wget run https://raw.githubusercontent.com/Twijn/tac/main/installer.lua
```
This will prompt you to select which modules to install and perform a complete setup.

### Quick Commands
```bash
# Install everything with all modules
wget run https://raw.githubusercontent.com/Twijn/tac/main/installer.lua install

# Refresh library files only (useful for updates)
wget run https://raw.githubusercontent.com/Twijn/tac/main/installer.lua install-libs

# Install core system only
wget run https://raw.githubusercontent.com/Twijn/tac/main/installer.lua install-core

# Install specific module
wget run https://raw.githubusercontent.com/Twijn/tac/main/installer.lua install-module shopk_access

# Remove a module
wget run https://raw.githubusercontent.com/Twijn/tac/main/installer.lua remove-module shop_monitor

# List available modules
wget run https://raw.githubusercontent.com/Twijn/tac/main/installer.lua list-modules

# Show help
wget run https://raw.githubusercontent.com/Twijn/tac/main/installer.lua --help
```

## Available Modules

### Core System
Always installed - provides basic access control functionality:
- Card management and authentication
- Door control and monitoring
- Security logging and audit trails
- Basic command interface

### SHOPK Access (`shopk_access`)
**Payment-based access control integration**
- Subscription-based access management
- Integration with SHOPK payment system
- Automatic access renewal and expiration
- Payment tracking and reporting
- Flexible pricing tiers

### Shop Monitor (`shop_monitor`)
**Shop monitoring and display**
- Real-time shop status monitoring
- Display integration for public information
- Stock level tracking
- Sales analytics

## System Requirements

- ComputerCraft (CC: Tweaked recommended)
- Internet access for initial installation
- Minimum 64KB disk space
- Redstone I/O for door control (optional)
- Wireless modem for networking (optional)

## Directory Structure

After installation, your system will have the following structure:

```
/
├── installer.lua          # Installation and module management
├── startup.lua           # System startup script
├── data/                 # Persistent data storage
│   ├── settings.json     # System configuration
│   ├── cards.json        # User card database
│   ├── doors.json        # Door configuration
│   └── accesslog.json    # Access attempt logs
├── lib/                  # Core libraries (from GitHub)
│   ├── cmd.lua           # Command processing
│   ├── formui.lua        # UI components
│   ├── persist.lua       # Data persistence
│   ├── s.lua             # String utilities
│   ├── shopk.lua         # SHOPK integration
│   └── tables.lua        # Table utilities
├── tac/                  # TAC core system
│   ├── init.lua          # Main TAC module
│   ├── commands/         # Command handlers
│   ├── core/             # Core functionality
│   ├── extensions/       # Extension modules
│   └── lib/              # TAC-specific libraries
└── logs/                 # System documentation
```

## Getting Started

1. **Install the system:**
   ```bash
   wget https://raw.githubusercontent.com/Twijn/tac/main/installer.lua && lua installer.lua
   ```

2. **Start the system:**
   ```bash
   startup
   ```

3. **Add your first door:**
   ```bash
   door add main "Main Entrance" redstone top
   ```

4. **Create an admin card:**
   ```bash
   card add admin "Administrator" --admin
   ```

5. **Grant access to the door:**
   ```bash
   card access admin main
   ```

## Configuration

The TAC system uses JSON files for configuration stored in the `data/` directory:

### settings.json
```json
{
  "system_name": "TAC Access Control",
  "version": "1.0.0",
  "auto_lock_timeout": 30,
  "require_card_for_commands": false
}
```

### Basic Commands

Once installed and running, TAC provides these commands:

- `card add <name> <display_name>` - Add a new access card
- `card list` - List all registered cards
- `card access <card> <door>` - Grant door access to a card
- `door add <name> <display_name> <type> <side>` - Add a new door
- `door list` - List all configured doors
- `logs show` - Display recent access logs
- `help` - Show available commands

## Module Management

### Installing Modules
```bash
# Install a specific module
wget run https://raw.githubusercontent.com/Twijn/tac/main/installer.lua install-module shopk_access

# Install all available modules
wget run https://raw.githubusercontent.com/Twijn/tac/main/installer.lua install
# Then select "all" when prompted
```

### Removing Modules
```bash
wget run https://raw.githubusercontent.com/Twijn/tac/main/installer.lua remove-module shop_monitor
```

### Updating Libraries
If you need to update the core library files from GitHub:
```bash
wget run https://raw.githubusercontent.com/Twijn/tac/main/installer.lua install-libs
```

## Extension Development

TAC supports custom extensions. See `tac/extensions/_example.lua` for a template.

Extensions can:
- Add new commands
- Hook into system events
- Provide background services
- Integrate with external systems

## Troubleshooting

### Installation Issues
- Ensure you have internet connectivity
- Check that HTTP is enabled in ComputerCraft config
- Verify you have sufficient disk space

### Runtime Issues
- Check `logs/` directory for error logs
- Ensure redstone connections are correct
- Verify card data isn't corrupted in `data/cards.json`

### Module Issues
- Use `wget run https://raw.githubusercontent.com/Twijn/tac/main/installer.lua list-modules` to check installation status
- Reinstall problematic modules with `install-module` command
- Check extension-specific logs in the `logs/` directory

## Contributing

The TAC system is designed to be modular and extensible. 

**Repositories:**
- TAC Core System: https://github.com/Twijn/tac
- Shared Libraries: https://github.com/Twijn/cc-misc/tree/main/util

## License

This project is open source. See individual files for license information.

## Support

For issues, feature requests, or questions:
1. Check the troubleshooting section above
2. Review the logs in the `logs/` directory
3. Create an issue on the GitHub repository

---

**TAC - Terminal Access Control System v1.0.0**  
*Secure, Modular, Extensible*