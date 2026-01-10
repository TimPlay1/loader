# ODY.FARM Script Loader

A centralized loader for Roblox scripts, served via ody.farm domain.

## Usage

Execute the loader in your exploit:

```lua
loadstring(game:HttpGet("https://ody.farm/loader.lua"))()
```

## Configuration

The loader automatically creates a config file `ody_loader_config.json` in the exploit workspace.
You can edit this file to enable/disable specific scripts.

### Default Config (all enabled):

```json
{
    "adminabuse": true,
    "killaura": true,
    "killaura_sync": true,
    "autosteal": true,
    "removeborders": true,
    "disable_camera": true,
    "customsound": true,
    "ambient": true
}
```

## Available Scripts

| ID | Name | Description |
|----|------|-------------|
| `adminabuse` | Admin Abuse | Auto-use admin commands on thieves |
| `killaura` | Killaura | Auto-attack enemies, ESP, glove rotation |
| `killaura_sync` | Killaura Sync | Meowl greeting animation |
| `autosteal` | AutoSteal Optimized | Auto-steal brainrots, ESP, thief tracking |
| `removeborders` | Remove Borders | Remove invisible borders, add ramps |
| `disable_camera` | Disable Camera Effects | Block camera shake, blur, FOV changes |
| `customsound` | Custom Sound Replacer | Replace game sounds with custom MP3 |
| `ambient` | Ambient Controller | Custom skybox, lighting, color picker |

## Deployment (Coolify)

1. Connect this repository to Coolify
2. Configure static file serving for the `scripts/` folder
3. Set up domain `ody.farm` to point to the deployment
4. Ensure CORS headers allow requests from Roblox

### Nginx Config Example

```nginx
server {
    listen 80;
    server_name ody.farm;
    
    root /app;
    
    location / {
        add_header Access-Control-Allow-Origin *;
        add_header Access-Control-Allow-Methods "GET, OPTIONS";
        try_files $uri $uri/ =404;
    }
    
    location /scripts/ {
        add_header Access-Control-Allow-Origin *;
        add_header Content-Type "text/plain; charset=utf-8";
        try_files $uri $uri/ =404;
    }
}
```

## File Structure

```
/
├── loader.lua           # Main loader script
├── scripts/
│   ├── adminabuse.lua
│   ├── killaura.lua
│   ├── killaura_sync.lua
│   ├── autosteal_optimized.lua
│   ├── RemoveBorders.lua
│   ├── disable_camera_effects.lua
│   ├── CustomSound.lua
│   └── Ambient.lua
└── README.md
```

## URLs

- Loader: `https://ody.farm/loader.lua`
- Scripts: `https://ody.farm/scripts/{script_name}.lua`
