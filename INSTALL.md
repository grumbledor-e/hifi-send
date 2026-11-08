# install · hifi send

**Install in Maiden → connect → run setup.** The installer handles dependencies, OwnTone and services. Internet access is needed on Norns for a fresh install; keep your computer and Norns on the same network.

Automatic fresh installation currently targets **Raspbian Bullseye**, tested with a Pi 3 Norns Shield. Other OS versions need [OwnTone 29+ installed separately](https://owntone.github.io/owntone-server/installation/) before running setup. The new automated installer has been simulated locally, not yet tested on a fresh Norns.

## Maiden install

Paste this into Maiden's command line, to install the project:

```text
;install https://github.com/grumbledor-e/hifi-send
```

Once installed, open Terminal on Mac, PowerShell on Windows, or Terminal → penguin on Chromebook:

```bash
ssh we@norns.local
```

Then, in the Norns SSH session:

```bash
cd ~/dust/code/hifi-send
bash setup.sh
```

After **Setup complete**, enable **hifi-send** in **SYSTEM → MODS** and reboot. Maiden downloads the project; this one SSH setup installs its background audio services. Keep only one installed copy. The folder must be named `hifi-send`; use GitHub release tags for version numbers.

**Remove:** in SSH, run `bash ~/dust/code/hifi-send/uninstall.sh` before deleting the folder, then disable the mod and reboot.

---

## ZIP alternative

## 1 · send the download to norns

Download **hifi-send-v0.2.2.zip**. Keep it zipped.

### Mac

Open **Terminal**. With the ZIP in Downloads:

```bash
scp ~/Downloads/hifi-send-v0.2.2.zip we@norns.local:
ssh we@norns.local
```

### Windows 10 / 11

Open **PowerShell** or **Windows Terminal → PowerShell**. With the ZIP in Downloads:

```powershell
scp "$HOME\Downloads\hifi-send-v0.2.2.zip" we@norns.local:
ssh we@norns.local
```

If `ssh` or `scp` is not recognised, install **OpenSSH Client** through Windows **Optional features**, then reopen PowerShell. You do not need OpenSSH Server, WSL or PuTTY. See [Microsoft's OpenSSH guide](https://learn.microsoft.com/windows-server/administration/openssh/openssh_install_firstuse).

### Chromebook

In the Files app, copy the ZIP into **Linux files**. Open **Terminal → penguin**:

```bash
scp ~/hifi-send-v0.2.2.zip we@norns.local:
ssh we@norns.local
```

If Linux is not enabled, set up **Linux development environment** in ChromeOS Settings first.

**For all three:** enter your Norns password (`sleep` unless changed). Password typing is invisible. If prompted to trust the host, check that the address is your Norns, then enter `yes`. If `norns.local` fails, replace it in both commands with the IP address shown on Norns. Run `scp` from your computer, before entering the SSH session. Adjust the local file path if you saved the ZIP elsewhere.

## 2 · run setup on norns

Once logged into Norns, paste:

```bash
unzip -o ~/hifi-send-v0.2.2.zip -d ~/dust/code/
cd ~/dust/code/hifi-send
bash setup.sh
```

Enter your Norns password if sudo asks. Wait for **Setup complete**; if an error appears, stop and keep the output. Do not run a general OS upgrade.

For an update, disconnect the stream and follow these same steps. Existing data and working buffer settings above 250 ms are retained. Fresh installs start at **500 ms**.

## 3 · enable and listen

Enable **hifi-send** in **SYSTEM → MODS**, then save your work and reboot Norns. Open its mod menu, refresh devices and connect. Streaming continues when you leave the menu or close SSH. On updates, reboot to load the new menu too.

**That's the complete normal installation.**

<details>
<summary><strong>Recover from the old dotted folder name</strong></summary>

Norns' mod scanner accepts letters, numbers, underscores and hyphens. A folder such as `hifi-send-0.2.2` is invalid even when its mod is disabled. Move any such old folder outside `dust/code` before opening MODS again; keep data/settings. Reboot after removing an installed mod before revisiting the MODS menu, so its list selection resets. Do not edit Norns core or delete other mods.

If you renamed the GitHub repository, use `https://github.com/grumbledor-e/hifi-send` directly. Old GitHub URLs may redirect but can still produce the old directory name in an installer.

</details>

<details>
<summary><strong>If something goes wrong</strong></summary>

Run in Norns SSH:

```bash
bash ~/dust/code/hifi-send/diagnose.sh
sudo journalctl -u norns-hifi-worker.service -n 50 --no-pager
```

- No speakers: check the same LAN, receiver awake, and guest Wi-Fi isolation.
- AirPlay won't connect: set the backend buffer to **500 ms**; it must be above 250 ms. Disconnect before changing it; K3 applies, then refresh and reconnect.
- Worker offline: `sudo systemctl restart norns-hifi-worker.service`.
- Password refused: use/reset the Norns password, not the computer password.
- Wrong ZIP path: check its filename and location on your computer, including duplicate-download suffixes.

A report should include Norns model/OS, receiver, protocol, buffer and relevant logs. Review logs for local IPs/device names before posting.

</details>

<details>
<summary><strong>What the installer changes</strong></summary>

On a fresh Bullseye setup it adds the [maintainer's OwnTone repository](https://forums.raspberrypi.com/viewtopic.php?t=49928), installs OwnTone 29+, FFmpeg, JACK tools and Python, and prevents the package's default server from starting. Package operations refuse removals. It does not perform a general distribution upgrade. An existing suitable OwnTone install skips repository setup.

It creates data in `~/dust/data/hifi-send/`, enables `norns-hifi-owntone.service` and `norns-hifi-worker.service`, and grants only the specific password-free service restart needed by the buffer menu. Services run as the normal user; the worker receives real-time/memory-lock limits and stays active for discovery even when the mod is disabled.

It writes `RemoveIPC=no` to `/etc/systemd/logind.conf.d/90-hifi-send.conf` to preserve audio IPC on logout; this affects system-wide logout cleanup and needs a reboot. Norns core and its JACK service are not edited. Config is backed up as `owntone.conf.before-v021`. Runtime API: port 3691, localhost trusted, remote admin password, no mod web UI. No audio recordings are saved; logs/databases persist and can grow.

</details>

<details>
<summary><strong>Remove</strong></summary>

Disconnect and disable the mod, then run:

```bash
cd ~/dust/code/hifi-send
bash uninstall.sh
```

Reboot. This removes its services, sudoers rule and logind drop-in. It keeps code, data, packages, package-source/key files and any earlier manually installed logout fixes. The default OwnTone service is not re-enabled automatically.

</details>
