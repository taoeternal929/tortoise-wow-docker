# Patches on top of upstream

`server/Dockerfile` applies every `*.patch` here, in file-name order, to the
upstream source before compiling. The GitLab backup applies the same files, so
GitLab always holds exactly the source each image was built from.

Current patches:

| File | Why |
|---|---|
| `0001-add-cmake-helper-scripts.patch` | Adds `cmake_cmd` / `cmake_cmd_release`, so the GitLab copy can still be built by hand. Docker builds pass the same options directly. |

Dropped when moving to Ubuntu 26.04 builds (upstream compiles cleanly without them):

- `#include <optional>` in `DatabaseLogger.hpp` and the `fmt::underlying` replacement in `Util.h`
- the `_winModules.empty()` guard in `WardenModuleMgr.cpp` (upstream now has the same check)

## When a patch stops applying

The build fails at the `applying ...` step. To refresh a patch:

```bash
. server/upstream.env
git clone https://github.com/tortoise-wow/tortoise-wow.git /tmp/tw && cd /tmp/tw
git checkout <new upstream commit>
git apply --3way /path/to/tortoise-wow-docker/server/patches/0001-*.patch   # fix conflicts
git diff HEAD > /path/to/tortoise-wow-docker/server/patches/0001-*.patch    # keep the header text
```

Changing any patch changes the image tag, so the next workflow run on the
default branch builds new images and opens a pull request that pins them.
