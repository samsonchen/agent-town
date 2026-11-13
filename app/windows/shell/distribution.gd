class_name Distribution
extends RefCounted
## How this copy of agent-town reached the user: the installer from GitHub Releases, or the
## Microsoft Store (an MSIX package; docs/windows/store.md). The Store export preset, "Windows x64
## Store", adds the custom feature "store"; the installer's preset does not.
##
## A Store copy updates through the Store, so it does not check GitHub for a newer app (Store
## policy); and its Open at login is the package's startup task, which the user turns on in Windows
## Settings → Apps → Startup, not the Run key: the Store installs each version in a new folder, so a
## Run value would point at a removed exe. A Store copy must not touch the Run key at all (LoginItem
## is not available): its repair() would point the installer copy's entry at the package.

const STARTUP_SETTINGS := "ms-settings:startupapps"


static func is_store() -> bool:
	return OS.has_feature("store")
