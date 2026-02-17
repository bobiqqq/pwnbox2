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
docker --context colima-x64 buildx build --load -t pwnbox .
# (outside colima-x64 context, add: --platform linux/amd64)

# 5) install the launcher script OPTIONAL BUT RECOMMENDED FOR FAST EXEC
install -m 0755 ./pwnbox /usr/local/bin/pwnbox