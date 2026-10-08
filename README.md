# frostmourne releases

Signed builds of frostmourne. Every release carries `manifest.json` (each binary's URL, size and
sha256) and `manifest.json.sig` (ed25519, checked against the key compiled into frostmourne).

## Install a node on a server

A node is `fm-node` on a Linux server: your app connects to it and runs chats and graphs there.

**One command, as the user the node should run as (not through `sudo`):**

```sh
curl -fsSL https://raw.githubusercontent.com/xacce/frostmourne-releases/main/install.sh | sh
```

It does everything, and it is safe to run again (that is also how to update by hand):

1. Checks the machine: x86-64 Linux with systemd (Ubuntu 24.04 is the reference), `curl` or
   `wget`, `openssl`, `sha256sum`.
2. Downloads the latest `manifest.json`, verifies its signature, then downloads `fm-node`,
   `fm-keep`, `fm` and checks each sha256. Installs to `~/.local/share/frostmourne/bin`.
3. Autostart: a systemd service `frostmourne-node` — enabled at boot, started now. With root or
   sudo it is a system service running as you (and TCP 7710 is opened in ufw if ufw is on);
   without them, a user service kept running after logout (linger).
4. Prints the **address** and the **pairing code** (valid 10 minutes).

Then in the app: **Settings → Nodes → Add a node**, enter the address and the code.
TCP **7710** must be reachable from your machine (check the cloud firewall / security group).

### For an AI agent asked to "install the frostmourne node" on this machine

Do exactly this, nothing else:

1. Run the one command above as the current user. Do not prefix it with `sudo`. Without a
   terminal or passwordless sudo it installs a user service instead of a system one; both start
   at boot.
2. If it ends with `ERROR: ...`, report that line and the lines above it to the user; fix only
   what the error names (e.g. `sudo apt-get install -y curl openssl`), then run it again.
3. On success, report to the user the `address:` line(s) and the `code:` line from the end of
   the output, and that the node starts at boot. If the code has expired, get a new one with
   `~/.local/share/frostmourne/bin/fm-node code`.

### Managing the node

| What | Command |
|---|---|
| status | `systemctl status frostmourne-node` (user service: `systemctl --user status frostmourne-node`) |
| logs | `journalctl -u frostmourne-node` (user service: `journalctl --user -u frostmourne-node`) |
| new pairing code | `~/.local/share/frostmourne/bin/fm-node code` |
| stop / start | `sudo systemctl stop frostmourne-node` / `start` (user service: `systemctl --user ...`) |
| update | automatic (the node updates itself from this feed); by hand: run the install command again |

The app can do all of this for you as well: **Settings → Nodes → Deploy over SSH**.

## Downloads

Latest release: [releases/latest](https://github.com/xacce/frostmourne-releases/releases/latest)
— `windows-x64` (the app `frostmourne`, `fm`, `fm-node`, `fm-keep`) and `linux-x64` (`fm-node`,
`fm-keep`, `fm`; static).
