#!/bin/sh

# 1. Read CPU package temperature via platform hwmon
raw_cpu=""
for f in /sys/devices/platform/coretemp.0/hwmon/hwmon*/temp1_input; do
    read -r raw_cpu < "$f" 2>/dev/null && break
done
cpu_temp=$(( ${raw_cpu:-0} / 1000 ))

# 2. Read NVIDIA PCI power state directly without waking GPU
read -r gpu_state < /sys/bus/pci/devices/0000:01:00.0/power_state 2>/dev/null
gpu_state=${gpu_state:-"unknown"}

# 3. Only query nvidia-smi if GPU is in D0 AND an application has /dev/nvidia0 open
if [ "$gpu_state" = "D0" ] && fuser -s /dev/nvidia0 2>/dev/null; then
    data=$(nvidia-smi --query-gpu=temperature.gpu,utilization.gpu,memory.used,memory.total --format=csv,noheader,nounits 2>/dev/null)
    if [ -n "$data" ]; then
        gpu_temp=$(echo "$data" | awk -F', ' '{print $1}')
        gpu_util=$(echo "$data" | awk -F', ' '{print $2}')
        gpu_mem=$(echo "$data" | awk -F', ' '{print $3}')
        gpu_maxmem=$(echo "$data" | awk -F', ' '{print $4}')

        pids=$(fuser /dev/nvidia0 2>/dev/null)
        apps=$(ps -o comm= -p $pids 2>/dev/null | sort -u | paste -sd, - | sed 's/,/, /g')

        text=" ${cpu_temp}°C · ${gpu_temp}°C"
        tooltip="CPU: ${cpu_temp}°C\nNVIDIA GPU: D0\n  Temperature: ${gpu_temp}°C\n  Usage: ${gpu_util}%\n  VRAM: ${gpu_mem} / ${gpu_maxmem} MB\n  Active by: ${apps:-"client"}"
        class="D0"

        if [ "${gpu_temp:-0}" -ge 85 ] || [ "$cpu_temp" -ge 85 ]; then
            class="D0 critical"
        elif [ "${gpu_temp:-0}" -ge 70 ] || [ "$cpu_temp" -ge 70 ]; then
            class="D0 warning"
        fi
    else
        text=" ${cpu_temp}°C · D0"
        tooltip="CPU: ${cpu_temp}°C\nNVIDIA GPU: D0"
        class="D0"
    fi
else
    text=" ${cpu_temp}°C · ${gpu_state}"
    tooltip="CPU: ${cpu_temp}°C\nNVIDIA GPU: ${gpu_state}"
    class="${gpu_state}"

    if [ "$cpu_temp" -ge 85 ]; then
        class="${class} critical"
    elif [ "$cpu_temp" -ge 70 ]; then
        class="${class} warning"
    fi
fi

printf '{"text": "%s", "tooltip": "%s", "class": "%s"}\n' "$text" "$tooltip" "$class"
