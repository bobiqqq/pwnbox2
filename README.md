# pwnbox for Apple Silicon

## How it works
- The `pwnbox` script starts the Colima profile `x64` (amd64 via QEMU) if it isn’t running.
- It starts Colima with `--activate=false` so it won’t switch your current Docker context.
- All payloads always go into the **same container**: `pwnbox-main` (the container is not removed).
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

# 4) build the image INSIDE the colima-x64 docker context (run from repo root with Dockerfile)
docker --context colima-x64 buildx build --load -t pwnbox .

# 5) install the launcher script OPTIONAL BUT RECOMMENDED FOR FAST EXEC
# sudo install -m 0755 ./pwnbox /usr/local/bin/pwnbox
```

## Commands
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

## Environment variables (optional)
- `PWNBOX_PROFILE` (default: `x64`)
- `PWNBOX_DOCKER_CONTEXT` (default: `colima-x64`)
- `PWNBOX_IMAGE` (default: `pwnbox`)
- `PWNBOX_CONTAINER` (default: `pwnbox-main`)
- `PWNBOX_DIR_FILE_LIMIT` (default: `5`)
- `PWNBOX_STOP_COLIMA` (default: `ask`, values: `ask|yes|no`)
