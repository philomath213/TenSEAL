# Roadmap

Working notes on outstanding modernization work. Ordered roughly by priority.

## Context

TenSEAL's CI had rotted against current GitHub runner images: the `*-latest` images
moved to CMake 4.x and AppleClang 17+, which the 2021-era vendored dependencies
cannot build against. Rather than force a large dependency upgrade, the approach has
been to **pin runners and keep the old dependencies**, with
`CMAKE_POLICY_VERSION_MINIMUM=3.5` as a transitional shim, and to modernize
dependencies separately.

Shipped so far (v0.3.17): cibuildwheel across Python 3.11–3.14 on three platforms,
PEP 517/621 packaging, ruff + pre-commit, an sdist, a declared `numpy` dependency,
a single-upload release path with a TestPyPI rehearsal, and a fixed Benchmarks
workflow.

## 1. Make the lockfile actually used

`uv.lock` is committed but nothing reads it — the install scripts run
`pip install --group dev`, which resolves fresh from `pyproject.toml`. Raised in
review on #521.

Replace with `uv sync --frozen --group dev`. Because `uv sync` also installs the
project, this collapses five scripts into one cross-platform path:
`install_req_{ubuntu,macos,windows}`, `build_nix.sh`, `build_windows.bat`.

Note `uv pip install --group` reads `pyproject.toml`, **not** `uv.lock`; only the
project interface (`uv sync`, `uv export`) consumes the lock.

Keep pip deliberately in two places: the TestPyPI install-back check, whose purpose is
to reproduce what a real user runs, and the runtime dependencies in `[project]`, which
stay unpinned — libraries constrain, applications lock.

Fold in three small fixes:

- Drop `numpy` from `CIBW_TEST_REQUIRES` — installing the wheel now pulls it, so
  listing it explicitly masks a missing declaration rather than testing it
- Give `numpy` a lower bound in `[project] dependencies`
- Drop `wheel` from `[build-system] requires` (obsolete for setuptools ≥ 70.1)

## 2. Automation and hardening

- **Dependabot** (`.github/dependabot.yml`) for `github-actions` and `pip`. Actions are
  SHA-pinned, so nothing else will ever move them.
- **Least-privilege `permissions:`** on every workflow — none declare one today, so all
  jobs get the default token scope. Add `concurrency` with `cancel-in-progress` on
  `tests.yml`; 13 jobs × ~27 min per superseded push is real money.

## 3. C++ dependency modernization

**Centralize the pins** into `cmake/dependencies.cmake` (`set(TENSEAL_SEAL_VERSION …)`)
so drift is visible on one screen and a bot has one file to edit. Then add a scheduled
workflow that compares the pins against upstream tags and opens a tracking issue —
Dependabot cannot see CMake `FetchContent` pins. (Renovate's `customManagers` can, if
the app can be installed.)

Then bump, one per PR, in increasing risk order:

| Dependency | To | Risk |
| --- | --- | --- |
| nlohmann/json | 3.12.0 | Header-only. Removes one pre-3.5 CMake floor |
| googletest | v1.17.0 | Test-only |
| pybind11 | 2.13.6 | Safe step; evaluate 3.0.x separately |
| xtensor stack | 0.27.1 / xtl 0.8.2 / xsimd 14.3.0 | Needs C++20, include-path changes in `tensor_storage.h`, `std::result_of` → `std::invoke_result` in `threadpool.h`. Unblocks AppleClang 17+ |
| protobuf | v22+ | Largest. Needs Abseil and a rewrite of `cmake/protobuf.cmake` to FetchContent targets. Verify serialized-blob round-trip against a 0.3.17 wheel |

**Then retire the shim**: once json and protobuf are upgraded, drop
`CMAKE_POLICY_VERSION_MINIMUM=3.5` everywhere, raise `cmake_minimum_required` to 3.22+,
move to C++20, and move macOS to `macos-15`. Hold Windows on `windows-2022`.

Optionally revisit SEAL 4.3.3 → 4.4.0; it broke `test_polynomial` ("input value is
larger than plain_modulus") when tried and needs its own investigation.

## 4. Bazel (low priority)

Add `MODULE.bazel`, migrate off `WORKSPACE`/`preload.bzl`/`deps.bzl`, and realign every
pin to `cmake/`. Re-enable on `pull_request` only once green. Schedule after the
dependency work so it is realigned against final versions rather than redone.

## 5. Documentation backlog

- **Refresh the tutorials.** All six notebooks were last executed on Python 3.8–3.9
  (2020–2022), below the current floor, so outputs come from a five-generations-old
  build. Tutorial 4 needs MNIST + torch, making it the most expensive item. No tutorial
  covers the tensor API (`CKKSTensor`/`BFVTensor`).
- **Resolve the two README TODO stubs** — Docker images (unmaintained since 2021,
  v0.3.4; `docker-images/` targets EOL Python 3.6–3.9) and Bazel. Each needs a
  refresh-or-retire decision.
- **API reference.** Docstrings exist but nothing renders them; there is no docs site
  and no architecture overview.

Deliberately **not** planned: encryption parameter guidance. TenSEAL is a binding plus
a tensor layer, and parameter semantics belong to SEAL; the README links there instead.

Not needed: issue templates, PR template and Code of Conduct are inherited from the
`OpenMined/.github` organization repository.

## 6. Other known issues

- **Three CKKS tests never run** — `test_add`/`test_sub`/`test_mul` in
  `tests/python/tenseal/tensors/test_serialization.py` are shadowed by BFV
  redefinitions. Suppressed with a scoped `F811` ignore. Un-shadowing them changes
  which tests execute and may surface real failures.
- **`tenseal/deps.bzl` references the deleted `requirements_dev.lock`.** Already broken
  before removal (it pinned a local `--find-links` path); belongs to the Bazel work.
- **Benchmarks C++ microbenchmarks** under `tests/cpp/benchmarks/` are only reachable
  through Bazel, so they cannot currently run.
- **OSSAR → CodeQL.** Deprioritized: OSSAR still works. CodeQL would give real
  C/C++ and Python analysis, but the C++ path needs a full build per run.
