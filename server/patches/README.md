# Patches on top of upstream

`server/Dockerfile` applies every `*.patch` here, in file-name order, to the
upstream source before compiling. The GitLab backup applies the same files, so
GitLab always holds exactly the source each image was built from.

Current patches:

| File | Why |
|---|---|
| `0001-add-cmake-helper-scripts.patch` | Adds `cmake_cmd` / `cmake_cmd_release`, so the GitLab copy can still be built by hand. Docker builds pass the same options directly. |
| `0002-cmake4-prefix-option.patch` | Upstream's documented `cmake ... -DPREFIX=../server` fails on CMake 4.x (Ubuntu 26.04): CMake clears an internal `PREFIX` variable during compiler detection, the user's value shows through, and detection breaks with `macro names must be identifiers`. The patch keeps the user's value aside until `project()` is done. Docker builds don't need it (they use `CMAKE_INSTALL_PREFIX`); it keeps the GitLab copy buildable with upstream's own instructions. Tested: with and without `-DPREFIX`, and on re-configure. |

## Fixes from lurundao/tortoise-wow-dev that are no longer needed

Checked against upstream `1181dev` `a4972d9` with unpatched builds on Ubuntu
26.04 (gcc 15, CMake 4.2; default options and `USE_PCH=OFF`) and Ubuntu 24.04
(gcc 13, CMake 3.28):

| Fix | Status upstream |
|---|---|
| `AccountMgr.h`, `AllocatorWithCategory.h`: missing `#include <optional>` | Upstream now includes `<optional>` in both. |
| `DatabaseLogger.hpp`: missing `#include <optional>` | Still missing upstream, but all 9 files that include it compile with `USE_PCH=OFF`, because `<optional>` arrives through other headers first. Not needed; worth reporting upstream so the header is self-contained. |
| `dep/include/rapidjson/document.h`: `GenericStringRef::operator=` | Upstream carries the same `= delete` change. |
| `Util.h`: `fmt::underlying` replaced by a cast | Compiles with gcc 13 and gcc 15 against the bundled fmt 10.1. |
| `tools/mmap`, `tools/vmap_assembler` CMake include paths | Extractors build without them on gcc 13 and gcc 15. |
| `WardenModuleMgr.cpp`: `_winModules.empty()` guard | Upstream has the same check. |
| `Warden.cpp`: byte-order mark removed | Cosmetic. |

## When a patch stops applying

The build fails at the `applying ...` step. To refresh a patch:

```bash
. server/upstream.env
git clone https://github.com/tortoise-wow/tortoise-wow.git /tmp/tw && cd /tmp/tw
git checkout <new upstream commit>
git apply --3way /path/to/tortoise-wow-docker/server/patches/0001-*.patch   # fix conflicts
git diff HEAD > /tmp/new.patch   # then put the description lines from the old patch back on top
```

Changing any patch changes the image tag, so the next workflow run on the
default branch builds new images and opens a pull request that pins them.
