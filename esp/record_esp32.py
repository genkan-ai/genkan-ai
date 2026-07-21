# Copyright (c) 2026 Shion Oba, Rui Yokokura. All Rights Reserved.
# Viewing and evaluation only. Unauthorized use, copying, modification, or distribution is prohibited.

import math
import struct
import subprocess
import time
import wave

import serial

PORT = "/dev/cu.usbserial-10"
BAUD_RATE = 115200

SAMPLE_RATE = 8000
RECORD_SECONDS = 5
SAMPLE_COUNT = SAMPLE_RATE * RECORD_SECONDS

OUTPUT_FILE = "esp32-mic-filtered.wav"


def wait_for_line(
    ser: serial.Serial,
    target: str,
    timeout_seconds: float,
) -> None:
    deadline = time.time() + timeout_seconds

    while time.time() < deadline:
        line = ser.readline().decode(
            "ascii",
            errors="ignore",
        ).strip()

        if line:
            print(f"ESP32: {line}")

        if line == target:
            return

    raise TimeoutError(
        f"ESP32から{target}を受信できませんでした"
    )


def receive_samples(ser: serial.Serial) -> list[int]:
    samples: list[int] = []
    deadline = time.time() + 90

    while len(samples) < SAMPLE_COUNT:
        if time.time() > deadline:
            raise TimeoutError(
                f"受信がタイムアウトしました: "
                f"{len(samples)}/{SAMPLE_COUNT}"
            )

        line = ser.readline().decode(
            "ascii",
            errors="ignore",
        ).strip()

        if not line:
            continue

        if line == "END":
            break

        try:
            value = int(line)
        except ValueError:
            continue

        # ESP32の12bit ADCとして有効な値だけ採用
        if 0 <= value <= 4095:
            samples.append(value)

        if len(samples) % 1000 == 0:
            progress = len(samples) / SAMPLE_COUNT * 100
            print(
                f"\r受信中: {progress:5.1f}%",
                end="",
                flush=True,
            )

    print()

    if len(samples) != SAMPLE_COUNT:
        raise RuntimeError(
            f"サンプル数が不足しています: "
            f"{len(samples)}/{SAMPLE_COUNT}"
        )

    return samples


def filter_audio(samples: list[int]) -> list[int]:
    average = sum(samples) / len(samples)

    print(f"ADC平均値: {average:.1f}")
    print(f"ADC最小値: {min(samples)}")
    print(f"ADC最大値: {max(samples)}")
    print(f"ADC振れ幅: {max(samples) - min(samples)}")

    centered = [
        float(sample) - average
        for sample in samples
    ]

    # USB電源などの低いノイズを削る
    highpass_cutoff = 250.0
    dt = 1.0 / SAMPLE_RATE
    highpass_rc = 1.0 / (
        2.0 * math.pi * highpass_cutoff
    )
    highpass_alpha = highpass_rc / (
        highpass_rc + dt
    )

    highpassed: list[float] = []
    previous_input = centered[0]
    previous_output = 0.0

    for value in centered:
        output = highpass_alpha * (
            previous_output
            + value
            - previous_input
        )

        highpassed.append(output)
        previous_input = value
        previous_output = output

    # 高域のADCノイズも軽く削る
    lowpass_cutoff = 3200.0
    lowpass_rc = 1.0 / (
        2.0 * math.pi * lowpass_cutoff
    )
    lowpass_alpha = dt / (
        lowpass_rc + dt
    )

    filtered: list[float] = []
    previous_output = 0.0

    for value in highpassed:
        previous_output += lowpass_alpha * (
            value - previous_output
        )
        filtered.append(previous_output)

    # 一瞬の大きな接触ノイズを基準にしない
    absolute_values = sorted(
        abs(value)
        for value in filtered
    )

    reference_index = int(
        len(absolute_values) * 0.995
    )
    reference = absolute_values[reference_index]

    if reference < 1.0:
        reference = 1.0

    gain = min(200.0, 26000.0 / reference)
    print(f"適用ゲイン: {gain:.1f}倍")

    pcm: list[int] = []

    for value in filtered:
        output = int(value * gain)
        output = max(-32768, min(32767, output))
        pcm.append(output)

    return pcm


print(f"ESP32へ接続しています: {PORT}")

with serial.Serial(
    PORT,
    BAUD_RATE,
    timeout=2,
) as ser:
    print("ESP32の起動を待っています...")

    time.sleep(2)
    ser.reset_input_buffer()

    wait_for_line(ser, "READY", 10)

    ser.write(b"R")
    ser.flush()

    wait_for_line(ser, "ACK", 5)

    print(
        f"{RECORD_SECONDS}秒間録音します。"
        "マイクを口元から1〜2cmにしてください。"
    )

    wait_for_line(ser, "DATA", 10)
    samples = receive_samples(ser)

pcm = filter_audio(samples)

with wave.open(OUTPUT_FILE, "wb") as wav:
    wav.setnchannels(1)
    wav.setsampwidth(2)
    wav.setframerate(SAMPLE_RATE)
    wav.writeframes(
        struct.pack(
            f"<{len(pcm)}h",
            *pcm,
        )
    )

print(f"保存しました: {OUTPUT_FILE}")
subprocess.run(
    ["afplay", OUTPUT_FILE],
    check=True,
)
