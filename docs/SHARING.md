# Sharing a Windows build

How to build the slice for someone on Windows and what to send them. The shared
build talks to Anthropic directly for Oda and Skrugs; the player brings their own
key and pastes it in F10. No key is ever in the build.

## What is different in the shared build

The **Windows Share** preset in `export_presets.cfg` adds the export feature
`share`. With it, `LLMConfig.default_path()` loads
`content/core/llm/defaults_share.json` instead of `defaults.json`:

- the chain is cloud only (no local llama-server, no Ollama to wait on),
- the cloud profile is `anthropic` against `https://api.anthropic.com/v1`, switched on,
- transcripts are not logged.

The editor and CI never have the `share` feature, so they keep the normal defaults.

## Build it (macOS)

Once: install the Godot 4.7.2 export templates (editor: Editor > Manage Export
Templates, or unpack the official `.tpz` into
`~/Library/Application Support/Godot/export_templates/4.7.2.stable/`).

```sh
mkdir -p builds/windows
godot --headless --path . --export-release "Windows Share" builds/windows/DesertSpaceport.exe
cd builds && zip -r DesertSpaceport-windows.zip windows && cd ..
```

`builds/` is git-ignored. Send `builds/DesertSpaceport-windows.zip`.

Before sending, set a spend limit on the Anthropic key in the Anthropic console.
Send the key separately (password manager or a private message), never inside
the zip.

## For the player (Windows)

1. Unzip `DesertSpaceport-windows.zip` anywhere.
2. Run `DesertSpaceport.exe`. Windows SmartScreen warns about an unknown app
   because the build is not signed: click **More info**, then **Run anyway**.
3. In game, press **F10**, paste the Anthropic key into **Cloud key**, press
   **Save**, then **Test** ("OK via cloud ..." means it works), then **Close**.
   Leave the other fields as they are.
4. Talk to Oda in the cantina or Skrugs outside the back gate (**E**). The top
   right says which brain is answering; "(canned: no brain answered)" means the
   key or connection is not working.

The key is saved in `%APPDATA%\Godot\app_userdata\Desert Spaceport Slice\llm\keys.cfg`,
outside the game folder. Controls are in `LAUNCH.md`.

Windows is not routinely tested; report anything odd (crash on start, black
screen, missing text).
