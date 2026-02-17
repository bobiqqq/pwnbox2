# pwnbox for Apple Silicon

## Quick install (recommended)
```bash
git clone https://github.com/bobiqqq/pwnbox2 && cd pwnbox2 && ./setup.sh
```

`setup.sh` installs dependencies, starts Colima x64, creates Docker context, builds the image and installs `pwnbox`.

Notes:
- run `setup.sh` without `sudo`
- for first run Docker build can be long (amd64 on Apple Silicon)
- if `/usr/local/bin` needs elevated rights, installer asks for `sudo` only at the final install step

## Manual setup
```bash
# 1) install deps
brew install docker docker-buildx colima

# 2) clone repo
git clone https://github.com/bobiqqq/pwnbox2
cd pwnbox2

# 3) start amd64 Colima profile (does not change active docker context)
colima start -p x64 -a x86_64 -c 4 -m 2 -d 10 --vm-type qemu --activate=false

# 4) create docker context if needed
docker context inspect colima-x64 >/dev/null 2>&1 || docker context create colima-x64 --docker "host=unix://$HOME/.colima/x64/docker.sock"

# 5) build image in colima-x64 context
docker --context colima-x64 buildx build --load -t pwnbox .

# 6) install launcher
install -m 0755 ./pwnbox /usr/local/bin/pwnbox
```

If build seems stuck, run with plain progress:
```bash
docker --context colima-x64 buildx build --progress=plain --load -t pwnbox .
```

## How pwnbox works
- `pwnbox` starts Colima profile `x64` (amd64 via QEMU) if needed
- startup uses `--activate=false` to avoid docker context switching
- payloads go into persistent container `pwnbox-main`
- default mode is non-privileged (`SYS_PTRACE` + default seccomp)
- each run creates `/home/<name>_<hex>/`
  - for file input: copies file and sets `+x` on that file
  - for directory input: copies directory contents and applies `u+rwX,go+rX`
- after shell exit it can stop Colima (depends on `PWNBOX_STOP_COLIMA` and interactive mode)

## Commands
Enter container shell:
```bash
pwnbox
```

Copy file and open shell in copied dir:
```bash
pwnbox ./a.out
```

Copy directory and open shell:
```bash
pwnbox ./challenge_dir
```

Directory copy safety guard (`PWNBOX_DIR_FILE_LIMIT`, default `5` top-level entries):
```bash
pwnbox --force-dir ~/Downloads
```

Clear copied payloads (keeps container):
```bash
pwnbox --clear
```

Show size info:
```bash
pwnbox --size
```

Remove container:
```bash
pwnbox --rm
```

## Optional env vars
```bash
export PWNBOX_PROFILE=x64
export PWNBOX_DOCKER_CONTEXT=colima-x64
export PWNBOX_IMAGE=pwnbox
export PWNBOX_CONTAINER=pwnbox-main
export PWNBOX_DIR_FILE_LIMIT=5
export PWNBOX_STOP_COLIMA=ask

# security/compatibility
export PWNBOX_PRIVILEGED=no
export PWNBOX_SECCOMP=unconfined
```
