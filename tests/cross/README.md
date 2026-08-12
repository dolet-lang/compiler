# Cross-target smoke tests

These tests are intentionally excluded from `run_tests.bat`: executing them
requires the matching target OS (or WSL). They verify target-pack link and
runtime boundaries rather than language semantics.

From a Windows checkout with WSL installed:

```powershell
bin\doletc.exe tests\cross\linux_desktop_smoke.dlt --target linux/x86_64 -O2 -o build\linux_desktop_smoke
wsl.exe bash -lc "chmod +x '/mnt/c/path/to/dolet-compiler/build/linux_desktop_smoke' && '/mnt/c/path/to/dolet-compiler/build/linux_desktop_smoke'"
```

The compiler must report `System SDK: dynamic desktop`. A zero exit status
confirms that loader TLS, pthread-backed Dolet threads, and the X11 ABI can
coexist in one generated executable.
