# Free 90 MiB (KOReader plugin)

A KOReader plugin for Kindle that manages free space on `/mnt/us` using only its own filler files in:

```text
/mnt/us/koreader/free90MiB/
```

Managed files are named `trash00000.bin` through `trash99999.bin`. Every file except the highest-numbered one is 20 MiB; the last file may be smaller. Files with other names are not modified.

## Installation

Copy the contents of this directory into a folder named `free90MiB.koplugin` inside `koreader/plugins/`. On a Kindle, the path will typically be:

```text
/mnt/us/koreader/plugins/free90MiB.koplugin/
```

Restart KOReader and enable the plugin if necessary. The data directory is created when the plugin is loaded. Loading the plugin **does not** fill the storage automatically.

## Usage

In the KOReader menu, select **Free 90 MiB**. The screen lets you:

- normalize free space to the 70–90 MiB range;
- request a specific amount of space to be released, in MiB;
- follow the operation with a progress bar and cancel between write or removal steps.

Normalization creates filler files when more than 90 MiB is free and removes the plugin's files when less than 70 MiB is free. If there are not enough plugin-owned files to restore the range, the operation fails without deleting data from other directories.

## API for other plugins

After KOReader has loaded its plugins, another plugin can load the shared module:

```lua
function OtherPlugin:onNeedSpace()
    -- Require lazily after KOReader has loaded its plugins and module paths.
    local Free90MiB = require("free90mib_api")
    local handle, err = Free90MiB.release_space(25 * Free90MiB.MIB,
        function(progress)
            -- progress.percentage, progress.current_free_bytes,
            -- progress.file_name, progress.phase
        end,
        function(success, result)
            if success then
                -- Perform the operation that needs the released space here.
                -- Call Free90MiB.reconcile(...) afterward to restore the range.
            end
        end
    )
    if not handle then
        -- err explains why the operation could not be started.
    end
end
```

Exported functions:

- `get_status()` — returns `free_bytes`, `managed_bytes`, and the managed files;
- `release_space(bytes, on_progress, on_done)` — removes filler files until at least the requested amount has been released;
- `reconcile(on_progress, on_done)` — adjusts free space to the 70–90 MiB range.

Operations are asynchronous and serialized. `on_done(success, result)` receives the result; `result.changed_bytes` indicates the net observed change in free space. Since space is released by removing whole files, the amount released may exceed the request. The returned object provides `:cancel()`; completed file changes are retained, and a valid partial file may remain as the last file in the series.

## Units and limitations

MiB is binary: 1 MiB = 1,048,576 bytes. The measured free space may vary because of filesystem allocation units or writes by other processes. The plugin modifies only its filler files; it cannot guarantee the range if other data consumes space and there are not enough plugin-owned files to remove.

## Local tests

With LuaJIT installed, run:

```sh
luajit tests/test_manager.lua
luajit tests/test_api.lua
```

The tests use a fake storage backend and do not run `dd` or modify `/mnt/us`.
