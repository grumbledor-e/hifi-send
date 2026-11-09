# hifi send

**norns, across the room.**

A background mod that sends the main stereo mix to an AirPlay or Chromecast receiver. Choose a speaker, leave the menu, keep making music.

`norns → wi-fi → hi-fi`

---

### listen

Open **SYSTEM → MODS → hifi-send**.

| Control | Action |
| :--- | :--- |
| **E2** | Select a device or action |
| **K3** | Connect, disconnect, refresh or apply |
| **E3** | Wireless volume; adjust buffer or cover on their rows |
| **K2** | Return to norns; streaming continues |

**[air]** is AirPlay. **[cast]** is Chromecast. One receiver at a time.

### now playing

Receivers that show track info display the running script as the title, its author as the artist, and the loaded PSET's name as the album (**norns** until a PSET is loaded). The cover is a snapshot of the norns screen. Set how often it refreshes on the **cover** row: off, or every 3–60 seconds. Menus are never captured.

The author comes from the norns.community catalog, else an `@name` in the script's header, else the GitHub owner of the install. Run `setup.sh` again after updating, so OwnTone finds its metadata pipe.

### a little distance

Designed for listening to patches and generative music. Network playback is delayed: in testing, AirPlay was around **one second**, Chromecast around **three seconds**. The backend buffer is only one part of that delay.

Start at **500 ms**. Disconnect before changing the buffer, then apply, refresh and reconnect. AirPlay requires **more than 250 ms** in this backend; Cast accepts lower settings without guaranteeing a shorter audible delay.

### compatibility

Tested setup: **Norns Shield / Raspberry Pi 3, Raspbian Bullseye, OwnTone 29.3**, with **Yamaha R-N303** and **Cambridge Audio MXN10**.

### install

Paste into Maiden:

```text
;install https://github.com/grumbledor-e/hifi-send
```

Then SSH into Norns and run:

```bash
cd ~/dust/code/hifi-send
bash setup.sh
```

Enable **hifi-send** in **SYSTEM → MODS**, then reboot.

The installer handles dependencies and OwnTone setup on Bullseye.

[Maiden, Mac, Windows & Chromebook instructions →](INSTALL.md)

**Remove:** run `bash uninstall.sh` from the installed project folder before deleting it; then disable the mod and reboot.

**0.2.2 · beta.** This release packages the tested streaming approach with revised setup and buffer checks; the revised installer still needs a fresh-device test.

---

Built on [OwnTone](https://owntone.github.io/owntone-server/), [FFmpeg](https://ffmpeg.org/) and [norns mods](https://github.com/monome/norns-example-mod). MIT licensed; dependencies retain their own licences.
