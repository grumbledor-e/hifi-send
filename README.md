# hifi send

**norns, across the room.**

A background mod that sends the main stereo mix to an AirPlay or Chromecast receiver. Choose a speaker, leave the menu, keep making music.

`norns → wi-fi → hi-fi`

---

### listen

Open **SYSTEM → MODS → hifi-send** (or **hifi-send-0.2.2** for the versioned repository).

| Control | Action |
| :--- | :--- |
| **E2** | Select a device or action |
| **K3** | Connect, disconnect, refresh or apply |
| **E3** | Wireless volume; adjust buffer on its row |
| **K2** | Return to norns; streaming continues |

**[air]** is AirPlay. **[cast]** is Chromecast. One receiver at a time.

### a little distance

Designed for listening to patches and generative music. Network playback is delayed: in testing, AirPlay was around **one second**, Chromecast around **three seconds**. The backend buffer is only one part of that delay.

Start at **500 ms**. Disconnect before changing the buffer, then apply, refresh and reconnect. AirPlay requires **more than 250 ms** in this backend; Cast accepts lower settings without guaranteeing a shorter audible delay.

### compatibility

Tested setup: **Norns Shield / Raspberry Pi 3, Raspbian Bullseye, OwnTone 29.3**, with **Yamaha R-N303** and **Cambridge Audio MXN10**. The MXN10 can feed an amplifier such as the Arcam A25+.

AirPlay-capable Sonos models are expected to work, but have not been tested with this mod. **Play:5 Gen 1 and Play:1 have no direct support.** Password/PIN entry, automatic reconnect and synchronised multiroom playback are not included.

### install

Paste into Maiden:

```text
;install https://github.com/grumbledor-e/hifi-send-0.2.2
```

Then SSH into Norns and run:

```bash
cd ~/dust/code/hifi-send-0.2.2
bash setup.sh
```

Enable **hifi-send-0.2.2** in **SYSTEM → MODS**, then reboot.

The installer handles dependencies and OwnTone setup on Bullseye.

[Maiden, Mac, Windows & Chromebook instructions →](INSTALL.md)

**Remove:** run `bash uninstall.sh` from the installed project folder before deleting it; then disable the mod and reboot.

**0.2.2 · beta.** This release packages the tested streaming approach with revised setup and buffer checks; the revised installer still needs a fresh-device test.

---

Built on [OwnTone](https://owntone.github.io/owntone-server/), [FFmpeg](https://ffmpeg.org/) and [norns mods](https://github.com/monome/norns-example-mod). MIT licensed; dependencies retain their own licences.
