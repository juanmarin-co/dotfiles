# Razer RZ09-0328: Linux Performance Control

This document describes performance modes, fan control, temperature monitoring, and communication with the embedded controller (EC) using Razer’s proprietary protocol over USB HID on the Razer Blade 15 Base (Early 2020).

## Embedded Controller and Linux Support

The **embedded controller (EC)** is a microcontroller inside the laptop that runs firmware independently of Linux. It manages the fans and participates in enforcing CPU/GPU power policies. On Windows, **Razer Synapse** exposes performance modes and fan controls, but Synapse is not available for Linux.

Many laptops expose performance and cooling controls through Linux drivers and standard interfaces such as `platform_profile` and `hwmon`. The RZ09-0328 does not currently expose its Razer controls through those interfaces. Linux tools instead reproduce Synapse’s proprietary commands over USB HID.

## Performance and Fan Control

**Performance control** selects the firmware policy for CPU/GPU power and cooling. Named modes such as Balanced and Gaming select presets, while Custom mode provides separate CPU and GPU levels. These levels are firmware-defined settings, not explicit wattage limits.

**Fan control** determines who selects the fan-speed target. With automatic control, the firmware chooses it. With manual control, software supplies a fixed RPM target. A software-defined temperature curve also uses manual control: the application reads temperatures, calculates a target, and periodically updates it rather than uploading the curve to the EC.

Razer performance modes are separate from Linux power profiles. Tools such as TLP and `power-profiles-daemon` configure kernel power-management settings; on this model, they do not select the proprietary Razer performance mode.

## USB HID Communication

Software controls the RZ09-0328’s fans and performance settings through **USB HID (Human Interface Device)**. The built-in Razer USB device has vendor ID `1532` and product ID `0255`, conventionally written as **`1532:0255`**.

Commands travel inside **HID Feature Reports**, messages for querying or configuring a device. Each exchange sends a command with `SET_REPORT` and retrieves its response with `GET_REPORT`. HID defines the transport; Razer defines the command format.

The device exposes three HID interfaces: interface `0` declares keyboard functions, interface `1` declares additional keyboard, media, and system controls, and interface `2` declares mouse-style input and vendor Feature Reports. Despite their different declared capabilities, all three support fan control and switching between Balanced and Gaming performance modes. They access shared settings, not independent copies.

