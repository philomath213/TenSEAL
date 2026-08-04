# TenSEAL — notes for Claude Code

Homomorphic encryption on tensors: a C++ core over [Microsoft SEAL](https://github.com/microsoft/SEAL),
exposed to Python through pybind11. Python 3.11+.

## Layout

| Path | What |
| --- | --- |
| `tenseal/cpp/` | C++ core — contexts, BFV/CKKS vectors and tensors |
| `tenseal/sealapi/` | Thin pybind11 bindings exposing SEAL directly |
| `tenseal/*.py`, `tenseal/tensors/` | Python API layer |
| `tenseal/proto/` | Protobuf schemas for serialization (`*.pb.*` are generated, gitignored) |
| `cmake/*.cmake` | One file per dependency, each pinning a `GIT_TAG` |
| `tests/cpp/`, `tests/python/` | gtest and pytest suites |

Dependencies are fetched and built by CMake (`FetchContent`). **There are no git
submodules** and nothing needs installing by hand.

## Commands

```bash
uv sync --group dev                  # dev dependencies (PEP 735 group, locked in uv.lock)
pip install .                        # build + install (compiles the C++ extension)

pre-commit run --all-files           # lint: ruff (python) + clang-format (c++)

pytest -m "not slow" -v tests/python/tenseal
pytest -v tests/python/sealapi
cmake . -D BUILD_TEST=TRUE && make -j && CTEST_OUTPUT_ON_FAILURE=1 make test
```

## Constraints that are not obvious from the code

- **CMake 4.x fails** with `Compatibility with CMake < 3.5 has been removed`, because
  protobuf 3.15.8 and nlohmann/json 3.9.1 declare pre-3.5 minimums. Every workflow
  sets `CMAKE_POLICY_VERSION_MINIMUM=3.5` as a shim. It can only be removed once
  **both** of those dependencies are upgraded.
- **macOS needs Xcode 15.x.** AppleClang 17+ (Xcode 16+) cannot compile the vendored
  xtensor 0.23.5 (`resize_container`, `std::result_of`). CI pins `macos-14` and runs
  `xcode-select -s /Applications/Xcode_15.4.app`.
- **Runners are pinned deliberately** — `ubuntu-24.04`, `windows-2022`, `macos-14`.
  `*-latest` images break the build for the two reasons above. `windows-2025` ships a
  preview MSVC that hit an internal compiler error.
- **CI builds cp311–cp314 but only tests cp314** (`CIBW_TEST_SKIP`). C++ gtest runs on
  Linux and macOS only; Windows has never run it.
- **The Bazel build is broken** and its workflow is `workflow_dispatch`-only. Its pins
  have drifted from `cmake/` (SEAL 4.1.1 vs 4.3.3, xtensor 0.24.3 vs 0.23.5), and
  `tenseal/deps.bzl` still references the deleted `requirements_dev.lock`.
- **`uv.lock` exists but nothing reads it.** The install scripts use
  `pip install --group dev`, which resolves fresh from `pyproject.toml`. Only
  `uv sync` / `uv export` consume the lock — `uv pip install` does not.
- **`BFVVectorTest.TestBFVSerializationSize` is flaky.** In
  `tests/cpp/tensors/bfvvector_test.cpp` (~line 293), the assertion
  `2 * sym_buffer.size() > pk_buffer.size()` compares zstd-compressed sizes of
  symmetric- vs asymmetric-encrypted vectors. Encryption is randomized, so the sizes
  vary run to run and the margin is narrow. A single CI failure here is almost
  certainly flakiness — re-run before investigating. A real fix would widen the margin
  or make the check deterministic.
- **Three CKKS tests never run.** In `tests/python/tenseal/tensors/test_serialization.py`,
  `test_add`/`test_sub`/`test_mul` (lines ~126/154/181) are shadowed by BFV
  redefinitions of the same name, so pytest only collects the second set. Suppressed
  with a scoped `F811` ignore; un-shadowing them changes which tests run.

## Dependency pins

Each lives in its own `cmake/*.cmake` file. Current versus latest:

| Dependency | Pinned | Notes |
| --- | --- | --- |
| Microsoft SEAL | v4.3.3 | v4.4.0 breaks `test_polynomial` |
| protobuf | v3.15.8 (2021) | forces the CMake shim; upgrading needs Abseil + a FetchContent rewrite |
| xtensor / xtl / xsimd | 0.23.5 / 0.7.2 / 7.4.10 (2021) | upgrading requires C++20; unblocks modern AppleClang |
| nlohmann/json | 3.9.1 (2020) | header-only; the other half of the CMake shim |
| pybind11 | 2.12.0 | |
| googletest | release-1.12.1 | test-only |

## Conventions

- **Version lives only in `tenseal/version.py`**, read dynamically by the build backend.
- **Conventional commit prefixes** (`ci:`, `build:`, `docs:`, `fix:`, `chore:`), one
  concern per PR. Actions are pinned by SHA.
- **Releases**: rehearse on TestPyPI via the `Build and Publish` workflow, then tag and
  publish a GitHub Release — publishing the release is what triggers the real upload.
  Full procedure in `RELEASING.md` (lands upstream with #525).
- **This is a fork.** Cut branches intended for upstream from `upstream/main`, not from
  this fork's `main`, or they will carry fork-only commits into the PR.
- **Don't touch `docs/ROADMAP.md` until the change merges into `OpenMined/TenSEAL` main.**
  An item moves to done when it lands upstream, not when it is written or a PR is opened,
  so the roadmap never reads ahead of what actually shipped.

## Where things stand

See [docs/ROADMAP.md](docs/ROADMAP.md) for outstanding work.
