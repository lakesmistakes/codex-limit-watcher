# User Assets

Put personal notification assets in this folder when you do not want to edit source code.

Examples:

- `assets/user/my-alert.wav`
- `assets/user/my-billboard.png`

Then update `config.json`:

```json
{
  "notifications": {
    "soundFile": "assets/user/my-alert.wav",
    "billboardImage": "assets/user/my-billboard.png"
  }
}
```

Restart the watcher after changing config. `.wav` files are recommended for sounds because Windows can play them reliably.
