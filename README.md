# pwnbox for Apple Silicon

## How it works
- The `pwnbox` script starts the Colima profile `x64` (amd64 via QEMU) if it isn’t running.
- It starts Colima with `--activate=false` so it won’t switch your current Docker context.
- All payloads always go into the **same container**: `pwnbox-main` (the container is not removed).
- By default the container is **not privileged** (`SYS_PTRACE` only + Docker default seccomp).
- For each run it creates a folder `/home/<name>_<hex>/` and puts:
  - file: `/home/<name>_<hex>/<original_filename>` + `chmod +x`
  - directory: the directory contents (no suffixes added to names) + recursive perms
- After you exit the container shell, it asks: `Stop Colima? [Y/n]`.
  - `Enter`/`y` → stop Colima (and stop the container)
  - `n` → keep Colima (and the container) running to avoid restart overhead between files

## Dependencies
```bash
brew install docker docker-buildx colima
```

## Setup from copy/paste
```bash
# 1) install deps
brew install docker docker-buildx colima

# 2) clone the repo
git clone https://github.com/bobiqqq/pwnbox2
cd pwnbox2

# 3) start the amd64 Colima VM (does not change your current docker context)
colima start -p x64 -a x86_64 -c 4 -m 2 -d 10 --vm-type qemu --activate=false

# 3.1) if the docker context wasn't created automatically, create it once:
docker context inspect colima-x64 >/dev/null 2>&1 || docker context create colima-x64 --docker "host=unix://$HOME/.colima/x64/docker.sock"

# 4) build the image INSIDE the colima-x64 docker context (run from repo root with Dockerfile)
docker --context colima-x64 build -t pwnbox .
# (outside colima-x64 context, add: --platform linux/amd64)

# 5) install the launcher script OPTIONAL BUT RECOMMENDED FOR FAST EXEC
sudo install -m 0755 ./pwnbox /usr/local/bin/pwnbox
```

## Commands (accessible with pwnbox -h)
Just enter the container (no copying):
```bash
pwnbox
```

Copy a file:
```bash
pwnbox ./a.out
```

Copy/run a directory:
```bash
pwnbox ./challenge_dir
```

Safety guard to avoid “copy my whole Downloads by accident”: if the directory has more than 5 files at top level, the script refuses.
Force copying a directory:
```bash
pwnbox --force-dir ~/Downloads
```

Clear previously copied payloads (keeps the container):
```bash
pwnbox --clear
```
Deletes `/home/*` except `/home/ubuntu`.

Show size info (docker + `/home` usage inside the container):
```bash
pwnbox --size
```

Remove the container (all copied files are lost; next `pwnbox` will recreate it):
```bash
pwnbox --rm
```

Optional security/compatibility env vars:
```bash
# default: no privileged mode
export PWNBOX_PRIVILEGED=no

# if you need old behavior:
export PWNBOX_PRIVILEGED=yes

# seccomp mode for non-privileged container (default: default)
export PWNBOX_SECCOMP=unconfined
```

Note: colima setup may be long, so if ssh takes a few minutes to setup, that's normal.