Linux exposes each interface as `/dev/hidrawN`. Vendor ID, product ID, and interface number identify the interface independently of device-node numbering, which can change between boots. The daemon selects interface `2`, matching [Synapse product 597’s middleware entry](https://apps.razer.com/synapse/products/597/mw/main.a1e24f33c1759c4315e3.js). Earlier local fan/mode tests used interface `0`; matching the vendor interface does not by itself establish identical physical behavior. Applications exchange reports directly through `ioctl` or through the **hidapi** library.

Access requires read/write permission on the device node. Multiple applications can communicate with the controller, so software should validate responses and handle communication failures.

## Razer Command Protocol

Razer uses a proprietary, reverse-engineered packet format for requests and responses. Each packet contains a command, its arguments, and fields for validating the exchange.

The packet is 90 bytes. Linux HID buffers include a leading report-ID byte, producing this **91-byte layout**:

| Offset | Size | Field | Meaning |
|---|---|---|---|
| `0` | 1 byte | Report ID | HID report identifier: `0x00`. |
| `1` | 1 byte | Status | Requests contain `0x00`; responses indicate success, busy, or an error. |
| `2` | 1 byte | Transaction ID | Echoed in the response to correlate it with the request. |
| `3–4` | 2 bytes | Remaining packets | Additional packets in a sequence; zero for single-packet exchanges. |
| `5` | 1 byte | Protocol type | `0x00`; other values are undocumented. |
| `6` | 1 byte | Argument length | Number of meaningful argument bytes, up to 80. |
| `7` | 1 byte | Command class | Function group. |
| `8` | 1 byte | Command ID | Operation within the function group. |
| `9–88` | 80 bytes | Arguments | Operation-specific data; unused bytes are zero. |
| `89` | 1 byte | Checksum | XOR of buffer bytes `3–88`, inclusive. |
| `90` | 1 byte | Reserved | `0x00`. |

### Status

| Value | Meaning |
|---|---|
| `0x00` | New request |
| `0x01` | Command busy |
| `0x02` | Command succeeded |
| `0x03` | Command failed |
| `0x04` | Command timed out |
| `0x05` | Command unsupported |

The controller processes a request before its response becomes available. Response validation covers the packet length, checksum, transaction ID, command, and relevant arguments. A successful USB transfer alone does not establish command success; the response status carries that result.

## Fan and Performance Commands

Fan and performance commands use command class **`0x0d`**. They address two firmware targets, selected by `1` or `2`. For custom performance levels, these select the CPU and GPU respectively. Consistent performance-mode and fan-control settings involve both targets.

Each response echoes the request’s transaction ID, command class, and command ID. The response arguments below describe successful responses, with status **`0x02`**. Argument indices are zero-based and relative to the packet’s argument area.

| Command ID | Operation | Request arguments | Successful response |
|---|---|---|---|
| `0x82` | Read mode and fan control | `[0, target, 0, 0]` | `[0, target, mode, manual]` |
| `0x02` | Set mode and fan control | `[1, target, mode, manual]` | Acknowledgement; stored state available through `0x82` |
| `0x81` | Read stored fan target | `[0, target, 0]` | `[0, target, rpm_units]` |
| `0x01` | Set fan target | `[1, target, rpm_units]` | Acknowledgement; stored target available through `0x81` |
| `0x87` | Read custom level | `[0, target, 0]` | `[0, target, level]` |
| `0x07` | Set custom level | `[0, target, level]` | Acknowledgement; stored level available through `0x87` |

The mode and fan-target setters above follow [Synapse product 597’s policy](https://apps.razer.com/synapse/products/597/mw/6737.6da70458ec9e64b00f37.js): setters use profile/class `1`, while getters use `0`. Earlier local tests use `0` for setters and confirm stored-state readback; those tests do not establish equivalence to the vendor sequence. Custom-level examples below retain that earlier test format.

A successful setter acknowledgement confirms acceptance, not the physical effect. The corresponding getter provides stored-state verification independently of the setter’s response arguments.

### Performance Modes

Command `0x02` sets performance mode and fan control together. A change to one field should preserve the other unless both changes are intended.

| Value | Community name |
|---|---|
| `0x00` | Balanced |
| `0x01` | Gaming |
| `0x02` | Creator |
| `0x04` | Custom |
| `0x05` | Silent |

All listed values are accepted and read back unchanged on both targets. Their distinct power/performance effects remain unmeasured. The [official guide, page 15](https://dl.razer.com/master-guides/RazerSynapse3/Blade-00000597-en.pdf), identifies Balanced as Default, Gaming as Increase Graphics Power, and Creator as Increase Processor Power. Gaming and Creator require external power in Synapse. Custom and Silent remain absent from this model’s vendor-supported preset list despite accepting stored values.

### Custom Performance Levels

Custom mode with automatic fans corresponds to `0x02` arguments `[0, target, 4, 0]` on both targets. Command `0x07` configures each component independently, and `0x87` returns its level in response argument `2`.

| `target` | Component |
|---|---|
| `1` | CPU |
| `2` | GPU |

| `level` | Meaning |
|---|---|
| `0` | Low |
| `1` | Medium |
| `2` | High |

For example, `0x07` arguments `[0, 1, 2]` select CPU High, while `[0, 2, 0]` select GPU Low. Changing one component preserves the other.

Write/readback support is verified for all six CPU/GPU settings. Their wattage and performance effects remain unmeasured. CPU level `3`, labelled Boost by some tools, is untested for this model.

### Fan Control and RPM

| `manual` | Meaning |
|---|---|
| `0` | Firmware selects fan speed |
| `1` | Software supplies the fan target |

A fixed-speed request consists of enabling manual control with `0x02`, followed by setting the target with `0x01`. Clearing the manual flag restores automatic control. The daemon follows this order on each target and waits 200 ms after the mode-command acknowledgement before readback, matching the post-command delay in [Synapse’s protocol implementation](https://apps.razer.com/synapse/products/597/mw/rzDevice25.ae57bbfa911460c03510.js). RPM-only updates while already manual do not rewrite the mode or incur this settling delay.

Razer encodes the fan target as **one unsigned byte in 100-RPM units**:

```text
rpm_units = RPM ÷ 100
RPM       = rpm_units × 100
```

For example, 3500 RPM corresponds to `35` (`0x23`), and 5000 RPM to `50` (`0x32`). Targets have 100-RPM increments. The byte’s numeric range is not the fan’s supported operating range.

Command `0x81` returns the stored target in response argument `2`, using the same units. Setting a target while automatic control is selected updates this value without enabling manual control. Its effect on physical fan speed in that state remains untested.

**The stored target is not measured fan speed.** It remains readable after switching to automatic control and can remain unchanged during CPU/GPU load. It should not be presented as the current automatic fan speed.

## Temperature Monitoring

CPU and GPU temperatures are available independently of Razer’s HID commands. Software-defined fan curves use these readings to calculate fan targets.

### CPU Temperature

The kernel’s **`coretemp`** driver exposes CPU temperatures under `/sys/class/hwmon/`. The CPU package sensor belongs to the directory whose `name` is `coretemp`, with a `temp*_label` containing `Package id 0`. Its matching `temp*_input` file holds the temperature. Directory numbering can change between boots.

CPU readings are in **millidegrees Celsius**: `65000` means **65°C**.

### GPU Temperature

NVIDIA GPU temperature is available through **NVML (NVIDIA Management Library)** and `nvidia-smi`’s `temperature.gpu` query. Both report **degrees Celsius** directly: `65` means **65°C**.

GPU telemetry can affect power management. **D0** is the operational PCI power state, **D3hot** retains power while suspended, and **D3cold** removes main power. The GPU’s PCI sysfs directory exposes this state through `power_state`; `power/runtime_status` separately reports Linux’s runtime state, such as `active` or `suspended`. Reading these attributes does not wake the GPU.

NVML initialization can wake the GPU before any temperature query. To avoid unnecessary wakeups, GPU temperature monitoring should run only when another application has the GPU open and it is **D0/active**. Each reading should use a short NVML session that closes immediately afterward.

`fuser` identifies processes with the GPU’s device node open, such as `/dev/nvidia0`, by inspecting `/proc`. This check does not wake a suspended GPU. The monitor and its telemetry subprocesses do not count as other applications.

An open client does not necessarily mean active rendering, and the checks are not atomic. This approach allows suspension in controlled tests but does not guarantee identical behaviour across applications or drivers. When sampling is skipped, GPU temperature is unavailable, not zero.

## Controller Policy

The policies below are local choices, not a reproduction of Synapse’s automatic behavior. Synapse also checks adapter wattage and forces Balanced/automatic when external power is insufficient; the daemon currently checks only AC presence. Synapse discovers fan IDs from firmware, while this model-specific daemon uses the locally tested targets `1` and `2`. Protocol readback verifies stored settings, not physical fan speed or CPU/GPU power limits. Interface selection, manual-entry ordering, and settling time are aligned with the inspected vendor code; the revised sequence still requires live validation on this unit.

`system/usr/local/bin/rz09-control` selects Gaming when the NVIDIA GPU is D0/active with a client and `/sys/class/power_supply/AC0/online` reads `1`. Otherwise it selects Balanced; missing AC status does not enable Gaming. This checks AC presence, not adapter wattage. The controller applies the EC preset only, not Synapse’s separate Windows GPU/VRAM tuning.

Intel CPU turbo is allowed only on confirmed AC power (`AC0/online=1`), in Balanced, while the NVIDIA GPU is confirmed powered off: PCI `power_state=D3cold` and `power/runtime_status=suspended`. Battery power or missing/unknown AC status disables turbo regardless of GPU state. An awake GPU disables turbo even without clients; missing, unknown, and transitional GPU power states also disable it. The daemon checks every poll, independently of fan or performance-mode changes, using sysfs without waking the GPU. Turbo is disabled before hardware changes when policy requires it; before allowing turbo, the GPU state is checked again after hardware changes because fan-mode changes can wake it. Detection is polled, not atomic with AC changes or GPU wakeups. Shutdown and reset disable turbo because no running monitor remains to track the GPU. This is an explicit policy, not restoration of an arbitrary prior value. The switch is `/sys/devices/system/cpu/intel_pstate/no_turbo` (`0` allows turbo, `1` disables it); writes occur only when needed and require readback. `max_perf_pct` is unchanged. Leave TLP’s `CPU_BOOST_ON_AC/BAT/SAV` unset so TLP does not compete for this switch. The daemon’s status socket reports whether turbo is allowed. The systemd service mounts the Intel P-state directory read-only with a writable exception for `no_turbo`, retaining the other sandbox settings.

Cooling is independent of performance selection and applies to CPU-only workloads too. Both fan channels receive the same target from `max(CPU, available or held GPU temperature)`. Manual control starts after at least 60°C continuously for 5 seconds, with targets of 3500 RPM from 60°C, 4000 RPM from 70°C, 4500 RPM from 75°C, and 5000 RPM from 80°C. Manual steps have 2°C downward hysteresis. Below 58°C, the controller holds at least 3500 RPM until 30 continuous seconds elapse, then returns to firmware automatic control. GPU temperature demand persists for 30 seconds after telemetry disappears. Suspend and CPU sensor failure interrupt continuous-temperature timers.

At 85°C, high-temperature cooling requests 5000 RPM without overriding the selected performance mode. It remains active until the control temperature stays at or below 80°C for 30 seconds. These are policy thresholds, not hardware emergency limits. CPU sensor failure, shutdown, and reset request Balanced/automatic control. The daemon’s status socket reports latched high-temperature cooling.

### Quickshell Monitoring

The Cooling widget reads newline-delimited JSON from `/run/rz09-control/status.sock` through one shared Quickshell socket connection. The daemon publishes once per second; the UI performs no additional hardware or NVML queries. It shows CPU/GPU temperatures, fan control and target RPM, hardware mode, turbo policy, and available GPU utilization, VRAM, and device clients. Target RPM is not measured fan speed. Missing GPU readings are not zero. Disconnected or five-second-old data is cleared, and the client reconnects automatically. TLP power profiles remain separate from the controller’s hardware mode. The former Waybar adapter has been removed; the CLI retains `daemon` and `reset`.

`ac_online` is `true` for confirmed AC, `false` for battery power, and `null` when unknown; unknown AC still disables Gaming and turbo. `cpu_turbo_reason` and `control.fan_reason` report policy reasons from the daemon, not UI guesses. `control.control_temp_c` includes any retained GPU temperature used by the fan policy. These fields do not alter hardware decisions. The UI labels firmware manual mode “Custom curve” and automatic mode “Firmware automatic”; generic success messages are hidden. The `healthy` flag means no reported sensor/control error, not proof of physical fan health.

### GPU Wakeups from Fan-Mode Changes

On this unit, switching automatic/manual fans through `0D/02` triggers firmware ACPI method `_Q30`, which sends GPU notification `0xC0`. NVIDIA handles it through `rm_acpi_notify` and acquires a dynamic-power reference, waking the GPU. Live tracing records 27 such notifications aligned with controller fan-mode changes; a three-minute controller pause records none, and the GPU stays in D3cold after its idle delay. Restarting the controller triggers another wake. The GPU USB controller’s resume errors occur downstream of these wakes.

The entry/exit timers reduce unnecessary fan-mode changes from short CPU spikes; they do not make these transitions wake-free. While already manual, the controller changes RPM targets with `0D/01` without rewriting `0D/02`. A hardware test first establishes Balanced/manual at 3500 RPM and waits for 5 continuous seconds in D3cold, then requests 4000, 4500, 5000, and 3500 RPM with independent readback. The GPU remains in D3cold throughout each 10-second observation window, sampled every 250 ms with no GPU clients detected. This verifies wake-free target updates in the tested state, not physical fan RPM.

## Control Lifetime and Recovery

Manual fan settings remain active after the controlling application exits. A fixed target needs no running process, but a software fan curve stops updating when its application stops. Applications should return the fans to automatic control when exiting.

Fan channels and custom CPU/GPU levels receive separate commands. Updates can partially succeed, so readback confirms each setting independently.

Settings may reset after suspend or reboot, so applications should reapply the user’s selected configuration after resume or startup.
