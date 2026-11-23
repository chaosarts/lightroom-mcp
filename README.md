# Lightroom MCP

Das Basissetup enthält einen Python-MCP-Server und ein Lua-Plug-in für Adobe Lightroom Classic. Die Verbindung zwischen beiden und die Lightroom-Tools folgen später.

## Server

Mit Python 3.11 oder neuer im Repository-Stammverzeichnis ausführen.

```sh
python3 -m venv server/.venv
server/.venv/bin/python -m pip install -e ./server
```

Im MCP-Client `stdio` als Transport und den absoluten Pfad zu `server/.venv/bin/lightroom-mcp` als Kommando eintragen. Für einen ersten Check den Server mit dem Client verbinden und die Tool-Liste abrufen. Sie ist im Basissetup leer.

## Lightroom-Classic-Plug-in

In Lightroom Classic 13.0 oder neuer **Datei → Zusatzmodul-Manager → Hinzufügen** öffnen und `plugin/LightroomMCP.lrplugin` auswählen. Das Zusatzmodul erscheint als **Lightroom MCP**.
