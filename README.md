# Capi (/ka.pi/) - Capacities for KOReader

This plugin for [KOReader](https://github.com/koreader/koreader) allows you to synchronize and view your Capacities PDF objects on your E-Reader.

It is heavily based on [zotero.koplugin](https://github.com/stelzch/zotero.koplugin).

## Features

- Synchronize Capacities PDF objects and collections via API
- Browse collections and objects
- Download and open attached PDF files
- Search entries by title

## Known limitations

- Capacities doesn't provide PDF annotations through their API, so it's not possible to render them on the downloaded PDF in your E-Reader, or to sync new highlights back to Capacities

## Installation Guide

1. Copy the files in this repository to `<KOReader>/plugins/capi.koplugin`
2. Obtain an API token from your [Capacities account settings](https://capacities.io).
3. Set your API key directly in KOReader through the plugin settings or edit the configuration file.

In KOReader, the Capacities plugin will be visible in the search menu under the "Capacities" entry.

## Configuration

### Manual configuration

If you prefer not to enter credentials on your E-Reader, you can edit the `meta.lua` file inside the storage directory (`<KOReader>/capi/meta.lua`):

```lua
return {
    ["api_key"] = "your_api_key_here", -- API secret key
}
```

## About

Allows seamless access to your Capacities PDF knowledge base on E-Ink devices via KOReader.
